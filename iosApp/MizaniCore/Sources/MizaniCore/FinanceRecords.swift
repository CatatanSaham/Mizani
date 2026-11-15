import Foundation

public struct IOSWorkspaceRecord: Equatable, Sendable {
    public let id: String
    public let name: String
    public let countryCode: String
    public let currencyCode: String
}

public struct IOSWalletRecord: Equatable, Sendable {
    public let id: String
    public let name: String
    public let typeName: String
    public let openingBalanceMinor: Int64
    public let currencyCode: String
    public let archived: Bool
    public let deleted: Bool
}

public struct IOSCategorySeed: Equatable, Sendable {
    public let id: String
    public let key: String
    public let name: String
    public let typeName: String
    public let icon: String
    public let colorHex: String

    public init(id: String, key: String, name: String, typeName: String, icon: String, colorHex: String) {
        self.id = id
        self.key = key
        self.name = name
        self.typeName = typeName
        self.icon = icon
        self.colorHex = colorHex
    }
}

public struct IOSCategoryRecord: Equatable, Sendable {
    public let id: String
    public let name: String
    public let typeName: String
    public let icon: String
    public let colorHex: String
    public let isDefault: Bool
    public let archived: Bool
    public let sortOrder: Int
    public let deleted: Bool
}

public struct IOSIncomeSourceKind: Equatable, Sendable {
    public let name: String
    public let label: String

    public init(name: String, label: String) {
        self.name = name
        self.label = label
    }
}

public struct IOSIncomeSourceRecord: Equatable, Sendable {
    public let id: String
    public let name: String
    public let kindName: String
    public let archived: Bool
    public let deleted: Bool

    public init(id: String, name: String, kindName: String, archived: Bool, deleted: Bool) {
        self.id = id
        self.name = name
        self.kindName = kindName
        self.archived = archived
        self.deleted = deleted
    }
}

public struct IOSGoalRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let targetMinor: Int64
    public let allocatedMinor: Int64
    public let targetEpochDay: Int64?
    public let linkedWalletId: String?
    public let priority: Int
    public let note: String
    public let icon: String
    public let archived: Bool
    public let deleted: Bool
}

public struct IOSGoalContributionRecord: Equatable, Sendable {
    public let id: String
    public let goalId: String
    public let amountMinor: Int64
    public let localDateEpochDay: Int64
    public let walletId: String?
    public let transferTransactionId: String?
    public let note: String
    public let createdAtMillis: Int64
}

public struct IOSInvestmentAssetType: Equatable, Sendable {
    public let name: String
    public let label: String

    public init(name: String, label: String) {
        self.name = name
        self.label = label
    }
}

public struct IOSInvestmentRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let provider: String
    public let assetTypeName: String
    public let costBasisMinor: Int64
    public let currentValueMinor: Int64
    public let currencyCode: String
    public let valuationDateEpochDay: Int64
    public let note: String
    public let archived: Bool
    public let deleted: Bool
}

public struct IOSInvestmentPortfolioSummary: Equatable, Sendable {
    public let holdingCount: Int
    public let costBasisMinor: Int64
    public let currentValueMinor: Int64
    public let gainLossMinor: Int64

    public init(holdingCount: Int, costBasisMinor: Int64, currentValueMinor: Int64, gainLossMinor: Int64) {
        self.holdingCount = holdingCount
        self.costBasisMinor = costBasisMinor
        self.currentValueMinor = currentValueMinor
        self.gainLossMinor = gainLossMinor
    }
}

public struct IOSCommitmentRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let targetMinor: Int64
    public let currencyCode: String
    public let targetWorkspaceMinor: Int64
    public let exchangeRate: String?
    public let exchangeRateDate: String?
    public let dueEpochDay: Int64
    public let categoryId: String?
    public let reminderDaysBefore: Int
    public let archived: Bool
    public let deleted: Bool
}

public struct IOSCommitmentDraft: Equatable, Sendable {
    public let name: String
    public let targetMinor: Int64
    public let currencyCode: String
    public let targetWorkspaceMinor: Int64
    public let exchangeRate: String?
    public let exchangeRateDate: String?
    public let dueEpochDay: Int64
    public let categoryId: String?
    public let reminderDaysBefore: Int

    public init(
        name: String,
        targetMinor: Int64,
        currencyCode: String,
        targetWorkspaceMinor: Int64,
        exchangeRate: String?,
        exchangeRateDate: String?,
        dueEpochDay: Int64,
        categoryId: String?,
        reminderDaysBefore: Int
    ) {
        self.name = name
        self.targetMinor = targetMinor
        self.currencyCode = currencyCode
        self.targetWorkspaceMinor = targetWorkspaceMinor
        self.exchangeRate = exchangeRate
        self.exchangeRateDate = exchangeRateDate
        self.dueEpochDay = dueEpochDay
        self.categoryId = categoryId
        self.reminderDaysBefore = reminderDaysBefore
    }
}

public struct IOSCommitmentPaymentRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let commitmentId: String
    public let transactionId: String
    public let createdAtMillis: Int64
}

public struct IOSCommitmentProgress: Equatable, Identifiable, Sendable {
    public let commitment: IOSCommitmentRecord
    public let paidMinor: Int64?
    public let remainingMinor: Int64?
    public let paidWorkspaceMinor: Int64?
    public let remainingWorkspaceMinor: Int64?

    public var id: String { commitment.id }

    public var isAvailable: Bool {
        paidMinor != nil && remainingMinor != nil &&
            paidWorkspaceMinor != nil && remainingWorkspaceMinor != nil
    }
}

public struct IOSTransactionRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let typeName: String
    public let amountMinor: Int64
    public let feeMinor: Int64
    public let currencyCode: String
    public let walletId: String
    public let destinationWalletId: String?
    public let categoryId: String?
    public let feeCategoryId: String?
    public let incomeSourceId: String?
    public let linkedTransactionId: String?
    public let note: String
    public let occurredAtMillis: Int64
    public let localDateEpochDay: Int64
    public let deleted: Bool
}

public struct IOSLedgerSnapshot: Equatable, Sendable {
    public let workspace: IOSWorkspaceRecord?
    public let wallets: [IOSWalletRecord]
    public let categories: [IOSCategoryRecord]
    public let incomeSources: [IOSIncomeSourceRecord]
    public let goals: [IOSGoalRecord]
    public let goalContributions: [IOSGoalContributionRecord]
    public let investments: [IOSInvestmentRecord]
    public let investmentSummary: IOSInvestmentPortfolioSummary?
    public let commitments: [IOSCommitmentRecord]
    public let commitmentPayments: [IOSCommitmentPaymentRecord]
    public let transactions: [IOSTransactionRecord]
    public let walletBalancesMinor: [String: Int64]
    public let balancesAvailable: Bool

    public init(
        workspace: IOSWorkspaceRecord?,
        wallets: [IOSWalletRecord],
        categories: [IOSCategoryRecord],
        incomeSources: [IOSIncomeSourceRecord] = [],
        goals: [IOSGoalRecord] = [],
        goalContributions: [IOSGoalContributionRecord] = [],
        investments: [IOSInvestmentRecord] = [],
        investmentSummary: IOSInvestmentPortfolioSummary? = nil,
        commitments: [IOSCommitmentRecord] = [],
        commitmentPayments: [IOSCommitmentPaymentRecord] = [],
        transactions: [IOSTransactionRecord],
        walletBalancesMinor: [String: Int64],
        balancesAvailable: Bool = true
    ) {
        self.workspace = workspace
        self.wallets = wallets
        self.categories = categories
        self.incomeSources = incomeSources
        self.goals = goals
        self.goalContributions = goalContributions
        self.investments = investments
        self.investmentSummary = investmentSummary
        self.commitments = commitments
        self.commitmentPayments = commitmentPayments
        self.transactions = transactions
        self.walletBalancesMinor = walletBalancesMinor
        self.balancesAvailable = balancesAvailable
    }

    public var activeWallets: [IOSWalletRecord] {
        wallets.filter { !$0.archived && !$0.deleted }
    }

    public var activeTransactions: [IOSTransactionRecord] {
        transactions.filter { !$0.deleted }
    }

    public var activeGoals: [IOSGoalRecord] {
        goals.filter { !$0.archived && !$0.deleted }
    }

    public var archivedGoals: [IOSGoalRecord] {
        goals.filter { $0.archived && !$0.deleted }
    }

    public var activeInvestments: [IOSInvestmentRecord] {
        investments.filter { !$0.archived && !$0.deleted }
    }

    public var archivedInvestments: [IOSInvestmentRecord] {
        investments.filter { $0.archived && !$0.deleted }
    }

    public var activeCommitments: [IOSCommitmentRecord] {
        commitments.filter { !$0.archived && !$0.deleted }
    }

    public var archivedCommitments: [IOSCommitmentRecord] {
        commitments.filter { $0.archived && !$0.deleted }
    }

    /// Computes progress from linked active expenses and active refunds. Associations never add
    /// ledger rows, and malformed legacy totals stay explicitly unavailable instead of wrapping.
    public func commitmentProgress(using rules: any IOSFinanceRulesProviding) -> [IOSCommitmentProgress] {
        var refundsByExpenseId: [String: Int64] = [:]
        var invalidRefundTotals = Set<String>()
        for transaction in transactions where !transaction.deleted && transaction.typeName == "REFUND" {
            guard let expenseId = transaction.linkedTransactionId else { continue }
            let (sum, overflow) = (refundsByExpenseId[expenseId] ?? 0).addingReportingOverflow(transaction.amountMinor)
            if overflow {
                invalidRefundTotals.insert(expenseId)
            } else {
                refundsByExpenseId[expenseId] = sum
            }
        }

        let transactionsById = Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
        return commitments.filter { !$0.deleted }.map { commitment in
            guard let workspaceCurrencyCode = workspace?.currencyCode,
                  commitment.targetMinor > 0,
                  commitment.targetWorkspaceMinor > 0 else {
                return IOSCommitmentProgress(
                    commitment: commitment,
                    paidMinor: nil,
                    remainingMinor: nil,
                    paidWorkspaceMinor: nil,
                    remainingWorkspaceMinor: nil
                )
            }

            var paidWorkspaceMinor: Int64 = 0
            var isAvailable = true
            for payment in commitmentPayments where payment.commitmentId == commitment.id {
                guard let transaction = transactionsById[payment.transactionId],
                      !transaction.deleted,
                      transaction.typeName == "EXPENSE" else { continue }
                if invalidRefundTotals.contains(transaction.id) {
                    isAvailable = false
                    break
                }
                let netMinor = max(0, transaction.amountMinor - (refundsByExpenseId[transaction.id] ?? 0))
                let (sum, overflow) = paidWorkspaceMinor.addingReportingOverflow(netMinor)
                guard !overflow else {
                    isAvailable = false
                    break
                }
                paidWorkspaceMinor = sum
            }

            guard isAvailable,
                  let remainingWorkspaceMinor = checkedSubtract(commitment.targetWorkspaceMinor, paidWorkspaceMinor).map({ max(0, $0) }),
                  let paidConverted = rules.workspaceToCommitmentMinor(
                      amountMinor: paidWorkspaceMinor,
                      workspaceCurrencyCode: workspaceCurrencyCode,
                      commitmentCurrencyCode: commitment.currencyCode,
                      exchangeRate: commitment.exchangeRate
                  ).flatMap({ Int64($0) }),
                  let remainingConverted = rules.workspaceToCommitmentMinor(
                      amountMinor: remainingWorkspaceMinor,
                      workspaceCurrencyCode: workspaceCurrencyCode,
                      commitmentCurrencyCode: commitment.currencyCode,
                      exchangeRate: commitment.exchangeRate
                  ).flatMap({ Int64($0) }) else {
                return IOSCommitmentProgress(
                    commitment: commitment,
                    paidMinor: nil,
                    remainingMinor: nil,
                    paidWorkspaceMinor: nil,
                    remainingWorkspaceMinor: nil
                )
            }
            return IOSCommitmentProgress(
                commitment: commitment,
                paidMinor: min(paidConverted, commitment.targetMinor),
                remainingMinor: remainingConverted,
                paidWorkspaceMinor: paidWorkspaceMinor,
                remainingWorkspaceMinor: remainingWorkspaceMinor
            )
        }
    }

    public var deletedTransactions: [IOSTransactionRecord] {
        transactions.filter(\.deleted)
    }

    public func activeCategories(typeName: String) -> [IOSCategoryRecord] {
        categories.filter { $0.typeName == typeName && !$0.archived && !$0.deleted }
    }

    public var totalBalanceMinor: Int64? {
        guard balancesAvailable else { return nil }
        var total: Int64 = 0
        for wallet in activeWallets {
            guard let balance = walletBalancesMinor[wallet.id] else { return nil }
            let (sum, overflow) = total.addingReportingOverflow(balance)
            guard !overflow else { return nil }
            total = sum
        }
        return total
    }
}

private func checkedSubtract(_ left: Int64, _ right: Int64) -> Int64? {
    let (value, overflow) = left.subtractingReportingOverflow(right)
    return overflow ? nil : value
}

/// An in-memory search index for the native Activity screen. It contains display text only and is
/// rebuilt from the current snapshot; it is never persisted or sent outside the device.
public struct IOSActivitySearchIndex {
    private let normalizedTextByTransactionId: [String: String]
    private let normalizeSearchText: (String) -> String
    private let containsNormalized: (String, String) -> Bool

    public init(
        snapshot: IOSLedgerSnapshot,
        normalizeSearchText: @escaping (String) -> String,
        containsNormalized: @escaping (String, String) -> Bool
    ) {
        self.normalizeSearchText = normalizeSearchText
        self.containsNormalized = containsNormalized
        let walletsById = Dictionary(uniqueKeysWithValues: snapshot.wallets.map { ($0.id, $0.name) })
        let categoriesById = Dictionary(uniqueKeysWithValues: snapshot.categories.map { ($0.id, $0.name) })
        let incomeSourcesById = Dictionary(uniqueKeysWithValues: snapshot.incomeSources.map { ($0.id, $0.name) })

        normalizedTextByTransactionId = Dictionary(uniqueKeysWithValues: snapshot.transactions.map { transaction in
            let displayType = transaction.typeName
                .replacingOccurrences(of: "_", with: " ")
            let sourceWallet = walletsById[transaction.walletId] ?? ""
            let destinationWallet = transaction.destinationWalletId.flatMap { walletsById[$0] } ?? ""
            let category = transaction.categoryId.flatMap { categoriesById[$0] } ?? ""
            let incomeSource = transaction.incomeSourceId.flatMap { incomeSourcesById[$0] } ?? ""
            let searchableText = [
                transaction.note,
                displayType,
                category,
                incomeSource,
                sourceWallet,
                destinationWallet,
                transaction.currencyCode,
                String(transaction.amountMinor),
                String(transaction.feeMinor),
            ].joined(separator: " ")
            return (transaction.id, normalizeSearchText(searchableText))
        })
    }

    /// Returns matching rows in their original ledger order. An empty query leaves the rows intact.
    public func matchingTransactions(
        _ transactions: [IOSTransactionRecord],
        query: String
    ) -> [IOSTransactionRecord] {
        let normalizedQuery = normalizeSearchText(query)
        return transactions.filter { transaction in
            containsNormalized(normalizedTextByTransactionId[transaction.id, default: ""], normalizedQuery)
        }
    }
}

/// Shared business rules are injected from the KMP framework by the native app target.
public protocol IOSFinanceRulesProviding: Sendable {
    func transactionValidationError(typeName: String, amountMinor: Int64, feeMinor: Int64) -> String?
    func isSupportedAmountMinor(_ amountMinor: Int64) -> Bool
    func isValidWalletTypeName(_ typeName: String) -> Bool
    func isSupportedCurrencyCode(_ currencyCode: String) -> Bool
    func canArchiveCategory(activeCategoryCount: Int64) -> Bool
    func canAssignIncomeSource(typeName: String, hasIncomeSource: Bool) -> Bool
    func defaultCategories() -> [IOSCategorySeed]
    func incomeSourceKinds() -> [IOSIncomeSourceKind]
    func isSupportedGoalTargetMinor(_ amountMinor: Int64) -> Bool
    func isSupportedGoalContributionMinor(_ amountMinor: Int64) -> Bool
    func goalAllocatedMinorAfterContribution(currentAllocatedMinor: Int64, contributionMinor: Int64) -> String?
    func commitmentDraftValidationError(
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        targetMinor: Int64,
        targetWorkspaceMinor: Int64,
        exchangeRate: String?,
        exchangeRateDate: String?,
        todayEpochDay: Int64
    ) -> String?
    func commitmentToWorkspaceMinor(
        amountMinor: Int64,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?
    ) -> String?
    func workspaceToCommitmentMinor(
        amountMinor: Int64,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?
    ) -> String?
    func investmentAssetTypes() -> [IOSInvestmentAssetType]
    func investmentDraftValidationError(
        name: String,
        provider: String,
        note: String,
        assetTypeName: String,
        costBasisMinor: Int64,
        currentValueMinor: Int64,
        valuationEpochDay: Int64,
        todayEpochDay: Int64
    ) -> String?
    func investmentPortfolioSummary(
        costBasisMinor: [Int64],
        currentValueMinor: [Int64],
        active: [Bool]
    ) -> IOSInvestmentPortfolioSummary?
    func feesCategoryId() -> String
    func walletBalanceMinor(walletId: String, openingBalanceMinor: Int64, transactions: [IOSTransactionRecord]) -> String?
}

public typealias IOSFinanceBalanceValidator = @Sendable (
    [IOSWalletRecord],
    [IOSTransactionRecord]
) throws -> Void

public typealias IOSFinanceCategoryArchiveValidator = @Sendable (Int64) -> Bool
public typealias IOSFinanceIncomeSourceKindValidator = @Sendable (String) -> Bool
public typealias IOSFinanceInvestmentAssetTypeValidator = @Sendable (String) -> Bool

public enum IOSFinanceRepositoryError: Error, Equatable {
    case noWorkspace
    case workspaceAlreadyExists
    case walletNotFound
    case walletUnavailable
    case categoryNotFound
    case categoryUnavailable
    case categoryTypeMismatch
    case categoryLastActive
    case categoryOrderUnavailable
    case invalidIncomeSourceKind
    case incomeSourceNotFound
    case incomeSourceUnavailable
    case goalNotFound
    case goalUnavailable
    case investmentNotFound
    case investmentUnavailable
    case investmentDraftRejected(String)
    case commitmentNotFound
    case commitmentUnavailable
    case commitmentDraftRejected(String)
    case commitmentPaymentUnavailable
    case sharedCatalogUnavailable
    case invalidWalletType
    case invalidTransactionType
    case unsupportedTransactionType
    case invalidTransferDestination
    case refundTargetUnavailable
    case transactionNotFound
    case transactionUnavailable
    case transactionHasRefunds
    case invalidCurrency
    case invalidName
    case amountOutsideSupportedRange
    case transactionRejected(String)
    case balanceUnavailable
}

private struct IOSFinanceBalanceCalculation {
    let balances: [String: Int64]
    let isAvailable: Bool
}

private func calculatedWalletBalances(
    wallets: [IOSWalletRecord],
    transactions: [IOSTransactionRecord],
    rules: any IOSFinanceRulesProviding
) -> IOSFinanceBalanceCalculation {
    var balances: [String: Int64] = [:]
    var activeTotal: Int64 = 0
    var isAvailable = true
    var hasUnknownTransactionType = false
    var transactionsByWallet: [String: [IOSTransactionRecord]] = [:]
    for transaction in transactions {
        switch transaction.typeName {
        case "INCOME", "EXPENSE", "REFUND", "ADJUSTMENT":
            transactionsByWallet[transaction.walletId, default: []].append(transaction)
        case "TRANSFER":
            transactionsByWallet[transaction.walletId, default: []].append(transaction)
            if let destinationWalletId = transaction.destinationWalletId,
               destinationWalletId != transaction.walletId {
                transactionsByWallet[destinationWalletId, default: []].append(transaction)
            }
        default:
            hasUnknownTransactionType = true
        }
    }
    for wallet in wallets where !wallet.deleted {
        guard !hasUnknownTransactionType else {
            isAvailable = false
            continue
        }
        guard let value = rules.walletBalanceMinor(
            walletId: wallet.id,
            openingBalanceMinor: wallet.openingBalanceMinor,
            transactions: transactionsByWallet[wallet.id, default: []]
        ), let balance = Int64(value) else {
            isAvailable = false
            continue
        }
        balances[wallet.id] = balance
        if !wallet.archived {
            let (sum, overflow) = activeTotal.addingReportingOverflow(balance)
            if overflow {
                isAvailable = false
            } else {
                activeTotal = sum
            }
        }
    }
    return IOSFinanceBalanceCalculation(balances: balances, isAvailable: isAvailable)
}

/// Validates native drafts with KMP rules before committing them to the encrypted store.
public actor IOSFinanceRepository {
    private let database: EncryptedFinanceDatabase
    private let rules: any IOSFinanceRulesProviding

    public init(
        databaseDirectoryURL: URL,
        keyProvider: any DatabaseKeyProviding,
        rules: any IOSFinanceRulesProviding
    ) throws {
        let categorySeeds = rules.defaultCategories()
        let feeCategoryId = rules.feesCategoryId()
        let incomeSourceKinds = rules.incomeSourceKinds()
        let categoryIds = categorySeeds.map(\.id)
        let categoryKeys = categorySeeds.map(\.key)
        let categoryTypes: Set<String> = ["EXPENSE", "INCOME"]
        guard !categorySeeds.isEmpty,
              Set(categoryIds).count == categorySeeds.count,
              Set(categoryKeys).count == categorySeeds.count,
              categorySeeds.allSatisfy({
                  !$0.id.isEmpty && !$0.key.isEmpty && !$0.name.isEmpty &&
                      categoryTypes.contains($0.typeName)
              }),
              categorySeeds.contains(where: { $0.typeName == "EXPENSE" }),
              categorySeeds.contains(where: { $0.typeName == "INCOME" }),
              categorySeeds.contains(where: { $0.id == feeCategoryId && $0.typeName == "EXPENSE" }) else {
            throw IOSFinanceRepositoryError.sharedCatalogUnavailable
        }
        guard !incomeSourceKinds.isEmpty,
              Set(incomeSourceKinds.map(\.name)).count == incomeSourceKinds.count,
              incomeSourceKinds.allSatisfy({ !$0.name.isEmpty && !$0.label.isEmpty }) else {
            throw IOSFinanceRepositoryError.sharedCatalogUnavailable
        }
        let investmentAssetTypes = rules.investmentAssetTypes()
        guard !investmentAssetTypes.isEmpty,
              Set(investmentAssetTypes.map(\.name)).count == investmentAssetTypes.count,
              investmentAssetTypes.allSatisfy({ !$0.name.isEmpty && !$0.label.isEmpty }) else {
            throw IOSFinanceRepositoryError.sharedCatalogUnavailable
        }
        self.database = try EncryptedFinanceDatabase(
            databaseDirectoryURL: databaseDirectoryURL,
            keyProvider: keyProvider,
            defaultCategories: categorySeeds,
            balanceValidator: { wallets, transactions in
                let calculation = calculatedWalletBalances(wallets: wallets, transactions: transactions, rules: rules)
                guard calculation.isAvailable else { throw IOSFinanceRepositoryError.balanceUnavailable }
            },
            categoryArchiveValidator: { activeCount in
                rules.canArchiveCategory(activeCategoryCount: activeCount)
            },
            incomeSourceKindValidator: { kindName in
                incomeSourceKinds.contains(where: { $0.name == kindName })
            },
            investmentAssetTypeValidator: { assetTypeName in
                investmentAssetTypes.contains(where: { $0.name == assetTypeName })
            }
        )
        self.rules = rules
    }

    public func snapshot() async throws -> IOSLedgerSnapshot {
        let stored = try await database.readFinanceSnapshot()
        let calculation = calculatedWalletBalances(
            wallets: stored.wallets,
            transactions: stored.transactions,
            rules: rules
        )
        return IOSLedgerSnapshot(
            workspace: stored.workspace,
            wallets: stored.wallets,
            categories: stored.categories,
            incomeSources: stored.incomeSources,
            goals: stored.goals,
            goalContributions: stored.goalContributions,
            investments: stored.investments,
            investmentSummary: rules.investmentPortfolioSummary(
                costBasisMinor: stored.investments.map(\.costBasisMinor),
                currentValueMinor: stored.investments.map(\.currentValueMinor),
                active: stored.investments.map { !$0.archived && !$0.deleted }
            ),
            commitments: stored.commitments,
            commitmentPayments: stored.commitmentPayments,
            transactions: stored.transactions,
            walletBalancesMinor: calculation.balances,
            balancesAvailable: calculation.isAvailable
        )
    }

    /// Closes the encrypted connection so the owning session can discard its repository on lock.
    public func close() async throws {
        try await database.close()
    }

    /// Creates the initial workspace and first wallet in one SQLite transaction.
    @discardableResult
    public func createWorkspace(
        name: String,
        countryCode: String,
        currencyCode: String,
        walletName: String,
        walletTypeName: String,
        openingBalanceMinor: Int64
    ) async throws -> String {
        let existing = try await database.readFinanceSnapshot()
        guard existing.workspace == nil else {
            throw IOSFinanceRepositoryError.workspaceAlreadyExists
        }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedWalletName = walletName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, !cleanedWalletName.isEmpty,
              cleanedName.count <= 80, cleanedWalletName.count <= 80 else {
            throw IOSFinanceRepositoryError.invalidName
        }
        try validateCountryAndCurrency(countryCode: countryCode, currencyCode: currencyCode)
        guard rules.isValidWalletTypeName(walletTypeName) else {
            throw IOSFinanceRepositoryError.invalidWalletType
        }
        guard rules.isSupportedAmountMinor(openingBalanceMinor) else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        return try await database.insertInitialWorkspace(
            name: cleanedName,
            countryCode: countryCode.uppercased(),
            currencyCode: currencyCode.uppercased(),
            walletName: cleanedWalletName,
            walletTypeName: walletTypeName,
            openingBalanceMinor: openingBalanceMinor,
            defaultCategories: rules.defaultCategories()
        )
    }

    @discardableResult
    public func addWallet(name: String, typeName: String, openingBalanceMinor: Int64) async throws -> String {
        let snapshot = try await database.readFinanceSnapshot()
        guard let workspace = snapshot.workspace else { throw IOSFinanceRepositoryError.noWorkspace }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 80 else { throw IOSFinanceRepositoryError.invalidName }
        guard rules.isValidWalletTypeName(typeName) else { throw IOSFinanceRepositoryError.invalidWalletType }
        guard rules.isSupportedAmountMinor(openingBalanceMinor) else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        return try await database.insertWallet(
            name: cleanedName,
            typeName: typeName,
            openingBalanceMinor: openingBalanceMinor,
            currencyCode: workspace.currencyCode
        )
    }

    @discardableResult
    public func addCategory(name: String, typeName: String, icon: String, colorHex: String) async throws -> String {
        let snapshot = try await database.readFinanceSnapshot()
        guard snapshot.workspace != nil else { throw IOSFinanceRepositoryError.noWorkspace }
        try Self.validateCategoryTypeName(typeName)
        let cleanedName = try Self.cleanedCategoryName(name)
        return try await database.insertCategory(
            name: cleanedName,
            typeName: typeName,
            icon: icon,
            colorHex: colorHex
        )
    }

    public func updateCategory(id: String, name: String, icon: String, colorHex: String) async throws {
        let cleanedName = try Self.cleanedCategoryName(name)
        try await database.updateCategory(id: id, name: cleanedName, icon: icon, colorHex: colorHex)
    }

    public func setCategoryArchived(id: String, archived: Bool) async throws {
        try await database.setCategoryArchived(id: id, archived: archived)
    }

    public func moveCategory(id: String, direction: Int) async throws {
        try await database.moveCategory(id: id, direction: direction)
    }

    @discardableResult
    public func addIncomeSource(name: String, kindName: String) async throws -> String {
        let snapshot = try await database.readFinanceSnapshot()
        guard snapshot.workspace != nil else { throw IOSFinanceRepositoryError.noWorkspace }
        let cleanedName = try Self.cleanedCategoryName(name)
        return try await database.insertIncomeSource(name: cleanedName, kindName: kindName)
    }

    public func updateIncomeSource(id: String, name: String, kindName: String) async throws {
        let cleanedName = try Self.cleanedCategoryName(name)
        try await database.updateIncomeSource(id: id, name: cleanedName, kindName: kindName)
    }

    @discardableResult
    public func saveGoal(
        id: String? = nil,
        name: String,
        targetMinor: Int64,
        targetDate: Date? = nil,
        linkedWalletId: String? = nil,
        priority: Int = 2,
        note: String = "",
        icon: String = "savings"
    ) async throws -> String {
        let snapshot = try await database.readFinanceSnapshot()
        guard snapshot.workspace != nil else { throw IOSFinanceRepositoryError.noWorkspace }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty, cleanedName.count <= 80 else {
            throw IOSFinanceRepositoryError.invalidName
        }
        guard rules.isSupportedGoalTargetMinor(targetMinor) else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        return try await database.saveGoal(
            id: id,
            name: cleanedName,
            targetMinor: targetMinor,
            targetEpochDay: targetDate.map(Self.localEpochDay),
            linkedWalletId: linkedWalletId,
            priority: min(3, max(1, priority)),
            note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)),
            icon: String(icon.prefix(64))
        )
    }

    public func contributeToGoal(
        goalId: String,
        amountMinor: Int64,
        fromWalletId: String? = nil,
        date: Date = Date(),
        note: String = ""
    ) async throws {
        guard rules.isSupportedGoalContributionMinor(amountMinor) else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        let snapshot = try await database.readFinanceSnapshot()
        guard let goal = snapshot.goals.first(where: { $0.id == goalId }) else {
            throw IOSFinanceRepositoryError.goalNotFound
        }
        guard !goal.archived, !goal.deleted else {
            throw IOSFinanceRepositoryError.goalUnavailable
        }
        guard let allocatedText = rules.goalAllocatedMinorAfterContribution(
            currentAllocatedMinor: goal.allocatedMinor,
            contributionMinor: amountMinor
        ), let allocatedAfter = Int64(allocatedText) else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        try await database.insertGoalContribution(
            goalId: goalId,
            amountMinor: amountMinor,
            allocatedMinorAfterContribution: allocatedAfter,
            fromWalletId: fromWalletId,
            localDateEpochDay: Self.localEpochDay(date),
            note: String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        )
    }

    public func setGoalArchived(id: String, archived: Bool) async throws {
        try await database.setGoalArchived(id: id, archived: archived)
    }

    @discardableResult
    public func saveInvestmentHolding(
        id: String? = nil,
        name: String,
        provider: String,
        assetTypeName: String,
        costBasisMinor: Int64,
        currentValueMinor: Int64,
        valuationDate: Date = Date(),
        note: String = ""
    ) async throws -> String {
        let snapshot = try await database.readFinanceSnapshot()
        guard let workspace = snapshot.workspace else { throw IOSFinanceRepositoryError.noWorkspace }
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let valuationEpochDay = Self.investmentLocalEpochDay(valuationDate)
        if let errorCode = rules.investmentDraftValidationError(
            name: cleanedName,
            provider: cleanedProvider,
            note: cleanedNote,
            assetTypeName: assetTypeName,
            costBasisMinor: costBasisMinor,
            currentValueMinor: currentValueMinor,
            valuationEpochDay: valuationEpochDay,
            todayEpochDay: Self.investmentLocalEpochDay(Date())
        ) {
            throw IOSFinanceRepositoryError.investmentDraftRejected(errorCode)
        }
        return try await database.saveInvestmentHolding(
            id: id,
            name: cleanedName,
            provider: cleanedProvider,
            assetTypeName: assetTypeName,
            costBasisMinor: costBasisMinor,
            currentValueMinor: currentValueMinor,
            currencyCode: workspace.currencyCode,
            valuationDateEpochDay: valuationEpochDay,
            note: cleanedNote
        )
    }

    public func setInvestmentHoldingArchived(id: String, archived: Bool) async throws {
        try await database.setInvestmentHoldingArchived(id: id, archived: archived)
    }

    public func deleteInvestmentHolding(id: String) async throws {
        try await database.deleteInvestmentHolding(id: id)
    }

    private static func localEpochDay(_ date: Date) -> Int64 {
        let epoch = Date(timeIntervalSince1970: 0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return Int64(calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: epoch),
            to: calendar.startOfDay(for: date)
        ).day ?? 0)
    }

    static func investmentLocalEpochDay(_ date: Date, timeZone: TimeZone = .current) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var epochComponents = DateComponents()
        epochComponents.year = 1970
        epochComponents.month = 1
        epochComponents.day = 1
        guard let epochStart = calendar.date(from: epochComponents) else { return 0 }
        return Int64(calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: epochStart),
            to: calendar.startOfDay(for: date)
        ).day ?? 0)
    }

    public static func commitmentLocalEpochDay(_ date: Date, timeZone: TimeZone = .current) -> Int64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var epochComponents = DateComponents()
        epochComponents.year = 1970
        epochComponents.month = 1
        epochComponents.day = 1
        guard let epochStart = calendar.date(from: epochComponents) else { return 0 }
        return Int64(calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: epochStart),
            to: calendar.startOfDay(for: date)
        ).day ?? 0)
    }

    public static func commitmentDate(fromEpochDay epochDay: Int64, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var epochComponents = DateComponents()
        epochComponents.year = 1970
        epochComponents.month = 1
        epochComponents.day = 1
        guard let epochStart = calendar.date(from: epochComponents),
              let dayOffset = Int(exactly: epochDay),
              let date = calendar.date(byAdding: .day, value: dayOffset, to: epochStart) else {
            return epochStartFallback(timeZone: timeZone)
        }
        return date
    }

    private static func epochStartFallback(timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 1970
        components.month = 1
        components.day = 1
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    @discardableResult
    public func saveCommitment(id: String? = nil, draft: IOSCommitmentDraft) async throws -> String {
        let snapshot = try await database.readFinanceSnapshot()
        guard let workspace = snapshot.workspace else { throw IOSFinanceRepositoryError.noWorkspace }
        let cleanedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { throw IOSFinanceRepositoryError.invalidName }
        guard cleanedName.count <= 80 else {
            throw IOSFinanceRepositoryError.commitmentDraftRejected("name_too_long")
        }
        guard (0...30).contains(draft.reminderDaysBefore) else {
            throw IOSFinanceRepositoryError.commitmentDraftRejected("reminder_days_invalid")
        }
        if let categoryId = draft.categoryId {
            guard let category = snapshot.categories.first(where: { $0.id == categoryId }) else {
                throw IOSFinanceRepositoryError.categoryNotFound
            }
            guard !category.deleted else { throw IOSFinanceRepositoryError.categoryUnavailable }
            guard category.typeName == "EXPENSE" else { throw IOSFinanceRepositoryError.categoryTypeMismatch }
        }
        let todayEpochDay = Int64(Date().timeIntervalSince1970 / 86_400)
        if let error = rules.commitmentDraftValidationError(
            workspaceCurrencyCode: workspace.currencyCode,
            commitmentCurrencyCode: draft.currencyCode,
            targetMinor: draft.targetMinor,
            targetWorkspaceMinor: draft.targetWorkspaceMinor,
            exchangeRate: draft.exchangeRate,
            exchangeRateDate: draft.exchangeRateDate,
            todayEpochDay: todayEpochDay
        ) {
            throw IOSFinanceRepositoryError.commitmentDraftRejected(error)
        }
        return try await database.saveCommitment(
            id: id,
            name: cleanedName,
            targetMinor: draft.targetMinor,
            currencyCode: draft.currencyCode,
            targetWorkspaceMinor: draft.targetWorkspaceMinor,
            exchangeRate: draft.exchangeRate,
            exchangeRateDate: draft.exchangeRateDate,
            dueEpochDay: draft.dueEpochDay,
            categoryId: draft.categoryId,
            reminderDaysBefore: draft.reminderDaysBefore
        )
    }

    public func setCommitmentArchived(id: String, archived: Bool) async throws {
        try await database.setCommitmentArchived(id: id, archived: archived)
    }

    public func deleteCommitment(id: String) async throws {
        try await database.deleteCommitment(id: id)
    }

    @discardableResult
    public func linkExpenseToCommitment(commitmentId: String, transactionId: String) async throws -> String {
        try await database.linkExpenseToCommitment(commitmentId: commitmentId, transactionId: transactionId)
    }

    public func unlinkCommitmentPayment(id: String) async throws {
        try await database.unlinkCommitmentPayment(id: id)
    }

    private static func validateCategoryTypeName(_ typeName: String) throws {
        guard typeName == "EXPENSE" || typeName == "INCOME" else {
            throw IOSFinanceRepositoryError.categoryTypeMismatch
        }
    }

    private static func cleanedCategoryName(_ name: String) throws -> String {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedName.isEmpty else { throw IOSFinanceRepositoryError.invalidName }
        return cleanedName
    }

    @discardableResult
    public func recordTransaction(
        typeName: String,
        amountMinor: Int64,
        feeMinor: Int64 = 0,
        walletId: String,
        categoryId: String? = nil,
        incomeSourceId: String? = nil,
        linkedTransactionId: String? = nil,
        transactionId: String? = nil,
        note: String,
        occurredAt: Date = Date()
    ) async throws -> String {
        guard typeName == "EXPENSE" || typeName == "INCOME" || typeName == "REFUND" || typeName == "ADJUSTMENT" else {
            throw IOSFinanceRepositoryError.unsupportedTransactionType
        }
        guard typeName == "REFUND" || linkedTransactionId == nil else {
            throw IOSFinanceRepositoryError.invalidTransactionType
        }
        guard rules.isSupportedAmountMinor(amountMinor), rules.isSupportedAmountMinor(feeMinor) else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        if let validationError = rules.transactionValidationError(
            typeName: typeName,
            amountMinor: amountMinor,
            feeMinor: feeMinor
        ) {
            throw IOSFinanceRepositoryError.transactionRejected(validationError)
        }
        guard rules.canAssignIncomeSource(typeName: typeName, hasIncomeSource: incomeSourceId != nil) else {
            throw IOSFinanceRepositoryError.invalidTransactionType
        }
        let snapshot = try await database.readFinanceSnapshot()
        let existingTransaction = transactionId.flatMap { id in
            snapshot.transactions.first(where: { $0.id == id })
        }
        let preservesExistingSourceReference = existingTransaction?.typeName == "INCOME" &&
            existingTransaction?.incomeSourceId == incomeSourceId
        guard let workspace = snapshot.workspace else { throw IOSFinanceRepositoryError.noWorkspace }
        guard let wallet = snapshot.wallets.first(where: { $0.id == walletId }) else {
            throw IOSFinanceRepositoryError.walletNotFound
        }
        guard !wallet.archived && !wallet.deleted else { throw IOSFinanceRepositoryError.walletUnavailable }
        guard wallet.currencyCode == workspace.currencyCode else { throw IOSFinanceRepositoryError.invalidCurrency }

        if let incomeSourceId {
            if let source = snapshot.incomeSources.first(where: { $0.id == incomeSourceId }) {
                guard !source.deleted || preservesExistingSourceReference else {
                    throw IOSFinanceRepositoryError.incomeSourceUnavailable
                }
            } else {
                guard preservesExistingSourceReference else {
                    throw IOSFinanceRepositoryError.incomeSourceNotFound
                }
            }
        }

        var resolvedCategoryId = categoryId
        switch typeName {
        case "EXPENSE", "INCOME":
            guard let resolvedCategoryId else { throw IOSFinanceRepositoryError.categoryNotFound }
            let expectedType = typeName
            guard let category = snapshot.categories.first(where: { $0.id == resolvedCategoryId }) else {
                throw IOSFinanceRepositoryError.categoryNotFound
            }
            guard !category.deleted else { throw IOSFinanceRepositoryError.categoryUnavailable }
            guard category.typeName == expectedType else { throw IOSFinanceRepositoryError.categoryTypeMismatch }
        case "REFUND":
            if let linkedTransactionId {
                let original = snapshot.transactions.first(where: { $0.id == linkedTransactionId })
                let keepsExistingLink = existingTransaction?.typeName == "REFUND" &&
                    existingTransaction?.linkedTransactionId == linkedTransactionId &&
                    original?.typeName == "EXPENSE"
                guard original?.typeName == "EXPENSE" &&
                    (original?.deleted == false || keepsExistingLink) else {
                    throw IOSFinanceRepositoryError.refundTargetUnavailable
                }
                if resolvedCategoryId == nil { resolvedCategoryId = original?.categoryId }
            }
            guard let resolvedCategoryId else { throw IOSFinanceRepositoryError.categoryNotFound }
            guard let category = snapshot.categories.first(where: { $0.id == resolvedCategoryId }) else {
                throw IOSFinanceRepositoryError.categoryNotFound
            }
            guard !category.deleted else { throw IOSFinanceRepositoryError.categoryUnavailable }
            guard category.typeName == "EXPENSE" else { throw IOSFinanceRepositoryError.categoryTypeMismatch }
        case "ADJUSTMENT":
            guard linkedTransactionId == nil else { throw IOSFinanceRepositoryError.invalidTransactionType }
            guard feeMinor == 0 else {
                throw IOSFinanceRepositoryError.transactionRejected("adjustment_fee_unsupported")
            }
            resolvedCategoryId = nil
        default:
            throw IOSFinanceRepositoryError.unsupportedTransactionType
        }
        let feeCategoryId = feeMinor > 0 ? rules.feesCategoryId() : nil
        if let feeCategoryId {
            guard let feeCategory = snapshot.categories.first(where: { $0.id == feeCategoryId }) else {
                throw IOSFinanceRepositoryError.categoryNotFound
            }
            guard !feeCategory.deleted else {
                throw IOSFinanceRepositoryError.categoryUnavailable
            }
            guard feeCategory.typeName == "EXPENSE" else {
                throw IOSFinanceRepositoryError.categoryTypeMismatch
            }
        }

        let cleanedNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let milliseconds = Int64((occurredAt.timeIntervalSince1970 * 1_000).rounded(.down))
        return try await database.insertTransaction(
            typeName: typeName,
            amountMinor: amountMinor,
            feeMinor: feeMinor,
            currencyCode: workspace.currencyCode,
            walletId: walletId,
            categoryId: resolvedCategoryId,
            feeCategoryId: feeCategoryId,
            incomeSourceId: incomeSourceId,
            linkedTransactionId: linkedTransactionId,
            transactionId: transactionId,
            note: cleanedNote,
            occurredAtMillis: milliseconds
        )
    }

    /// Records one transfer row. The database revalidates both wallets while holding a write
    /// transaction, then stores the source debit, destination credit, and any fee atomically.
    @discardableResult
    public func recordTransfer(
        amountMinor: Int64,
        feeMinor: Int64 = 0,
        sourceWalletId: String,
        destinationWalletId: String,
        transactionId: String? = nil,
        note: String,
        occurredAt: Date = Date()
    ) async throws -> String {
        guard rules.isSupportedAmountMinor(amountMinor), rules.isSupportedAmountMinor(feeMinor) else {
            throw IOSFinanceRepositoryError.amountOutsideSupportedRange
        }
        if let validationError = rules.transactionValidationError(
            typeName: "TRANSFER",
            amountMinor: amountMinor,
            feeMinor: feeMinor
        ) {
            throw IOSFinanceRepositoryError.transactionRejected(validationError)
        }
        let snapshot = try await database.readFinanceSnapshot()
        guard let workspace = snapshot.workspace else { throw IOSFinanceRepositoryError.noWorkspace }
        let feeCategoryId = feeMinor > 0 ? rules.feesCategoryId() : nil
        let cleanedNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let milliseconds = Int64((occurredAt.timeIntervalSince1970 * 1_000).rounded(.down))
        return try await database.insertTransaction(
            typeName: "TRANSFER",
            amountMinor: amountMinor,
            feeMinor: feeMinor,
            currencyCode: workspace.currencyCode,
            walletId: sourceWalletId,
            toWalletId: destinationWalletId,
            categoryId: nil,
            feeCategoryId: feeCategoryId,
            transactionId: transactionId,
            note: cleanedNote,
            occurredAtMillis: milliseconds
        )
    }

    public func deleteTransaction(id: String) async throws {
        try await database.setTransactionDeleted(id: id, deleted: true)
    }

    public func restoreTransaction(id: String) async throws {
        try await database.setTransactionDeleted(id: id, deleted: false)
    }

    private func validateCountryAndCurrency(countryCode: String, currencyCode: String) throws {
        let normalizedCountry = countryCode.uppercased()
        let normalizedCurrency = currencyCode.uppercased()
        guard normalizedCountry.count == 2,
              normalizedCountry.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }),
              normalizedCurrency.count == 3,
              normalizedCurrency.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }),
              rules.isSupportedCurrencyCode(normalizedCurrency) else {
            throw IOSFinanceRepositoryError.invalidCurrency
        }
    }

}
