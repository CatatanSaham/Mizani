import Foundation
import SQLCipher

public enum EncryptedDatabaseError: Error, Equatable {
    case directoryUnavailable
    case openFailed(Int32)
    case keyRejected(Int32)
    case sqlCipherUnavailable
    case unreadableDatabase(Int32)
    case unsupportedSchema(Int32)
    case migrationFailed(Int32)
    case statementFailed(Int32)
    case journalModeUnavailable
    case databaseClosed
    case fileProtectionFailed
}

/// Owns the only SQLite connection and serializes all access through actor isolation.
public actor EncryptedFinanceDatabase {
    private enum SQLValue {
        case text(String)
        case integer(Int64)
        case null
    }

    private var handle: OpaquePointer?
    private let databaseURL: URL
    private let balanceValidator: IOSFinanceBalanceValidator?
    private let categoryArchiveValidator: IOSFinanceCategoryArchiveValidator?
    private let incomeSourceKindValidator: IOSFinanceIncomeSourceKindValidator?
    private let investmentAssetTypeValidator: IOSFinanceInvestmentAssetTypeValidator?

    /// Stores the database in a dedicated app-owned directory so protection and backup settings
    /// cannot accidentally affect unrelated Application Support files.
    public init(
        databaseDirectoryURL: URL,
        keyProvider: any DatabaseKeyProviding,
        defaultCategories: [IOSCategorySeed] = [],
        balanceValidator: IOSFinanceBalanceValidator? = nil,
        categoryArchiveValidator: IOSFinanceCategoryArchiveValidator? = nil,
        incomeSourceKindValidator: IOSFinanceIncomeSourceKindValidator? = nil,
        investmentAssetTypeValidator: IOSFinanceInvestmentAssetTypeValidator? = nil
    ) throws {
        let fileManager = FileManager.default
        let directory = databaseDirectoryURL.standardizedFileURL
        let databaseURL = directory.appendingPathComponent("mizani.sqlite", isDirectory: false)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.protect(directory: directory)
        } catch {
            throw EncryptedDatabaseError.directoryUnavailable
        }

        var key = try keyProvider.databaseKey(for: databaseURL)
        defer { key.resetBytes(in: 0..<key.count) }
        guard key.count == 32 else {
            throw EncryptedDatabaseError.keyRejected(SQLITE_MISUSE)
        }

        var openedHandle: OpaquePointer?
        let openStatus = sqlite3_open_v2(
            databaseURL.path,
            &openedHandle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openStatus == SQLITE_OK, let database = openedHandle else {
            if let openedHandle {
                sqlite3_close_v2(openedHandle)
            }
            throw EncryptedDatabaseError.openFailed(openStatus)
        }

        var closeOnFailure = true
        defer {
            if closeOnFailure {
                sqlite3_close_v2(database)
            }
        }

        let keyStatus = key.withUnsafeBytes { bytes in
            sqlite3_key(database, bytes.baseAddress, Int32(bytes.count))
        }
        guard keyStatus == SQLITE_OK else {
            throw EncryptedDatabaseError.keyRejected(keyStatus)
        }

        guard let cipherVersion = try Self.cipherVersion(database), !cipherVersion.isEmpty else {
            throw EncryptedDatabaseError.sqlCipherUnavailable
        }
        do {
            try Self.execute("SELECT count(*) FROM sqlite_master;", on: database)
        } catch {
            throw EncryptedDatabaseError.unreadableDatabase(sqlite3_errcode(database))
        }

        do {
            try Self.execute("PRAGMA foreign_keys = ON;", on: database)
            try Self.execute("PRAGMA cipher_memory_security = ON;", on: database)
            try Self.execute("PRAGMA secure_delete = ON;", on: database)
            try Self.execute("PRAGMA temp_store = MEMORY;", on: database)
            try Self.execute("PRAGMA journal_mode = WAL;", on: database)
            guard let journalMode = try Self.stringValue("PRAGMA journal_mode;", on: database),
                  journalMode.caseInsensitiveCompare("wal") == .orderedSame else {
                throw EncryptedDatabaseError.journalModeUnavailable
            }
            try Self.execute("PRAGMA synchronous = FULL;", on: database)
            try Self.protectDatabaseFiles(at: databaseURL)
            try Self.migrate(database, defaultCategories: defaultCategories)
            try Self.protectDatabaseFiles(at: databaseURL)
        } catch let error as EncryptedDatabaseError {
            throw error
        } catch {
            throw EncryptedDatabaseError.migrationFailed(sqlite3_errcode(database))
        }

        self.handle = database
        self.databaseURL = databaseURL
        self.balanceValidator = balanceValidator
        self.categoryArchiveValidator = categoryArchiveValidator
        self.incomeSourceKindValidator = incomeSourceKindValidator
        self.investmentAssetTypeValidator = investmentAssetTypeValidator
        closeOnFailure = false
    }

    deinit {
        if let handle {
            sqlite3_close_v2(handle)
        }
    }

    public func close() throws {
        guard let handle else { return }
        let status = sqlite3_close_v2(handle)
        guard status == SQLITE_OK else {
            throw EncryptedDatabaseError.statementFailed(status)
        }
        self.handle = nil
    }

    func executeForTesting(_ sql: String) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute(sql, on: handle)
    }

    func textForTesting(_ sql: String) throws -> String? {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw EncryptedDatabaseError.statementFailed(prepareStatus)
        }
        defer { sqlite3_finalize(statement) }

        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_ROW || stepStatus == SQLITE_DONE else {
            throw EncryptedDatabaseError.statementFailed(stepStatus)
        }
        guard stepStatus == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value)
    }

    func readFinanceSnapshot() throws -> IOSLedgerSnapshot {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        var workspace: IOSWorkspaceRecord?
        try Self.query(
            "SELECT id, name, country_code, currency_code FROM workspaces ORDER BY created_at LIMIT 1;",
            on: handle
        ) { statement in
            workspace = IOSWorkspaceRecord(
                id: Self.columnText(statement, 0) ?? "",
                name: Self.columnText(statement, 1) ?? "",
                countryCode: Self.columnText(statement, 2) ?? "",
                currencyCode: Self.columnText(statement, 3) ?? ""
            )
        }

        var wallets: [IOSWalletRecord] = []
        try Self.query(
            "SELECT id, name, type, opening_balance_minor, currency_code, archived, deleted_at " +
                "FROM wallets ORDER BY sort_order, created_at;",
            on: handle
        ) { statement in
            wallets.append(
                IOSWalletRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    name: Self.columnText(statement, 1) ?? "",
                    typeName: Self.columnText(statement, 2) ?? "OTHER",
                    openingBalanceMinor: sqlite3_column_int64(statement, 3),
                    currencyCode: Self.columnText(statement, 4) ?? "",
                    archived: sqlite3_column_int(statement, 5) != 0,
                    deleted: sqlite3_column_type(statement, 6) != SQLITE_NULL
                )
            )
        }

        var categories: [IOSCategoryRecord] = []
        try Self.query(
            "SELECT id, name, type, icon, color_hex, is_default, archived, sort_order, deleted_at " +
                "FROM categories ORDER BY sort_order, created_at;",
            on: handle
        ) { statement in
            categories.append(
                IOSCategoryRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    name: Self.columnText(statement, 1) ?? "",
                    typeName: Self.columnText(statement, 2) ?? "EXPENSE",
                    icon: Self.columnText(statement, 3) ?? "other",
                    colorHex: Self.columnText(statement, 4) ?? "#6D6D6D",
                    isDefault: sqlite3_column_int(statement, 5) != 0,
                    archived: sqlite3_column_int(statement, 6) != 0,
                    sortOrder: Int(sqlite3_column_int(statement, 7)),
                    deleted: sqlite3_column_type(statement, 8) != SQLITE_NULL
                )
            )
        }

        var incomeSources: [IOSIncomeSourceRecord] = []
        try Self.query(
            "SELECT id, name, kind, archived, deleted_at FROM income_sources " +
                "ORDER BY name COLLATE NOCASE, created_at;",
            on: handle
        ) { statement in
            incomeSources.append(
                IOSIncomeSourceRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    name: Self.columnText(statement, 1) ?? "",
                    kindName: Self.columnText(statement, 2) ?? "OTHER",
                    archived: sqlite3_column_int(statement, 3) != 0,
                    deleted: sqlite3_column_type(statement, 4) != SQLITE_NULL
                )
            )
        }

        var goals: [IOSGoalRecord] = []
        try Self.query(
            "SELECT id, name, target_minor, allocated_minor, target_epoch_day, linked_wallet_id, " +
                "priority, note, icon, archived, deleted_at FROM goals ORDER BY priority, created_at;",
            on: handle
        ) { statement in
            goals.append(
                IOSGoalRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    name: Self.columnText(statement, 1) ?? "",
                    targetMinor: sqlite3_column_int64(statement, 2),
                    allocatedMinor: sqlite3_column_int64(statement, 3),
                    targetEpochDay: sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 4),
                    linkedWalletId: Self.columnText(statement, 5),
                    priority: Int(sqlite3_column_int(statement, 6)),
                    note: Self.columnText(statement, 7) ?? "",
                    icon: Self.columnText(statement, 8) ?? "savings",
                    archived: sqlite3_column_int(statement, 9) != 0,
                    deleted: sqlite3_column_type(statement, 10) != SQLITE_NULL
                )
            )
        }

        var goalContributions: [IOSGoalContributionRecord] = []
        try Self.query(
            "SELECT id, goal_id, amount_minor, local_date_epoch_day, wallet_id, " +
                "transfer_transaction_id, note, created_at FROM goal_contributions " +
                "ORDER BY local_date_epoch_day DESC, created_at DESC;",
            on: handle
        ) { statement in
            goalContributions.append(
                IOSGoalContributionRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    goalId: Self.columnText(statement, 1) ?? "",
                    amountMinor: sqlite3_column_int64(statement, 2),
                    localDateEpochDay: sqlite3_column_int64(statement, 3),
                    walletId: Self.columnText(statement, 4),
                    transferTransactionId: Self.columnText(statement, 5),
                    note: Self.columnText(statement, 6) ?? "",
                    createdAtMillis: sqlite3_column_int64(statement, 7)
                )
            )
        }

        var investments: [IOSInvestmentRecord] = []
        try Self.query(
            "SELECT id, name, provider, asset_type, cost_basis_minor, current_value_minor, currency_code, " +
                "valuation_date_epoch_day, note, archived, deleted_at FROM investment_holdings " +
                "ORDER BY archived, provider COLLATE NOCASE, name COLLATE NOCASE, created_at;",
            on: handle
        ) { statement in
            investments.append(
                IOSInvestmentRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    name: Self.columnText(statement, 1) ?? "",
                    provider: Self.columnText(statement, 2) ?? "",
                    assetTypeName: Self.columnText(statement, 3) ?? "OTHER",
                    costBasisMinor: sqlite3_column_int64(statement, 4),
                    currentValueMinor: sqlite3_column_int64(statement, 5),
                    currencyCode: Self.columnText(statement, 6) ?? "",
                    valuationDateEpochDay: sqlite3_column_int64(statement, 7),
                    note: Self.columnText(statement, 8) ?? "",
                    archived: sqlite3_column_int(statement, 9) != 0,
                    deleted: sqlite3_column_type(statement, 10) != SQLITE_NULL
                )
            )
        }

        var commitments: [IOSCommitmentRecord] = []
        try Self.query(
            "SELECT id, name, target_minor, currency_code, target_workspace_minor, exchange_rate, " +
                "exchange_rate_date, due_epoch_day, category_id, reminder_days_before, archived, deleted_at " +
                "FROM commitments ORDER BY archived, due_epoch_day, name COLLATE NOCASE;",
            on: handle
        ) { statement in
            commitments.append(
                IOSCommitmentRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    name: Self.columnText(statement, 1) ?? "",
                    targetMinor: sqlite3_column_int64(statement, 2),
                    currencyCode: Self.columnText(statement, 3) ?? "",
                    targetWorkspaceMinor: sqlite3_column_int64(statement, 4),
                    exchangeRate: Self.columnText(statement, 5),
                    exchangeRateDate: Self.columnText(statement, 6),
                    dueEpochDay: sqlite3_column_int64(statement, 7),
                    categoryId: Self.columnText(statement, 8),
                    reminderDaysBefore: Int(sqlite3_column_int(statement, 9)),
                    archived: sqlite3_column_int(statement, 10) != 0,
                    deleted: sqlite3_column_type(statement, 11) != SQLITE_NULL
                )
            )
        }

        var commitmentPayments: [IOSCommitmentPaymentRecord] = []
        try Self.query(
            "SELECT id, commitment_id, transaction_id, created_at FROM commitment_payments " +
                "ORDER BY created_at, id;",
            on: handle
        ) { statement in
            commitmentPayments.append(
                IOSCommitmentPaymentRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    commitmentId: Self.columnText(statement, 1) ?? "",
                    transactionId: Self.columnText(statement, 2) ?? "",
                    createdAtMillis: sqlite3_column_int64(statement, 3)
                )
            )
        }

        var transactions: [IOSTransactionRecord] = []
        try Self.query(
            "SELECT id, type, amount_minor, fee_minor, currency_code, wallet_id, to_wallet_id, " +
            "category_id, fee_category_id, income_source_id, linked_transaction_id, note, occurred_at, local_date_epoch_day, deleted_at FROM transactions " +
                "ORDER BY local_date_epoch_day DESC, occurred_at DESC, created_at DESC;",
            on: handle
        ) { statement in
            transactions.append(
                IOSTransactionRecord(
                    id: Self.columnText(statement, 0) ?? "",
                    typeName: Self.columnText(statement, 1) ?? "EXPENSE",
                    amountMinor: sqlite3_column_int64(statement, 2),
                    feeMinor: sqlite3_column_int64(statement, 3),
                    currencyCode: Self.columnText(statement, 4) ?? "",
                    walletId: Self.columnText(statement, 5) ?? "",
                    destinationWalletId: Self.columnText(statement, 6),
                    categoryId: Self.columnText(statement, 7),
                    feeCategoryId: Self.columnText(statement, 8),
                    incomeSourceId: Self.columnText(statement, 9),
                    linkedTransactionId: Self.columnText(statement, 10),
                    note: Self.columnText(statement, 11) ?? "",
                    occurredAtMillis: sqlite3_column_int64(statement, 12),
                    localDateEpochDay: sqlite3_column_int64(statement, 13),
                    deleted: sqlite3_column_type(statement, 14) != SQLITE_NULL
                )
            )
        }
        return IOSLedgerSnapshot(
            workspace: workspace,
            wallets: wallets,
            categories: categories,
            incomeSources: incomeSources,
            goals: goals,
            goalContributions: goalContributions,
            investments: investments,
            commitments: commitments,
            commitmentPayments: commitmentPayments,
            transactions: transactions,
            walletBalancesMinor: [:]
        )
    }

    func insertInitialWorkspace(
        name: String,
        countryCode: String,
        currencyCode: String,
        walletName: String,
        walletTypeName: String,
        openingBalanceMinor: Int64,
        defaultCategories: [IOSCategorySeed]
    ) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var exists = false
            try Self.query("SELECT id FROM workspaces LIMIT 1;", on: handle) { _ in exists = true }
            guard !exists else { throw IOSFinanceRepositoryError.workspaceAlreadyExists }

            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let workspaceId = UUID().uuidString.lowercased()
            let walletId = UUID().uuidString.lowercased()
            try Self.execute(
                "INSERT INTO workspaces (id, name, country_code, currency_code, created_at, updated_at) " +
                    "VALUES (?, ?, ?, ?, ?, ?);",
                values: [.text(workspaceId), .text(name), .text(countryCode), .text(currencyCode), .integer(now), .integer(now)],
                on: handle
            )
            try Self.insertCategories(defaultCategories, at: now, on: handle)
            try Self.execute(
                "INSERT INTO wallets (id, name, type, opening_balance_minor, currency_code, color_hex, icon, " +
                    "sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?);",
                values: [
                    .text(walletId), .text(walletName), .text(walletTypeName), .integer(openingBalanceMinor),
                    .text(currencyCode), .text("#087F72"), .text("wallet"), .integer(now), .integer(now),
                ],
                on: handle
            )
            try validateCurrentBalances()
            try Self.execute("COMMIT;", on: handle)
            return workspaceId
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func insertWallet(name: String, typeName: String, openingBalanceMinor: Int64, currencyCode: String) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var workspaceCurrency: String?
            try Self.query("SELECT currency_code FROM workspaces LIMIT 1;", on: handle) {
                workspaceCurrency = Self.columnText($0, 0)
            }
            guard let workspaceCurrency else { throw IOSFinanceRepositoryError.noWorkspace }
            guard workspaceCurrency == currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }

            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let id = UUID().uuidString.lowercased()
            var sortOrder: Int64 = 0
            try Self.query("SELECT COALESCE(MAX(sort_order), -1) + 1 FROM wallets;", on: handle) {
                sortOrder = sqlite3_column_int64($0, 0)
            }
            try Self.execute(
                "INSERT INTO wallets (id, name, type, opening_balance_minor, currency_code, color_hex, icon, " +
                    "sort_order, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                values: [
                    .text(id), .text(name), .text(typeName), .integer(openingBalanceMinor), .text(currencyCode),
                    .text("#087F72"), .text("wallet"), .integer(sortOrder), .integer(now), .integer(now),
                ],
                on: handle
            )
            try validateCurrentBalances()
            try Self.execute("COMMIT;", on: handle)
            return id
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func insertCategory(name: String, typeName: String, icon: String, colorHex: String) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let id = UUID().uuidString.lowercased()
            var lastSortOrder: Int64 = -1
            try Self.query("SELECT COALESCE(MAX(sort_order), -1) FROM categories;", on: handle) {
                lastSortOrder = sqlite3_column_int64($0, 0)
            }
            let (sortOrder, overflow) = lastSortOrder.addingReportingOverflow(1)
            guard !overflow else { throw IOSFinanceRepositoryError.categoryOrderUnavailable }
            try Self.execute(
                "INSERT INTO categories (id, name, type, icon, color_hex, is_default, archived, sort_order, created_at, updated_at) " +
                    "VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?, ?);",
                values: [
                    .text(id), .text(name), .text(typeName), .text(icon), .text(colorHex),
                    .integer(sortOrder), .integer(now), .integer(now),
                ],
                on: handle
            )
            try Self.execute("COMMIT;", on: handle)
            return id
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func updateCategory(id: String, name: String, icon: String, colorHex: String) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var found = false
            var deleted = false
            try Self.query(
                "SELECT deleted_at FROM categories WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                found = true
                deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
            }
            guard found else { throw IOSFinanceRepositoryError.categoryNotFound }
            guard !deleted else { throw IOSFinanceRepositoryError.categoryUnavailable }
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            try Self.execute(
                "UPDATE categories SET name = ?, icon = ?, color_hex = ?, updated_at = ?, revision = revision + 1 " +
                    "WHERE id = ? AND deleted_at IS NULL;",
                values: [.text(name), .text(icon), .text(colorHex), .integer(now), .text(id)],
                on: handle
            )
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func setCategoryArchived(id: String, archived: Bool) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var typeName: String?
            var wasArchived = false
            var deleted = false
            try Self.query(
                "SELECT type, archived, deleted_at FROM categories WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                typeName = Self.columnText($0, 0)
                wasArchived = sqlite3_column_int($0, 1) != 0
                deleted = sqlite3_column_type($0, 2) != SQLITE_NULL
            }
            guard let typeName else { throw IOSFinanceRepositoryError.categoryNotFound }
            guard !deleted else { throw IOSFinanceRepositoryError.categoryUnavailable }

            if wasArchived != archived {
                if archived {
                    var activeCount: Int64 = 0
                    try Self.query(
                        "SELECT COUNT(*) FROM categories WHERE type = ? AND archived = 0 AND deleted_at IS NULL;",
                        values: [.text(typeName)],
                        on: handle
                    ) {
                        activeCount = sqlite3_column_int64($0, 0)
                    }
                    guard let categoryArchiveValidator else {
                        throw IOSFinanceRepositoryError.sharedCatalogUnavailable
                    }
                    guard categoryArchiveValidator(activeCount) else {
                        throw IOSFinanceRepositoryError.categoryLastActive
                    }
                }
                let now = Int64(Date().timeIntervalSince1970 * 1_000)
                try Self.execute(
                    "UPDATE categories SET archived = ?, updated_at = ?, revision = revision + 1 " +
                        "WHERE id = ? AND deleted_at IS NULL;",
                    values: [.integer(archived ? 1 : 0), .integer(now), .text(id)],
                    on: handle
                )
            }
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func moveCategory(id: String, direction: Int) throws {
        guard direction == -1 || direction == 1 else { return }
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var typeName: String?
            var isArchived = false
            var isDeleted = false
            try Self.query(
                "SELECT type, archived, deleted_at FROM categories WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                typeName = Self.columnText($0, 0)
                isArchived = sqlite3_column_int($0, 1) != 0
                isDeleted = sqlite3_column_type($0, 2) != SQLITE_NULL
            }
            guard let typeName else { throw IOSFinanceRepositoryError.categoryNotFound }
            guard !isArchived && !isDeleted else { throw IOSFinanceRepositoryError.categoryUnavailable }

            var siblings: [(id: String, sortOrder: Int64)] = []
            try Self.query(
                "SELECT id, sort_order FROM categories WHERE type = ? AND archived = 0 AND deleted_at IS NULL " +
                    "ORDER BY sort_order, created_at;",
                values: [.text(typeName)],
                on: handle
            ) {
                siblings.append((Self.columnText($0, 0) ?? "", sqlite3_column_int64($0, 1)))
            }
            guard let sourceIndex = siblings.firstIndex(where: { $0.id == id }) else {
                throw IOSFinanceRepositoryError.categoryUnavailable
            }
            let targetIndex = sourceIndex + direction
            guard siblings.indices.contains(targetIndex) else {
                try Self.execute("COMMIT;", on: handle)
                return
            }

            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            try Self.execute(
                "UPDATE categories SET sort_order = ?, updated_at = ?, revision = revision + 1 WHERE id = ?;",
                values: [.integer(siblings[targetIndex].sortOrder), .integer(now), .text(id)],
                on: handle
            )
            try Self.execute(
                "UPDATE categories SET sort_order = ?, updated_at = ?, revision = revision + 1 WHERE id = ?;",
                values: [.integer(siblings[sourceIndex].sortOrder), .integer(now), .text(siblings[targetIndex].id)],
                on: handle
            )
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func insertIncomeSource(name: String, kindName: String) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        guard incomeSourceKindValidator?(kindName) == true else {
            throw IOSFinanceRepositoryError.invalidIncomeSourceKind
        }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let id = UUID().uuidString.lowercased()
            try Self.execute(
                "INSERT INTO income_sources (id, name, kind, archived, created_at, updated_at) " +
                    "VALUES (?, ?, ?, 0, ?, ?);",
                values: [.text(id), .text(name), .text(kindName), .integer(now), .integer(now)],
                on: handle
            )
            try Self.execute("COMMIT;", on: handle)
            return id
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func updateIncomeSource(id: String, name: String, kindName: String) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        guard incomeSourceKindValidator?(kindName) == true else {
            throw IOSFinanceRepositoryError.invalidIncomeSourceKind
        }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var found = false
            var deleted = false
            try Self.query(
                "SELECT deleted_at FROM income_sources WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                found = true
                deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
            }
            guard found else { throw IOSFinanceRepositoryError.incomeSourceNotFound }
            guard !deleted else { throw IOSFinanceRepositoryError.incomeSourceUnavailable }
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            try Self.execute(
                "UPDATE income_sources SET name = ?, kind = ?, updated_at = ?, revision = revision + 1 " +
                    "WHERE id = ? AND deleted_at IS NULL;",
                values: [.text(name), .text(kindName), .integer(now), .text(id)],
                on: handle
            )
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func saveGoal(
        id goalId: String?,
        name: String,
        targetMinor: Int64,
        targetEpochDay: Int64?,
        linkedWalletId: String?,
        priority: Int,
        note: String,
        icon: String
    ) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        guard !name.isEmpty, name.count <= 80 else {
            throw IOSFinanceRepositoryError.invalidName
        }
        guard targetMinor > 0, targetMinor <= 9_000_000_000_000_000 else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var hasWorkspace = false
            try Self.query("SELECT id FROM workspaces LIMIT 1;", on: handle) { _ in hasWorkspace = true }
            guard hasWorkspace else { throw IOSFinanceRepositoryError.noWorkspace }

            if let linkedWalletId {
                var exists = false
                var available = false
                try Self.query(
                    "SELECT archived, deleted_at FROM wallets WHERE id = ? LIMIT 1;",
                    values: [.text(linkedWalletId)],
                    on: handle
                ) {
                    exists = true
                    available = sqlite3_column_int($0, 0) == 0 && sqlite3_column_type($0, 1) == SQLITE_NULL
                }
                guard exists else { throw IOSFinanceRepositoryError.walletNotFound }
                guard available else { throw IOSFinanceRepositoryError.walletUnavailable }
            }

            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let savedId = goalId ?? UUID().uuidString.lowercased()
            if goalId != nil {
                var exists = false
                var deleted = false
                try Self.query(
                    "SELECT deleted_at FROM goals WHERE id = ? LIMIT 1;",
                    values: [.text(savedId)],
                    on: handle
                ) {
                    exists = true
                    deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
                }
                guard exists else { throw IOSFinanceRepositoryError.goalNotFound }
                guard !deleted else { throw IOSFinanceRepositoryError.goalUnavailable }
                try Self.execute(
                    "UPDATE goals SET name = ?, target_minor = ?, target_epoch_day = ?, linked_wallet_id = ?, " +
                        "priority = ?, note = ?, icon = ?, updated_at = ?, revision = revision + 1 " +
                        "WHERE id = ? AND deleted_at IS NULL;",
                    values: [
                        .text(name), .integer(targetMinor), targetEpochDay.map { .integer($0) } ?? .null,
                        linkedWalletId.map { .text($0) } ?? .null, .integer(Int64(priority)), .text(note),
                        .text(icon), .integer(now), .text(savedId),
                    ],
                    on: handle
                )
                guard sqlite3_changes(handle) == 1 else { throw IOSFinanceRepositoryError.goalUnavailable }
            } else {
                try Self.execute(
                    "INSERT INTO goals (id, name, target_minor, allocated_minor, target_epoch_day, linked_wallet_id, " +
                        "priority, note, icon, archived, created_at, updated_at) " +
                        "VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, 0, ?, ?);",
                    values: [
                        .text(savedId), .text(name), .integer(targetMinor),
                        targetEpochDay.map { .integer($0) } ?? .null,
                        linkedWalletId.map { .text($0) } ?? .null, .integer(Int64(priority)), .text(note),
                        .text(icon), .integer(now), .integer(now),
                    ],
                    on: handle
                )
            }
            try Self.execute("COMMIT;", on: handle)
            return savedId
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func setGoalArchived(id: String, archived: Bool) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var exists = false
            var deleted = false
            try Self.query(
                "SELECT deleted_at FROM goals WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                exists = true
                deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
            }
            guard exists else { throw IOSFinanceRepositoryError.goalNotFound }
            guard !deleted else { throw IOSFinanceRepositoryError.goalUnavailable }
            try Self.execute(
                "UPDATE goals SET archived = ?, updated_at = ?, revision = revision + 1 " +
                    "WHERE id = ? AND deleted_at IS NULL;",
                values: [.integer(archived ? 1 : 0), .integer(Int64(Date().timeIntervalSince1970 * 1_000)), .text(id)],
                on: handle
            )
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func saveInvestmentHolding(
        id investmentId: String?,
        name: String,
        provider: String,
        assetTypeName: String,
        costBasisMinor: Int64,
        currentValueMinor: Int64,
        currencyCode: String,
        valuationDateEpochDay: Int64,
        note: String
    ) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        guard investmentAssetTypeValidator?(assetTypeName) == true else {
            throw IOSFinanceRepositoryError.investmentDraftRejected("asset_type_invalid")
        }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var workspaceCurrency: String?
            try Self.query("SELECT currency_code FROM workspaces ORDER BY created_at LIMIT 1;", on: handle) {
                workspaceCurrency = Self.columnText($0, 0)
            }
            guard let workspaceCurrency else { throw IOSFinanceRepositoryError.noWorkspace }
            guard workspaceCurrency == currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }

            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let savedId = investmentId ?? UUID().uuidString.lowercased()
            if investmentId != nil {
                var exists = false
                var deleted = false
                try Self.query(
                    "SELECT deleted_at FROM investment_holdings WHERE id = ? LIMIT 1;",
                    values: [.text(savedId)],
                    on: handle
                ) {
                    exists = true
                    deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
                }
                guard exists else { throw IOSFinanceRepositoryError.investmentNotFound }
                guard !deleted else { throw IOSFinanceRepositoryError.investmentUnavailable }
                try Self.execute(
                    "UPDATE investment_holdings SET name = ?, provider = ?, asset_type = ?, cost_basis_minor = ?, " +
                        "current_value_minor = ?, currency_code = ?, valuation_date_epoch_day = ?, note = ?, " +
                        "updated_at = ?, revision = revision + 1 WHERE id = ? AND deleted_at IS NULL;",
                    values: [
                        .text(name), .text(provider), .text(assetTypeName), .integer(costBasisMinor),
                        .integer(currentValueMinor), .text(currencyCode), .integer(valuationDateEpochDay),
                        .text(note), .integer(now), .text(savedId),
                    ],
                    on: handle
                )
                guard sqlite3_changes(handle) == 1 else { throw IOSFinanceRepositoryError.investmentUnavailable }
            } else {
                try Self.execute(
                    "INSERT INTO investment_holdings (id, name, provider, asset_type, cost_basis_minor, " +
                        "current_value_minor, currency_code, valuation_date_epoch_day, note, archived, created_at, updated_at) " +
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?);",
                    values: [
                        .text(savedId), .text(name), .text(provider), .text(assetTypeName), .integer(costBasisMinor),
                        .integer(currentValueMinor), .text(currencyCode), .integer(valuationDateEpochDay),
                        .text(note), .integer(now), .integer(now),
                    ],
                    on: handle
                )
            }
            try Self.execute("COMMIT;", on: handle)
            return savedId
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func setInvestmentHoldingArchived(id: String, archived: Bool) throws {
        try updateInvestmentHolding(id: id, sql: "archived = ?", values: [.integer(archived ? 1 : 0)])
    }

    func deleteInvestmentHolding(id: String) throws {
        try updateInvestmentHolding(
            id: id,
            sql: "deleted_at = ?",
            values: [.integer(Int64(Date().timeIntervalSince1970 * 1_000))]
        )
    }

    private func updateInvestmentHolding(id: String, sql: String, values: [SQLValue]) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var exists = false
            var deleted = false
            try Self.query(
                "SELECT deleted_at FROM investment_holdings WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                exists = true
                deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
            }
            guard exists else { throw IOSFinanceRepositoryError.investmentNotFound }
            guard !deleted else { throw IOSFinanceRepositoryError.investmentUnavailable }
            try Self.execute(
                "UPDATE investment_holdings SET \(sql), updated_at = ?, revision = revision + 1 " +
                    "WHERE id = ? AND deleted_at IS NULL;",
                values: values + [.integer(Int64(Date().timeIntervalSince1970 * 1_000)), .text(id)],
                on: handle
            )
            guard sqlite3_changes(handle) == 1 else { throw IOSFinanceRepositoryError.investmentUnavailable }
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func saveCommitment(
        id commitmentId: String?,
        name: String,
        targetMinor: Int64,
        currencyCode: String,
        targetWorkspaceMinor: Int64,
        exchangeRate: String?,
        exchangeRateDate: String?,
        dueEpochDay: Int64,
        categoryId: String?,
        reminderDaysBefore: Int
    ) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var workspaceCurrency: String?
            try Self.query("SELECT currency_code FROM workspaces ORDER BY created_at LIMIT 1;", on: handle) {
                workspaceCurrency = Self.columnText($0, 0)
            }
            guard workspaceCurrency != nil else { throw IOSFinanceRepositoryError.noWorkspace }
            guard targetMinor > 0, targetWorkspaceMinor > 0, reminderDaysBefore >= 0 else {
                throw IOSFinanceRepositoryError.commitmentDraftRejected("target_invalid")
            }
            if let categoryId {
                try Self.validateCategory(categoryId, expectedType: "EXPENSE", allowArchived: true, on: handle)
            }

            let savedId = commitmentId ?? UUID().uuidString.lowercased()
            var existing = false
            var deleted = false
            if commitmentId != nil {
                try Self.query(
                    "SELECT deleted_at FROM commitments WHERE id = ? LIMIT 1;",
                    values: [.text(savedId)],
                    on: handle
                ) {
                    existing = true
                    deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
                }
                guard existing else { throw IOSFinanceRepositoryError.commitmentNotFound }
                guard !deleted else { throw IOSFinanceRepositoryError.commitmentUnavailable }
            }

            let paidWorkspaceMinor: Int64
            if existing {
                paidWorkspaceMinor = try Self.commitmentPaidWorkspaceMinor(commitmentId: savedId, on: handle)
            } else {
                paidWorkspaceMinor = 0
            }
            guard targetWorkspaceMinor >= paidWorkspaceMinor else {
                throw IOSFinanceRepositoryError.commitmentDraftRejected("target_below_payments")
            }

            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            if existing {
                try Self.execute(
                    "UPDATE commitments SET name = ?, target_minor = ?, currency_code = ?, " +
                        "target_workspace_minor = ?, exchange_rate = ?, exchange_rate_date = ?, due_epoch_day = ?, " +
                        "category_id = ?, reminder_days_before = ?, updated_at = ?, revision = revision + 1 " +
                        "WHERE id = ? AND deleted_at IS NULL;",
                    values: [
                        .text(name), .integer(targetMinor), .text(currencyCode), .integer(targetWorkspaceMinor),
                        exchangeRate.map { .text($0) } ?? .null,
                        exchangeRateDate.map { .text($0) } ?? .null,
                        .integer(dueEpochDay), categoryId.map { .text($0) } ?? .null,
                        .integer(Int64(reminderDaysBefore)), .integer(now), .text(savedId),
                    ],
                    on: handle
                )
                guard sqlite3_changes(handle) == 1 else { throw IOSFinanceRepositoryError.commitmentUnavailable }
            } else {
                try Self.execute(
                    "INSERT INTO commitments (id, name, target_minor, currency_code, target_workspace_minor, " +
                        "exchange_rate, exchange_rate_date, due_epoch_day, category_id, reminder_days_before, " +
                        "archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?);",
                    values: [
                        .text(savedId), .text(name), .integer(targetMinor), .text(currencyCode),
                        .integer(targetWorkspaceMinor), exchangeRate.map { .text($0) } ?? .null,
                        exchangeRateDate.map { .text($0) } ?? .null, .integer(dueEpochDay),
                        categoryId.map { .text($0) } ?? .null, .integer(Int64(reminderDaysBefore)),
                        .integer(now), .integer(now),
                    ],
                    on: handle
                )
            }
            try Self.execute("COMMIT;", on: handle)
            return savedId
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func setCommitmentArchived(id: String, archived: Bool) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var exists = false
            var deleted = false
            try Self.query(
                "SELECT deleted_at FROM commitments WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                exists = true
                deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
            }
            guard exists else { throw IOSFinanceRepositoryError.commitmentNotFound }
            guard !deleted else { throw IOSFinanceRepositoryError.commitmentUnavailable }
            try Self.execute(
                "UPDATE commitments SET archived = ?, updated_at = ?, revision = revision + 1 " +
                    "WHERE id = ? AND deleted_at IS NULL;",
                values: [
                    .integer(archived ? 1 : 0),
                    .integer(Int64(Date().timeIntervalSince1970 * 1_000)),
                    .text(id),
                ],
                on: handle
            )
            guard sqlite3_changes(handle) == 1 else { throw IOSFinanceRepositoryError.commitmentUnavailable }
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func deleteCommitment(id: String) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var exists = false
            var deleted = false
            try Self.query(
                "SELECT deleted_at FROM commitments WHERE id = ? LIMIT 1;",
                values: [.text(id)],
                on: handle
            ) {
                exists = true
                deleted = sqlite3_column_type($0, 0) != SQLITE_NULL
            }
            if exists && !deleted {
                try Self.execute("DELETE FROM commitment_payments WHERE commitment_id = ?;", values: [.text(id)], on: handle)
                let now = Int64(Date().timeIntervalSince1970 * 1_000)
                try Self.execute(
                    "UPDATE commitments SET deleted_at = ?, updated_at = ?, revision = revision + 1 " +
                        "WHERE id = ? AND deleted_at IS NULL;",
                    values: [.integer(now), .integer(now), .text(id)],
                    on: handle
                )
            }
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func linkExpenseToCommitment(commitmentId: String, transactionId: String) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var targetWorkspaceMinor: Int64?
            var commitmentAvailable = false
            try Self.query(
                "SELECT target_workspace_minor, archived, deleted_at FROM commitments WHERE id = ? LIMIT 1;",
                values: [.text(commitmentId)],
                on: handle
            ) {
                targetWorkspaceMinor = sqlite3_column_int64($0, 0)
                commitmentAvailable = sqlite3_column_int($0, 1) == 0 && sqlite3_column_type($0, 2) == SQLITE_NULL
            }
            guard let targetWorkspaceMinor else { throw IOSFinanceRepositoryError.commitmentNotFound }
            guard commitmentAvailable else { throw IOSFinanceRepositoryError.commitmentUnavailable }

            var transactionType: String?
            var transactionAmount: Int64 = 0
            var transactionCurrency: String?
            var transactionActive = false
            try Self.query(
                "SELECT type, amount_minor, currency_code, deleted_at FROM transactions WHERE id = ? LIMIT 1;",
                values: [.text(transactionId)],
                on: handle
            ) {
                transactionType = Self.columnText($0, 0)
                transactionAmount = sqlite3_column_int64($0, 1)
                transactionCurrency = Self.columnText($0, 2)
                transactionActive = sqlite3_column_type($0, 3) == SQLITE_NULL
            }
            guard let transactionType else { throw IOSFinanceRepositoryError.transactionNotFound }
            guard transactionActive else { throw IOSFinanceRepositoryError.transactionUnavailable }
            guard transactionType == "EXPENSE" else { throw IOSFinanceRepositoryError.commitmentPaymentUnavailable }
            var workspaceCurrency: String?
            try Self.query("SELECT currency_code FROM workspaces ORDER BY created_at LIMIT 1;", on: handle) {
                workspaceCurrency = Self.columnText($0, 0)
            }
            guard let workspaceCurrency else { throw IOSFinanceRepositoryError.noWorkspace }
            guard transactionCurrency == workspaceCurrency else { throw IOSFinanceRepositoryError.invalidCurrency }

            var alreadyLinked = false
            try Self.query(
                "SELECT id FROM commitment_payments WHERE transaction_id = ? LIMIT 1;",
                values: [.text(transactionId)],
                on: handle
            ) { _ in alreadyLinked = true }
            guard !alreadyLinked else { throw IOSFinanceRepositoryError.commitmentPaymentUnavailable }

            let refundMinor = try Self.refundedAmountMinor(for: transactionId, on: handle)
            let netPaymentMinor = max(0, transactionAmount - refundMinor)
            guard netPaymentMinor > 0 else { throw IOSFinanceRepositoryError.commitmentPaymentUnavailable }
            let alreadyPaidMinor = try Self.commitmentPaidWorkspaceMinor(commitmentId: commitmentId, on: handle)
            guard alreadyPaidMinor <= targetWorkspaceMinor,
                  netPaymentMinor <= targetWorkspaceMinor - alreadyPaidMinor else {
                throw IOSFinanceRepositoryError.commitmentPaymentUnavailable
            }

            let paymentId = UUID().uuidString.lowercased()
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            try Self.execute(
                "INSERT INTO commitment_payments (id, commitment_id, transaction_id, created_at, updated_at) " +
                    "VALUES (?, ?, ?, ?, ?);",
                values: [.text(paymentId), .text(commitmentId), .text(transactionId), .integer(now), .integer(now)],
                on: handle
            )
            try Self.execute("COMMIT;", on: handle)
            return paymentId
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func unlinkCommitmentPayment(id: String) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("DELETE FROM commitment_payments WHERE id = ?;", values: [.text(id)], on: handle)
    }

    private static func commitmentPaidWorkspaceMinor(
        commitmentId: String,
        excludingTransactionId: String? = nil,
        on database: OpaquePointer
    ) throws -> Int64 {
        var total: Int64 = 0
        try query(
            "SELECT t.id, t.type, t.amount_minor, t.deleted_at FROM commitment_payments p " +
                "JOIN transactions t ON t.id = p.transaction_id WHERE p.commitment_id = ?;",
            values: [.text(commitmentId)],
            on: database
        ) { statement in
            let transactionId = columnText(statement, 0) ?? ""
            guard transactionId != excludingTransactionId,
                  columnText(statement, 1) == "EXPENSE",
                  sqlite3_column_type(statement, 3) == SQLITE_NULL else { return }
            let amountMinor = sqlite3_column_int64(statement, 2)
            let refundedMinor = try refundedAmountMinor(for: transactionId, on: database)
            let netMinor = max(0, amountMinor - refundedMinor)
            let (sum, overflow) = total.addingReportingOverflow(netMinor)
            guard !overflow else { throw IOSFinanceRepositoryError.commitmentDraftRejected("payment_total_overflow") }
            total = sum
        }
        return total
    }

    private static func refundedAmountMinor(for transactionId: String, on database: OpaquePointer) throws -> Int64 {
        var total: Int64 = 0
        try query(
            "SELECT amount_minor FROM transactions WHERE type = 'REFUND' AND linked_transaction_id = ? " +
                "AND deleted_at IS NULL;",
            values: [.text(transactionId)],
            on: database
        ) { statement in
            let (sum, overflow) = total.addingReportingOverflow(sqlite3_column_int64(statement, 0))
            guard !overflow else { throw IOSFinanceRepositoryError.commitmentPaymentUnavailable }
            total = sum
        }
        return total
    }

    func insertGoalContribution(
        goalId: String,
        amountMinor: Int64,
        allocatedMinorAfterContribution: Int64,
        fromWalletId: String?,
        localDateEpochDay: Int64,
        note: String
    ) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        guard amountMinor > 0, amountMinor <= 9_000_000_000_000_000 else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var goalName: String?
            var currentAllocation: Int64 = 0
            var linkedWalletId: String?
            var archived = false
            var deleted = false
            try Self.query(
                "SELECT name, allocated_minor, linked_wallet_id, archived, deleted_at FROM goals WHERE id = ? LIMIT 1;",
                values: [.text(goalId)],
                on: handle
            ) {
                goalName = Self.columnText($0, 0)
                currentAllocation = sqlite3_column_int64($0, 1)
                linkedWalletId = Self.columnText($0, 2)
                archived = sqlite3_column_int($0, 3) != 0
                deleted = sqlite3_column_type($0, 4) != SQLITE_NULL
            }
            guard let goalName else { throw IOSFinanceRepositoryError.goalNotFound }
            guard !archived, !deleted else { throw IOSFinanceRepositoryError.goalUnavailable }
            let (expectedAllocation, overflow) = currentAllocation.addingReportingOverflow(amountMinor)
            guard currentAllocation >= 0, currentAllocation <= 9_000_000_000_000_000,
                  !overflow, expectedAllocation == allocatedMinorAfterContribution,
                  expectedAllocation <= 9_000_000_000_000_000 else {
                throw IOSFinanceRepositoryError.amountOutsideSupportedRange
            }

            var currencyCode: String?
            try Self.query("SELECT currency_code FROM workspaces ORDER BY created_at LIMIT 1;", on: handle) {
                currencyCode = Self.columnText($0, 0)
            }
            guard let currencyCode else { throw IOSFinanceRepositoryError.noWorkspace }

            if let fromWalletId {
                var walletCurrency: String?
                var walletAvailable = false
                try Self.query(
                    "SELECT currency_code, archived, deleted_at FROM wallets WHERE id = ? LIMIT 1;",
                    values: [.text(fromWalletId)],
                    on: handle
                ) {
                    walletCurrency = Self.columnText($0, 0)
                    walletAvailable = sqlite3_column_int($0, 1) == 0 && sqlite3_column_type($0, 2) == SQLITE_NULL
                }
                guard let walletCurrency else { throw IOSFinanceRepositoryError.walletNotFound }
                guard walletAvailable else { throw IOSFinanceRepositoryError.walletUnavailable }
                guard walletCurrency == currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }
            }

            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            var transferId: String?
            if let fromWalletId, let linkedWalletId, fromWalletId != linkedWalletId {
                var destinationCurrency: String?
                var destinationAvailable = false
                try Self.query(
                    "SELECT currency_code, archived, deleted_at FROM wallets WHERE id = ? LIMIT 1;",
                    values: [.text(linkedWalletId)],
                    on: handle
                ) {
                    destinationCurrency = Self.columnText($0, 0)
                    destinationAvailable = sqlite3_column_int($0, 1) == 0 && sqlite3_column_type($0, 2) == SQLITE_NULL
                }
                guard let destinationCurrency else { throw IOSFinanceRepositoryError.walletNotFound }
                guard destinationAvailable else { throw IOSFinanceRepositoryError.walletUnavailable }
                guard destinationCurrency == currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }

                let createdTransferId = UUID().uuidString.lowercased()
                try Self.execute(
                    "INSERT INTO transactions (id, type, amount_minor, fee_minor, currency_code, wallet_id, to_wallet_id, " +
                        "category_id, fee_category_id, income_source_id, linked_transaction_id, note, " +
                        "local_date_epoch_day, occurred_at, created_at, updated_at) " +
                        "VALUES (?, 'TRANSFER', ?, 0, ?, ?, ?, NULL, NULL, NULL, NULL, ?, ?, ?, ?, ?);",
                    values: [
                        .text(createdTransferId), .integer(amountMinor), .text(currencyCode), .text(fromWalletId),
                        .text(linkedWalletId), .text("Savings: \(goalName)"), .integer(localDateEpochDay),
                        .integer(now), .integer(now), .integer(now),
                    ],
                    on: handle
                )
                try validateCurrentBalances()
                transferId = createdTransferId
            }

            try Self.execute(
                "INSERT INTO goal_contributions (id, goal_id, amount_minor, local_date_epoch_day, wallet_id, " +
                    "transfer_transaction_id, note, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
                values: [
                    .text(UUID().uuidString.lowercased()), .text(goalId), .integer(amountMinor),
                    .integer(localDateEpochDay), fromWalletId.map { .text($0) } ?? .null,
                    transferId.map { .text($0) } ?? .null, .text(note), .integer(now),
                ],
                on: handle
            )
            try Self.execute(
                "UPDATE goals SET allocated_minor = ?, updated_at = ?, revision = revision + 1 " +
                    "WHERE id = ? AND allocated_minor = ? AND archived = 0 AND deleted_at IS NULL;",
                values: [
                    .integer(allocatedMinorAfterContribution), .integer(now), .text(goalId), .integer(currentAllocation),
                ],
                on: handle
            )
            guard sqlite3_changes(handle) == 1 else { throw IOSFinanceRepositoryError.goalUnavailable }
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func insertTransaction(
        typeName: String,
        amountMinor: Int64,
        feeMinor: Int64,
        currencyCode: String,
        walletId: String,
        toWalletId: String? = nil,
        categoryId: String?,
        feeCategoryId: String?,
        incomeSourceId: String? = nil,
        linkedTransactionId: String? = nil,
        transactionId: String? = nil,
        note: String,
        occurredAtMillis: Int64
    ) throws -> String {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            guard (typeName == "TRANSFER") == (toWalletId != nil) else {
                throw IOSFinanceRepositoryError.invalidTransferDestination
            }
            guard typeName == "REFUND" || linkedTransactionId == nil else {
                throw IOSFinanceRepositoryError.invalidTransactionType
            }
            guard typeName != "ADJUSTMENT" || feeMinor == 0 else {
                throw IOSFinanceRepositoryError.invalidTransactionType
            }
            guard typeName == "INCOME" || incomeSourceId == nil else {
                throw IOSFinanceRepositoryError.invalidTransactionType
            }
            var existingType: String?
            var existingIsActive = false
            var existingIncomeSourceId: String?
            var existingLinkedTransactionId: String?
            var existingLocalDateEpochDay: Int64?
            var existingOccurredAtMillis: Int64?
            if let transactionId {
                try Self.query(
                    "SELECT type, deleted_at, income_source_id, linked_transaction_id, local_date_epoch_day, occurred_at " +
                        "FROM transactions WHERE id = ? LIMIT 1;",
                    values: [.text(transactionId)],
                    on: handle
                ) {
                    existingType = Self.columnText($0, 0)
                    existingIsActive = sqlite3_column_type($0, 1) == SQLITE_NULL
                    existingIncomeSourceId = Self.columnText($0, 2)
                    existingLinkedTransactionId = Self.columnText($0, 3)
                    existingLocalDateEpochDay = sqlite3_column_int64($0, 4)
                    existingOccurredAtMillis = sqlite3_column_int64($0, 5)
                }
                guard let existingType else { throw IOSFinanceRepositoryError.transactionNotFound }
                guard existingIsActive else { throw IOSFinanceRepositoryError.transactionUnavailable }
                if existingType == "EXPENSE" && typeName != "EXPENSE" {
                    var hasLinkedRefunds = false
                    try Self.query(
                        "SELECT id FROM transactions WHERE type = 'REFUND' AND linked_transaction_id = ? " +
                            "LIMIT 1;",
                        values: [.text(transactionId)],
                        on: handle
                    ) { _ in hasLinkedRefunds = true }
                    guard !hasLinkedRefunds else { throw IOSFinanceRepositoryError.transactionHasRefunds }
                }

                var commitmentId: String?
                try Self.query(
                    "SELECT commitment_id FROM commitment_payments WHERE transaction_id = ? LIMIT 1;",
                    values: [.text(transactionId)],
                    on: handle
                ) { commitmentId = Self.columnText($0, 0) }
                if let commitmentId {
                    guard typeName == "EXPENSE" else {
                        throw IOSFinanceRepositoryError.commitmentPaymentUnavailable
                    }
                    var targetWorkspaceMinor: Int64?
                    try Self.query(
                        "SELECT target_workspace_minor FROM commitments WHERE id = ? AND deleted_at IS NULL LIMIT 1;",
                        values: [.text(commitmentId)],
                        on: handle
                    ) { targetWorkspaceMinor = sqlite3_column_int64($0, 0) }
                    if let targetWorkspaceMinor {
                        let paidWithoutThisExpense = try Self.commitmentPaidWorkspaceMinor(
                            commitmentId: commitmentId,
                            excludingTransactionId: transactionId,
                            on: handle
                        )
                        guard paidWithoutThisExpense <= targetWorkspaceMinor,
                              amountMinor <= targetWorkspaceMinor - paidWithoutThisExpense else {
                            throw IOSFinanceRepositoryError.commitmentPaymentUnavailable
                        }
                    }
                }
            }
            var currentWorkspaceCurrency: String?
            try Self.query("SELECT currency_code FROM workspaces ORDER BY created_at LIMIT 1;", on: handle) {
                currentWorkspaceCurrency = Self.columnText($0, 0)
            }
            guard let currentWorkspaceCurrency else { throw IOSFinanceRepositoryError.noWorkspace }
            guard currentWorkspaceCurrency == currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }
            var walletCurrency: String?
            var walletAvailable = false
            try Self.query("SELECT currency_code, archived, deleted_at FROM wallets WHERE id = ? LIMIT 1;", values: [.text(walletId)], on: handle) {
                walletCurrency = Self.columnText($0, 0)
                walletAvailable = sqlite3_column_int($0, 1) == 0 && sqlite3_column_type($0, 2) == SQLITE_NULL
            }
            guard let walletCurrency else { throw IOSFinanceRepositoryError.walletNotFound }
            guard walletAvailable else { throw IOSFinanceRepositoryError.walletUnavailable }
            guard walletCurrency == currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }

            if let incomeSourceId {
                var sourceExists = false
                var sourceDeleted = false
                try Self.query(
                    "SELECT deleted_at FROM income_sources WHERE id = ? LIMIT 1;",
                    values: [.text(incomeSourceId)],
                    on: handle
                ) {
                    sourceExists = true
                    sourceDeleted = sqlite3_column_type($0, 0) != SQLITE_NULL
                }
                let preservesExistingSourceReference = existingType == "INCOME" &&
                    existingIncomeSourceId == incomeSourceId
                guard sourceExists || preservesExistingSourceReference else {
                    throw IOSFinanceRepositoryError.incomeSourceNotFound
                }
                guard !sourceDeleted || preservesExistingSourceReference else {
                    throw IOSFinanceRepositoryError.incomeSourceUnavailable
                }
            }

            if let toWalletId {
                guard toWalletId != walletId else { throw IOSFinanceRepositoryError.invalidTransferDestination }
                var destinationCurrency: String?
                var destinationAvailable = false
                try Self.query(
                    "SELECT currency_code, archived, deleted_at FROM wallets WHERE id = ? LIMIT 1;",
                    values: [.text(toWalletId)],
                    on: handle
                ) {
                    destinationCurrency = Self.columnText($0, 0)
                    destinationAvailable = sqlite3_column_int($0, 1) == 0 && sqlite3_column_type($0, 2) == SQLITE_NULL
                }
                guard let destinationCurrency else { throw IOSFinanceRepositoryError.walletNotFound }
                guard destinationAvailable else { throw IOSFinanceRepositoryError.walletUnavailable }
                guard destinationCurrency == currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }
            }

            if let linkedTransactionId {
                guard linkedTransactionId != transactionId else {
                    throw IOSFinanceRepositoryError.refundTargetUnavailable
                }
                var linkedType: String?
                var linkedIsActive = false
                try Self.query(
                    "SELECT type, deleted_at FROM transactions WHERE id = ? LIMIT 1;",
                    values: [.text(linkedTransactionId)],
                    on: handle
                ) {
                    linkedType = Self.columnText($0, 0)
                    linkedIsActive = sqlite3_column_type($0, 1) == SQLITE_NULL
                }
                let preservesExistingRefundLink = typeName == "REFUND" &&
                    existingType == "REFUND" && existingLinkedTransactionId == linkedTransactionId &&
                    linkedType == "EXPENSE"
                guard (linkedType == "EXPENSE" && linkedIsActive) || preservesExistingRefundLink else {
                    throw IOSFinanceRepositoryError.refundTargetUnavailable
                }
            }

            if feeMinor > 0 {
                guard let feeCategoryId else { throw IOSFinanceRepositoryError.categoryNotFound }
                try Self.validateCategory(feeCategoryId, expectedType: "EXPENSE", allowArchived: true, on: handle)
            }
            if let categoryId {
                switch typeName {
                case "EXPENSE", "REFUND":
                    try Self.validateCategory(categoryId, expectedType: "EXPENSE", allowArchived: true, on: handle)
                case "INCOME":
                    try Self.validateCategory(categoryId, expectedType: "INCOME", allowArchived: true, on: handle)
                default:
                    throw IOSFinanceRepositoryError.invalidTransactionType
                }
            } else if typeName == "EXPENSE" || typeName == "INCOME" || typeName == "REFUND" {
                throw IOSFinanceRepositoryError.categoryNotFound
            }

            let date = Date(timeIntervalSince1970: TimeInterval(occurredAtMillis) / 1_000)
            let epoch = Date(timeIntervalSince1970: 0)
            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = TimeZone.current
            let calculatedEpochDay = Int64(
                localCalendar.dateComponents(
                    [.day],
                    from: localCalendar.startOfDay(for: epoch),
                    to: localCalendar.startOfDay(for: date)
                ).day ?? 0
            )
            let epochDay = existingOccurredAtMillis == occurredAtMillis
                ? (existingLocalDateEpochDay ?? calculatedEpochDay)
                : calculatedEpochDay
            let id = transactionId ?? UUID().uuidString.lowercased()
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            if transactionId != nil {
                try Self.execute(
                    "UPDATE transactions SET type = ?, amount_minor = ?, fee_minor = ?, currency_code = ?, " +
                        "wallet_id = ?, to_wallet_id = ?, category_id = ?, fee_category_id = ?, " +
                        "income_source_id = ?, linked_transaction_id = ?, note = ?, local_date_epoch_day = ?, occurred_at = ?, " +
                        "updated_at = ?, revision = revision + 1 WHERE id = ? AND deleted_at IS NULL;",
                    values: [
                        .text(typeName), .integer(amountMinor), .integer(feeMinor), .text(currencyCode),
                        .text(walletId), toWalletId.map { .text($0) } ?? .null,
                        categoryId.map { .text($0) } ?? .null, feeCategoryId.map { .text($0) } ?? .null,
                        incomeSourceId.map { .text($0) } ?? .null,
                        linkedTransactionId.map { .text($0) } ?? .null, .text(note),
                        .integer(epochDay), .integer(occurredAtMillis), .integer(now), .text(id),
                    ],
                    on: handle
                )
                guard sqlite3_changes(handle) == 1 else { throw IOSFinanceRepositoryError.transactionUnavailable }
            } else {
                try Self.execute(
                    "INSERT INTO transactions (id, type, amount_minor, fee_minor, currency_code, wallet_id, to_wallet_id, " +
                    "category_id, fee_category_id, income_source_id, linked_transaction_id, note, " +
                        "local_date_epoch_day, occurred_at, created_at, updated_at) " +
                        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
                    values: [
                        .text(id), .text(typeName), .integer(amountMinor), .integer(feeMinor), .text(currencyCode),
                        .text(walletId), toWalletId.map { .text($0) } ?? .null,
                        categoryId.map { .text($0) } ?? .null, feeCategoryId.map { .text($0) } ?? .null,
                        incomeSourceId.map { .text($0) } ?? .null,
                        linkedTransactionId.map { .text($0) } ?? .null, .text(note),
                        .integer(epochDay), .integer(occurredAtMillis), .integer(now), .integer(now),
                    ],
                    on: handle
                )
            }
            try validateCurrentBalances()
            try Self.execute("COMMIT;", on: handle)
            return id
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    func setTransactionDeleted(id: String, deleted: Bool) throws {
        guard let handle else { throw EncryptedDatabaseError.databaseClosed }
        try Self.execute("BEGIN IMMEDIATE;", on: handle)
        do {
            var balancesWereAvailable = true
            if deleted {
                do {
                    try validateCurrentBalances()
                } catch {
                    guard let repositoryError = error as? IOSFinanceRepositoryError,
                          repositoryError == .balanceUnavailable else {
                        throw error
                    }
                    balancesWereAvailable = false
                }
            }
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            if deleted {
                try Self.execute(
                    "UPDATE transactions SET deleted_at = ?, updated_at = ?, revision = revision + 1 " +
                        "WHERE id = ? AND deleted_at IS NULL;",
                    values: [.integer(now), .integer(now), .text(id)],
                    on: handle
                )
            } else {
                try Self.execute(
                    "UPDATE transactions SET deleted_at = NULL, updated_at = ?, revision = revision + 1 " +
                        "WHERE id = ? AND deleted_at IS NOT NULL;",
                    values: [.integer(now), .text(id)],
                    on: handle
                )
            }
            let didChange = sqlite3_changes(handle) > 0
            if deleted && didChange {
                try Self.execute(
                    "DELETE FROM commitment_payments WHERE transaction_id = ?;",
                    values: [.text(id)],
                    on: handle
                )
            }
            if didChange && (!deleted || balancesWereAvailable) {
                try validateCurrentBalances()
            }
            try Self.execute("COMMIT;", on: handle)
        } catch {
            try? Self.execute("ROLLBACK;", on: handle)
            throw error
        }
    }

    private func validateCurrentBalances() throws {
        guard let balanceValidator else { return }
        let snapshot = try readFinanceSnapshot()
        try balanceValidator(snapshot.wallets, snapshot.transactions)
    }

    private static func validateCategory(
        _ id: String,
        expectedType: String,
        allowArchived: Bool = false,
        on database: OpaquePointer
    ) throws {
        var actualType: String?
        var available = false
        try query(
            "SELECT type, archived, deleted_at FROM categories WHERE id = ? LIMIT 1;",
            values: [.text(id)],
            on: database
        ) {
            actualType = columnText($0, 0)
            available = (allowArchived || sqlite3_column_int($0, 1) == 0) &&
                sqlite3_column_type($0, 2) == SQLITE_NULL
        }
        guard let actualType else { throw IOSFinanceRepositoryError.categoryNotFound }
        guard available else { throw IOSFinanceRepositoryError.categoryUnavailable }
        guard actualType == expectedType else { throw IOSFinanceRepositoryError.categoryTypeMismatch }
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func execute(_ sql: String, values: [SQLValue], on database: OpaquePointer) throws {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw EncryptedDatabaseError.statementFailed(prepareStatus)
        }
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)
        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_DONE else {
            throw EncryptedDatabaseError.statementFailed(stepStatus)
        }
    }

    private static func query(
        _ sql: String,
        values: [SQLValue] = [],
        on database: OpaquePointer,
        row: (OpaquePointer) throws -> Void
    ) throws {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw EncryptedDatabaseError.statementFailed(prepareStatus)
        }
        defer { sqlite3_finalize(statement) }

        try bind(values, to: statement)
        while true {
            let stepStatus = sqlite3_step(statement)
            if stepStatus == SQLITE_DONE { return }
            guard stepStatus == SQLITE_ROW else {
                throw EncryptedDatabaseError.statementFailed(stepStatus)
            }
            try row(statement)
        }
    }

    private static func bind(_ values: [SQLValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case let .text(string):
                status = string.withCString {
                    sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
                }
            case let .integer(integer):
                status = sqlite3_bind_int64(statement, index, integer)
            case .null:
                status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else {
                throw EncryptedDatabaseError.statementFailed(status)
            }
        }
    }

    private static func columnText(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: value)
    }

    private static func insertCategories(_ categories: [IOSCategorySeed], at timestamp: Int64, on database: OpaquePointer) throws {
        for (index, category) in categories.enumerated() {
            try execute(
                "INSERT INTO categories (id, name, type, icon, color_hex, is_default, sort_order, created_at, updated_at) " +
                    "VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?);",
                values: [
                    .text(category.id), .text(category.name), .text(category.typeName), .text(category.icon),
                    .text(category.colorHex), .integer(Int64(index)), .integer(timestamp), .integer(timestamp),
                ],
                on: database
            )
        }
    }

    private static func migrate(_ database: OpaquePointer, defaultCategories: [IOSCategorySeed]) throws {
        let currentVersion = try userVersion(database)
        guard currentVersion <= 5 else {
            throw EncryptedDatabaseError.unsupportedSchema(currentVersion)
        }
        if currentVersion < 2 {
            try execute("BEGIN IMMEDIATE;", on: database)
            do {
                if currentVersion == 0 {
                try execute(
                    """
                    CREATE TABLE workspaces (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL,
                        country_code TEXT NOT NULL,
                        currency_code TEXT NOT NULL,
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL,
                        revision INTEGER NOT NULL DEFAULT 1
                    );
                    CREATE TABLE wallets (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL,
                        type TEXT NOT NULL,
                        opening_balance_minor INTEGER NOT NULL,
                        currency_code TEXT NOT NULL,
                        color_hex TEXT NOT NULL,
                        icon TEXT NOT NULL,
                        sort_order INTEGER NOT NULL,
                        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
                        deleted_at INTEGER,
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL,
                        revision INTEGER NOT NULL DEFAULT 1
                    );
                    CREATE TABLE categories (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL,
                        type TEXT NOT NULL CHECK (type IN ('EXPENSE', 'INCOME')),
                        icon TEXT NOT NULL,
                        color_hex TEXT NOT NULL,
                        is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
                        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
                        sort_order INTEGER NOT NULL,
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL,
                        revision INTEGER NOT NULL DEFAULT 1,
                        deleted_at INTEGER
                    );
                    CREATE INDEX index_categories_deleted ON categories(deleted_at);
                    CREATE INDEX index_categories_type ON categories(type);
                    CREATE INDEX index_categories_archived ON categories(archived);
                    CREATE TABLE transactions (
                        id TEXT PRIMARY KEY NOT NULL,
                        type TEXT NOT NULL CHECK (type IN ('EXPENSE', 'INCOME', 'TRANSFER', 'REFUND', 'ADJUSTMENT')),
                        amount_minor INTEGER NOT NULL,
                        fee_minor INTEGER NOT NULL DEFAULT 0 CHECK (fee_minor >= 0),
                        currency_code TEXT NOT NULL,
                        wallet_id TEXT NOT NULL REFERENCES wallets(id),
                        to_wallet_id TEXT REFERENCES wallets(id),
                        category_id TEXT,
                        fee_category_id TEXT,
                        income_source_id TEXT,
                        linked_transaction_id TEXT REFERENCES transactions(id),
                        note TEXT NOT NULL DEFAULT '',
                        payee TEXT NOT NULL DEFAULT '',
                        local_date_epoch_day INTEGER NOT NULL,
                        occurred_at INTEGER NOT NULL,
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL,
                        revision INTEGER NOT NULL DEFAULT 1,
                        deleted_at INTEGER,
                        source_amount_minor INTEGER,
                        source_fee_minor INTEGER,
                        source_currency_code TEXT,
                        exchange_rate TEXT,
                        exchange_rate_date TEXT,
                        source_provider TEXT,
                        source_reference TEXT,
                        CHECK (type IN ('ADJUSTMENT') OR amount_minor > 0)
                    );
                    CREATE INDEX index_wallets_active ON wallets(deleted_at, archived, sort_order);
                    CREATE INDEX index_transactions_date ON transactions(deleted_at, local_date_epoch_day, occurred_at);
                    CREATE INDEX index_transactions_wallet ON transactions(deleted_at, wallet_id, local_date_epoch_day);
                    CREATE INDEX index_transactions_reference ON transactions(source_provider, source_reference);
                    PRAGMA user_version = 2;
                    """,
                    on: database
                )
            } else {
                // Version 1 stored the ledger but had no category table. This forward-only
                // migration retains every transaction and category_id value, including nulls.
                // Some early v1 files may also predate the nullable income_source_id column.
                var hasIncomeSourceIdColumn = false
                try query("PRAGMA table_info(transactions);", on: database) { statement in
                    if columnText(statement, 1) == "income_source_id" {
                        hasIncomeSourceIdColumn = true
                    }
                }
                if !hasIncomeSourceIdColumn {
                    try execute("ALTER TABLE transactions ADD COLUMN income_source_id TEXT;", on: database)
                }
                try execute(
                    """
                    CREATE TABLE categories (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL,
                        type TEXT NOT NULL CHECK (type IN ('EXPENSE', 'INCOME')),
                        icon TEXT NOT NULL,
                        color_hex TEXT NOT NULL,
                        is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
                        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
                        sort_order INTEGER NOT NULL,
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL,
                        revision INTEGER NOT NULL DEFAULT 1,
                        deleted_at INTEGER
                    );
                    CREATE INDEX index_categories_deleted ON categories(deleted_at);
                    CREATE INDEX index_categories_type ON categories(type);
                    CREATE INDEX index_categories_archived ON categories(archived);
                    """,
                    on: database
                )
                var hasWorkspace = false
                try query("SELECT id FROM workspaces LIMIT 1;", on: database) { _ in hasWorkspace = true }
                if hasWorkspace {
                    try insertCategories(defaultCategories, at: Int64(Date().timeIntervalSince1970 * 1_000), on: database)
                }
                try execute("PRAGMA user_version = 2;", on: database)
            }
            try execute("COMMIT;", on: database)
        } catch let error as EncryptedDatabaseError {
            try? execute("ROLLBACK;", on: database)
            if case let .statementFailed(status) = error {
                throw EncryptedDatabaseError.migrationFailed(status)
            }
            throw error
        } catch {
            try? execute("ROLLBACK;", on: database)
            throw EncryptedDatabaseError.migrationFailed(sqlite3_errcode(database))
        }
        }

        let migratedVersion = try userVersion(database)
        if migratedVersion < 3 {
            try execute("BEGIN IMMEDIATE;", on: database)
            do {
                try execute(
                    """
                    CREATE TABLE income_sources (
                        id TEXT PRIMARY KEY NOT NULL,
                        name TEXT NOT NULL,
                        kind TEXT NOT NULL,
                        archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
                        created_at INTEGER NOT NULL,
                        updated_at INTEGER NOT NULL,
                        revision INTEGER NOT NULL DEFAULT 1,
                        deleted_at INTEGER
                    );
                    CREATE INDEX index_income_sources_deleted ON income_sources(deleted_at);
                    PRAGMA user_version = 3;
                    """,
                    on: database
                )
                try execute("COMMIT;", on: database)
            } catch let error as EncryptedDatabaseError {
                try? execute("ROLLBACK;", on: database)
                if case let .statementFailed(status) = error {
                    throw EncryptedDatabaseError.migrationFailed(status)
                }
                throw error
            } catch {
                try? execute("ROLLBACK;", on: database)
                throw EncryptedDatabaseError.migrationFailed(sqlite3_errcode(database))
            }
        }

        if try userVersion(database) < 4 {
            try execute("BEGIN IMMEDIATE;", on: database)
            do {
                try execute(
                    """
                CREATE TABLE goals (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    target_minor INTEGER NOT NULL,
                    allocated_minor INTEGER NOT NULL DEFAULT 0,
                    target_epoch_day INTEGER,
                    linked_wallet_id TEXT,
                    priority INTEGER NOT NULL DEFAULT 2,
                    note TEXT NOT NULL DEFAULT '',
                    icon TEXT NOT NULL DEFAULT 'savings',
                    archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    deleted_at INTEGER
                );
                CREATE INDEX index_goals_deleted ON goals(deleted_at);
                CREATE INDEX index_goals_archived ON goals(archived);
                CREATE TABLE goal_contributions (
                    id TEXT PRIMARY KEY NOT NULL,
                    goal_id TEXT NOT NULL,
                    amount_minor INTEGER NOT NULL,
                    local_date_epoch_day INTEGER NOT NULL,
                    wallet_id TEXT,
                    transfer_transaction_id TEXT,
                    note TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL
                );
                CREATE INDEX index_goal_contributions_goal_id ON goal_contributions(goal_id);
                CREATE INDEX index_goal_contributions_local_date_epoch_day ON goal_contributions(local_date_epoch_day);
                PRAGMA user_version = 4;
                """,
                    on: database
                )
                try execute("COMMIT;", on: database)
            } catch let error as EncryptedDatabaseError {
                try? execute("ROLLBACK;", on: database)
                if case let .statementFailed(status) = error {
                    throw EncryptedDatabaseError.migrationFailed(status)
                }
                throw error
            } catch {
                try? execute("ROLLBACK;", on: database)
                throw EncryptedDatabaseError.migrationFailed(sqlite3_errcode(database))
            }
        }

        if try userVersion(database) < 5 {
            try execute("BEGIN IMMEDIATE;", on: database)
            do {
                try execute(
                    """
                CREATE TABLE investment_holdings (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    asset_type TEXT NOT NULL,
                    cost_basis_minor INTEGER NOT NULL,
                    current_value_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL,
                    valuation_date_epoch_day INTEGER NOT NULL,
                    note TEXT NOT NULL DEFAULT '',
                    archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    deleted_at INTEGER
                );
                CREATE INDEX index_investment_holdings_deleted ON investment_holdings(deleted_at);
                CREATE INDEX index_investment_holdings_provider ON investment_holdings(provider);
                CREATE INDEX index_investment_holdings_asset_type ON investment_holdings(asset_type);
                CREATE INDEX index_investment_holdings_valuation_date ON investment_holdings(valuation_date_epoch_day);
                PRAGMA user_version = 5;
                """,
                    on: database
                )
                try execute("COMMIT;", on: database)
            } catch let error as EncryptedDatabaseError {
                try? execute("ROLLBACK;", on: database)
                if case let .statementFailed(status) = error {
                    throw EncryptedDatabaseError.migrationFailed(status)
                }
                throw error
            } catch {
                try? execute("ROLLBACK;", on: database)
                throw EncryptedDatabaseError.migrationFailed(sqlite3_errcode(database))
            }
        }

        guard try userVersion(database) < 6 else { return }
        try execute("BEGIN IMMEDIATE;", on: database)
        do {
            try execute(
                """
                CREATE TABLE commitments (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    target_minor INTEGER NOT NULL,
                    currency_code TEXT NOT NULL,
                    target_workspace_minor INTEGER NOT NULL,
                    exchange_rate TEXT,
                    exchange_rate_date TEXT,
                    due_epoch_day INTEGER NOT NULL,
                    category_id TEXT,
                    reminder_days_before INTEGER NOT NULL DEFAULT 0,
                    archived INTEGER NOT NULL DEFAULT 0 CHECK (archived IN (0, 1)),
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    revision INTEGER NOT NULL DEFAULT 1,
                    deleted_at INTEGER
                );
                CREATE INDEX index_commitments_due_epoch_day ON commitments(due_epoch_day);
                CREATE INDEX index_commitments_deleted ON commitments(deleted_at);
                CREATE INDEX index_commitments_archived ON commitments(archived);
                CREATE INDEX index_commitments_category_id ON commitments(category_id);
                CREATE TABLE commitment_payments (
                    id TEXT PRIMARY KEY NOT NULL,
                    commitment_id TEXT NOT NULL REFERENCES commitments(id) ON DELETE CASCADE,
                    transaction_id TEXT NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE CASCADE,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
                CREATE INDEX index_commitment_payments_commitment_id ON commitment_payments(commitment_id);
                PRAGMA user_version = 6;
                """,
                on: database
            )
            try execute("COMMIT;", on: database)
        } catch let error as EncryptedDatabaseError {
            try? execute("ROLLBACK;", on: database)
            if case let .statementFailed(status) = error {
                throw EncryptedDatabaseError.migrationFailed(status)
            }
            throw error
        } catch {
            try? execute("ROLLBACK;", on: database)
            throw EncryptedDatabaseError.migrationFailed(sqlite3_errcode(database))
        }
    }

    private static func userVersion(_ database: OpaquePointer) throws -> Int32 {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw EncryptedDatabaseError.statementFailed(prepareStatus)
        }
        defer { sqlite3_finalize(statement) }
        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_ROW else {
            throw EncryptedDatabaseError.statementFailed(stepStatus)
        }
        return sqlite3_column_int(statement, 0)
    }

    private static func cipherVersion(_ database: OpaquePointer) throws -> String? {
        try stringValue("PRAGMA cipher_version;", on: database)
    }

    private static func stringValue(_ sql: String, on database: OpaquePointer) throws -> String? {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareStatus == SQLITE_OK, let statement else {
            throw EncryptedDatabaseError.statementFailed(prepareStatus)
        }
        defer { sqlite3_finalize(statement) }
        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_ROW else { return nil }
        guard let value = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: value)
    }

    private static func execute(_ sql: String, on database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if let errorMessage {
            sqlite3_free(errorMessage)
        }
        guard status == SQLITE_OK else {
            throw EncryptedDatabaseError.statementFailed(status)
        }
    }

    private static func protect(directory: URL) throws {
        #if os(iOS)
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: directory.path
            )
            try excludeFromBackup(directory)
        } catch {
            throw EncryptedDatabaseError.fileProtectionFailed
        }
        #endif
    }

    private static func protectDatabaseFiles(at databaseURL: URL) throws {
        #if os(iOS)
        let fileManager = FileManager.default
        for path in [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm",
            databaseURL.path + "-journal",
        ] {
            guard fileManager.fileExists(atPath: path) else { continue }
            do {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: path
                )
                try excludeFromBackup(URL(fileURLWithPath: path))
            } catch {
                throw EncryptedDatabaseError.fileProtectionFailed
            }
        }
        #endif
    }

    #if os(iOS)
    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
    #endif
}
