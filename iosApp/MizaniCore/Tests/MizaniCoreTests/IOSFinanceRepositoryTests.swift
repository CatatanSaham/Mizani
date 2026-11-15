import Foundation
import XCTest
@testable import MizaniCore

final class IOSFinanceRepositoryTests: XCTestCase {
    func testInvestmentValuationEpochDayUsesLocalJanuaryFirstInAllTimeZones() throws {
        let targetComponents = DateComponents(year: 2026, month: 11, day: 15, hour: 12)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let epochComponents = DateComponents(year: 1970, month: 1, day: 1)
        let epochStart = try XCTUnwrap(utcCalendar.date(from: epochComponents))
        let utcTarget = try XCTUnwrap(utcCalendar.date(from: targetComponents))
        let expectedDay = Int64(utcCalendar.dateComponents(
            [.day],
            from: utcCalendar.startOfDay(for: epochStart),
            to: utcCalendar.startOfDay(for: utcTarget)
        ).day ?? -1)

        for secondsFromGMT in [-8 * 60 * 60, 3 * 60 * 60] {
            let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: secondsFromGMT))
            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = timeZone
            let localTarget = try XCTUnwrap(localCalendar.date(from: targetComponents))
            XCTAssertEqual(
                IOSFinanceRepository.investmentLocalEpochDay(localTarget, timeZone: timeZone),
                expectedDay
            )
        }
    }

    func testWalletAndActivityWritesPersistAndUseTheInjectedRules() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryTests", keychain: MemoryKeychainValueStore()),
            rules: TestFinanceRules()
        )

        let workspaceId = try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        XCTAssertFalse(workspaceId.isEmpty)

        let initial = try await repository.snapshot()
        XCTAssertEqual(initial.workspace?.currencyCode, "UGX")
        XCTAssertEqual(initial.activeWallets.count, 1)
        XCTAssertEqual(initial.categories.count, TestFinanceRules.categories.count)
        XCTAssertEqual(initial.totalBalanceMinor, 1_000)
        guard let wallet = initial.activeWallets.first else { return XCTFail("Expected initial wallet") }

        _ = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 100,
            feeMinor: 5,
            walletId: wallet.id,
            categoryId: "expense-category",
            note: "Market"
        )
        _ = try await repository.recordTransaction(
            typeName: "INCOME",
            amountMinor: 50,
            walletId: wallet.id,
            categoryId: "income-category",
            note: "Refunded cash"
        )

        let updated = try await repository.snapshot()
        XCTAssertEqual(updated.activeTransactions.count, 2)
        XCTAssertEqual(updated.activeTransactions.first(where: { $0.note == "Market" })?.feeCategoryId, "fees-category")
        XCTAssertEqual(updated.walletBalancesMinor[wallet.id], 945)
        XCTAssertEqual(updated.totalBalanceMinor, 945)
    }

    func testOverflowingTransactionWriteIsRejectedWithoutChangingEncryptedLedger() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryOverflowWriteTests",
            keychain: MemoryKeychainValueStore()
        )
        let seedDatabase = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        _ = try await seedDatabase.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: Int64.max,
            defaultCategories: rules.defaultCategories()
        )
        try await seedDatabase.close()

        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            rules: rules
        )
        let before = try await repository.snapshot()
        let wallet = try XCTUnwrap(before.activeWallets.first)
        XCTAssertEqual(before.walletBalancesMinor[wallet.id], Int64.max)

        do {
            _ = try await repository.recordTransaction(
                typeName: "INCOME",
                amountMinor: 1,
                walletId: wallet.id,
                categoryId: "income-category",
                note: "Must not overflow the balance"
            )
            XCTFail("Expected the overflowing write to be rejected")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .balanceUnavailable)
        }

        let after = try await repository.snapshot()
        XCTAssertTrue(after.transactions.isEmpty)
        XCTAssertEqual(after.walletBalancesMinor[wallet.id], Int64.max)
    }

    func testDeletingLegacyOverflowRecoversBalanceAndRestoreIsRejectedAtomically() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryOverflowRecoveryTests",
            keychain: MemoryKeychainValueStore()
        )
        let seedDatabase = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        _ = try await seedDatabase.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: Int64.max,
            defaultCategories: rules.defaultCategories()
        )
        let seededSnapshot = try await seedDatabase.readFinanceSnapshot()
        let wallet = try XCTUnwrap(seededSnapshot.wallets.first)
        let transactionId = try await seedDatabase.insertTransaction(
            typeName: "INCOME",
            amountMinor: 1,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: "income-category",
            feeCategoryId: nil,
            note: "Legacy overflow row",
            occurredAtMillis: 1_700_000_000_000
        )
        try await seedDatabase.close()

        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            rules: rules
        )
        let overflowSnapshot = try await repository.snapshot()
        XCTAssertFalse(overflowSnapshot.balancesAvailable)
        XCTAssertNil(overflowSnapshot.totalBalanceMinor)
        XCTAssertEqual(overflowSnapshot.activeTransactions.map(\.id), [transactionId])

        try await repository.deleteTransaction(id: transactionId)
        let recovered = try await repository.snapshot()
        XCTAssertEqual(recovered.walletBalancesMinor[wallet.id], Int64.max)
        XCTAssertEqual(recovered.deletedTransactions.map(\.id), [transactionId])

        do {
            try await repository.restoreTransaction(id: transactionId)
            XCTFail("Expected restore to be rejected while it would reintroduce overflow")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .balanceUnavailable)
        }
        let afterRejectedRestore = try await repository.snapshot()
        XCTAssertTrue(afterRejectedRestore.activeTransactions.isEmpty)
        XCTAssertEqual(afterRejectedRestore.deletedTransactions.map(\.id), [transactionId])
        XCTAssertEqual(afterRejectedRestore.walletBalancesMinor[wallet.id], Int64.max)
    }

    func testRepeatedDeletesCanRecoverLegacyOverflowAcrossMultipleTransactions() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryMultiRowOverflowRecoveryTests",
            keychain: MemoryKeychainValueStore()
        )
        let seedDatabase = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        _ = try await seedDatabase.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: Int64.max - 1,
            defaultCategories: rules.defaultCategories()
        )
        let seededSnapshot = try await seedDatabase.readFinanceSnapshot()
        let wallet = try XCTUnwrap(seededSnapshot.wallets.first)
        var transactionIds: [String] = []
        for index in 0..<3 {
            let transactionId = try await seedDatabase.insertTransaction(
                typeName: "INCOME",
                amountMinor: 1,
                feeMinor: 0,
                currencyCode: "UGX",
                walletId: wallet.id,
                categoryId: "income-category",
                feeCategoryId: nil,
                note: "Legacy overflow row \(index)",
                occurredAtMillis: Int64(1_700_000_000_000 + index)
            )
            transactionIds.append(transactionId)
        }
        try await seedDatabase.close()

        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            rules: rules
        )
        let initial = try await repository.snapshot()
        XCTAssertFalse(initial.balancesAvailable)
        XCTAssertEqual(initial.activeTransactions.count, 3)

        try await repository.deleteTransaction(id: transactionIds[0])
        let stillRecovering = try await repository.snapshot()
        XCTAssertFalse(stillRecovering.balancesAvailable)
        XCTAssertEqual(stillRecovering.activeTransactions.count, 2)
        XCTAssertEqual(stillRecovering.deletedTransactions.map(\.id), [transactionIds[0]])

        try await repository.deleteTransaction(id: transactionIds[1])
        let recovered = try await repository.snapshot()
        XCTAssertTrue(recovered.balancesAvailable)
        XCTAssertEqual(recovered.walletBalancesMinor[wallet.id], Int64.max)
        XCTAssertEqual(recovered.activeTransactions.map(\.id), [transactionIds[2]])
        XCTAssertEqual(Set(recovered.deletedTransactions.map(\.id)), Set(transactionIds.prefix(2)))
    }

    func testEditingLegacyOverflowTransactionCanRepairBalanceAtomically() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryOverflowEditTests",
            keychain: MemoryKeychainValueStore()
        )
        let seedDatabase = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        _ = try await seedDatabase.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: Int64.max,
            defaultCategories: rules.defaultCategories()
        )
        let seededSnapshot = try await seedDatabase.readFinanceSnapshot()
        let wallet = try XCTUnwrap(seededSnapshot.wallets.first)
        let transactionId = try await seedDatabase.insertTransaction(
            typeName: "INCOME",
            amountMinor: 1,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: "income-category",
            feeCategoryId: nil,
            note: "Legacy overflow row",
            occurredAtMillis: 1_700_000_000_000
        )
        try await seedDatabase.close()

        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            rules: rules
        )
        let initial = try await repository.snapshot()
        XCTAssertFalse(initial.balancesAvailable)

        _ = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 1,
            walletId: wallet.id,
            categoryId: "expense-category",
            transactionId: transactionId,
            note: "Corrected legacy row"
        )

        let recovered = try await repository.snapshot()
        XCTAssertTrue(recovered.balancesAvailable)
        XCTAssertEqual(recovered.walletBalancesMinor[wallet.id], Int64.max - 1)
        XCTAssertEqual(recovered.activeTransactions.first?.typeName, "EXPENSE")
        XCTAssertEqual(recovered.activeTransactions.first?.note, "Corrected legacy row")
    }

    func testTransferStoresOneRowCreditsDestinationAndDebitsSourceWithFee() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryTransferTests", keychain: MemoryKeychainValueStore()),
            rules: TestFinanceRules()
        )
        _ = try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initialSnapshot = try await repository.snapshot()
        let cash = try XCTUnwrap(initialSnapshot.activeWallets.first)
        let bankId = try await repository.addWallet(name: "Bank", typeName: "BANK", openingBalanceMinor: 250)

        let transferId = try await repository.recordTransfer(
            amountMinor: 200,
            feeMinor: 10,
            sourceWalletId: cash.id,
            destinationWalletId: bankId,
            note: "Move to bank"
        )

        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.activeTransactions.count, 1)
        let transfer = try XCTUnwrap(snapshot.activeTransactions.first)
        XCTAssertEqual(transfer.id, transferId)
        XCTAssertEqual(transfer.typeName, "TRANSFER")
        XCTAssertEqual(transfer.amountMinor, 200)
        XCTAssertEqual(transfer.feeMinor, 10)
        XCTAssertEqual(transfer.walletId, cash.id)
        XCTAssertEqual(transfer.destinationWalletId, bankId)
        XCTAssertNil(transfer.categoryId)
        XCTAssertEqual(transfer.feeCategoryId, "fees-category")
        XCTAssertEqual(snapshot.walletBalancesMinor[cash.id], 790)
        XCTAssertEqual(snapshot.walletBalancesMinor[bankId], 450)
        XCTAssertEqual(snapshot.totalBalanceMinor, 1_240)

        do {
            _ = try await repository.recordTransfer(
                amountMinor: 50,
                sourceWalletId: cash.id,
                destinationWalletId: cash.id,
                note: "Invalid same-wallet transfer"
            )
            XCTFail("Expected same-wallet transfer rejection")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .invalidTransferDestination)
        }
        do {
            _ = try await repository.recordTransfer(
                amountMinor: 50,
                sourceWalletId: cash.id,
                destinationWalletId: "missing-wallet",
                note: "Invalid destination"
            )
            XCTFail("Expected missing destination rejection")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .walletNotFound)
        }

        let afterRejectedWrites = try await repository.snapshot()
        XCTAssertEqual(afterRejectedWrites.activeTransactions.count, 1)
        XCTAssertEqual(afterRejectedWrites.walletBalancesMinor[cash.id], 790)
        XCTAssertEqual(afterRejectedWrites.walletBalancesMinor[bankId], 450)
    }

    func testTransactionEditPreservesIdentityAndOccurrenceWhileDeleteRestoreRecalculatesBalance() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryLifecycleTests", keychain: MemoryKeychainValueStore()),
            rules: TestFinanceRules()
        )
        _ = try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initialSnapshot = try await repository.snapshot()
        let wallet = try XCTUnwrap(initialSnapshot.activeWallets.first)
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000.125)
        let transactionId = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 100,
            walletId: wallet.id,
            categoryId: "expense-category",
            note: "Original note",
            occurredAt: occurredAt
        )
        let beforeEdit = try await repository.snapshot()
        let original = try XCTUnwrap(beforeEdit.activeTransactions.first)

        let editedId = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 175,
            feeMinor: 4,
            walletId: wallet.id,
            categoryId: "expense-category",
            transactionId: transactionId,
            note: "Updated note",
            occurredAt: occurredAt
        )
        let edited = try await repository.snapshot()
        let transaction = try XCTUnwrap(edited.activeTransactions.first)
        XCTAssertEqual(editedId, transactionId)
        XCTAssertEqual(edited.activeTransactions.count, 1)
        XCTAssertEqual(transaction.id, transactionId)
        XCTAssertEqual(transaction.amountMinor, 175)
        XCTAssertEqual(transaction.feeMinor, 4)
        XCTAssertEqual(transaction.note, "Updated note")
        XCTAssertEqual(transaction.occurredAtMillis, 1_700_000_000_125)
        XCTAssertEqual(transaction.localDateEpochDay, original.localDateEpochDay)
        XCTAssertEqual(edited.walletBalancesMinor[wallet.id], 821)

        try await repository.deleteTransaction(id: transactionId)
        try await repository.deleteTransaction(id: transactionId)
        let deleted = try await repository.snapshot()
        XCTAssertTrue(deleted.activeTransactions.isEmpty)
        XCTAssertEqual(deleted.deletedTransactions.map(\.id), [transactionId])
        XCTAssertEqual(deleted.walletBalancesMinor[wallet.id], 1_000)

        try await repository.restoreTransaction(id: transactionId)
        try await repository.restoreTransaction(id: transactionId)
        let restored = try await repository.snapshot()
        XCTAssertEqual(restored.activeTransactions.map(\.id), [transactionId])
        XCTAssertTrue(restored.deletedTransactions.isEmpty)
        XCTAssertEqual(restored.walletBalancesMinor[wallet.id], 821)

        try await repository.deleteTransaction(id: transactionId)
        do {
            _ = try await repository.recordTransaction(
                typeName: "EXPENSE",
                amountMinor: 10,
                walletId: wallet.id,
                categoryId: "expense-category",
                transactionId: transactionId,
                note: "Cannot edit a deleted transaction"
            )
            XCTFail("Expected a deleted transaction to reject edits")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .transactionUnavailable)
        }
    }

    func testEditingTransferReusesItsRowAndRecalculatesBothWalletBalances() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryTransferEditTests", keychain: MemoryKeychainValueStore()),
            rules: TestFinanceRules()
        )
        _ = try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initialSnapshot = try await repository.snapshot()
        let cash = try XCTUnwrap(initialSnapshot.activeWallets.first)
        let bankId = try await repository.addWallet(name: "Bank", typeName: "BANK", openingBalanceMinor: 250)
        let transferId = try await repository.recordTransfer(
            amountMinor: 200,
            feeMinor: 10,
            sourceWalletId: cash.id,
            destinationWalletId: bankId,
            note: "First route"
        )

        let updatedId = try await repository.recordTransfer(
            amountMinor: 150,
            feeMinor: 5,
            sourceWalletId: bankId,
            destinationWalletId: cash.id,
            transactionId: transferId,
            note: "Updated route"
        )
        let snapshot = try await repository.snapshot()
        let transfer = try XCTUnwrap(snapshot.activeTransactions.first)
        XCTAssertEqual(updatedId, transferId)
        XCTAssertEqual(snapshot.activeTransactions.count, 1)
        XCTAssertEqual(transfer.id, transferId)
        XCTAssertEqual(transfer.amountMinor, 150)
        XCTAssertEqual(transfer.feeMinor, 5)
        XCTAssertEqual(transfer.walletId, bankId)
        XCTAssertEqual(transfer.destinationWalletId, cash.id)
        XCTAssertEqual(transfer.note, "Updated route")
        XCTAssertEqual(snapshot.walletBalancesMinor[cash.id], 1_150)
        XCTAssertEqual(snapshot.walletBalancesMinor[bankId], 95)
        XCTAssertEqual(snapshot.totalBalanceMinor, 1_245)
    }

    func testRefundLinksRemainStableAcrossDeleteAndRestoreAndBlockExpenseTypeChange() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryRefundLifecycleTests", keychain: MemoryKeychainValueStore()),
            rules: TestFinanceRules()
        )
        _ = try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initialSnapshot = try await repository.snapshot()
        let wallet = try XCTUnwrap(initialSnapshot.activeWallets.first)
        let expenseId = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 200,
            walletId: wallet.id,
            categoryId: "expense-category",
            note: "Market"
        )
        let refundId = try await repository.recordTransaction(
            typeName: "REFUND",
            amountMinor: 225,
            walletId: wallet.id,
            linkedTransactionId: expenseId,
            note: "Refund exceeds original expense"
        )
        let afterRefund = try await repository.snapshot()
        XCTAssertEqual(afterRefund.walletBalancesMinor[wallet.id], 1_025)

        do {
            _ = try await repository.recordTransaction(
                typeName: "INCOME",
                amountMinor: 200,
                walletId: wallet.id,
                categoryId: "income-category",
                transactionId: expenseId,
                note: "Cannot change an expense with linked refunds"
            )
            XCTFail("Expected linked refunds to keep the expense type stable")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .transactionHasRefunds)
        }
        let afterRejectedTypeChange = try await repository.snapshot()
        XCTAssertEqual(afterRejectedTypeChange.walletBalancesMinor[wallet.id], 1_025)

        try await repository.deleteTransaction(id: expenseId)
        _ = try await repository.recordTransaction(
            typeName: "REFUND",
            amountMinor: 240,
            walletId: wallet.id,
            categoryId: "expense-category",
            linkedTransactionId: expenseId,
            transactionId: refundId,
            note: "Updated while original is in Recently deleted"
        )
        let whileSourceDeleted = try await repository.snapshot()
        XCTAssertEqual(whileSourceDeleted.activeTransactions.map(\.id), [refundId])
        XCTAssertEqual(whileSourceDeleted.activeTransactions.first?.linkedTransactionId, expenseId)
        XCTAssertEqual(whileSourceDeleted.walletBalancesMinor[wallet.id], 1_240)

        try await repository.deleteTransaction(id: refundId)
        let withBothRowsDeleted = try await repository.snapshot()
        XCTAssertTrue(withBothRowsDeleted.activeTransactions.isEmpty)
        XCTAssertEqual(withBothRowsDeleted.walletBalancesMinor[wallet.id], 1_000)

        try await repository.restoreTransaction(id: refundId)
        let refundRestoredFirst = try await repository.snapshot()
        XCTAssertEqual(refundRestoredFirst.activeTransactions.map(\.id), [refundId])
        XCTAssertEqual(refundRestoredFirst.walletBalancesMinor[wallet.id], 1_240)

        try await repository.restoreTransaction(id: expenseId)
        let restored = try await repository.snapshot()
        XCTAssertEqual(restored.walletBalancesMinor[wallet.id], 1_040)

        try await repository.deleteTransaction(id: refundId)
        do {
            _ = try await repository.recordTransaction(
                typeName: "INCOME",
                amountMinor: 200,
                walletId: wallet.id,
                categoryId: "income-category",
                transactionId: expenseId,
                note: "A deleted refund still refers to this expense"
            )
            XCTFail("Expected a deleted linked refund to preserve the expense type")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .transactionHasRefunds)
        }
    }

    func testRefundLinkAndSignedAdjustmentUseTheSharedLedgerSemantics() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryRefundTests", keychain: MemoryKeychainValueStore()),
            rules: TestFinanceRules()
        )
        _ = try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initialSnapshot = try await repository.snapshot()
        let wallet = try XCTUnwrap(initialSnapshot.activeWallets.first)
        _ = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 200,
            walletId: wallet.id,
            categoryId: "expense-category",
            note: "Market"
        )
        let afterExpense = try await repository.snapshot()
        let expense = try XCTUnwrap(afterExpense.activeTransactions.first)

        _ = try await repository.recordTransaction(
            typeName: "REFUND",
            amountMinor: 75,
            walletId: wallet.id,
            linkedTransactionId: expense.id,
            note: "Partial refund"
        )
        _ = try await repository.recordTransaction(
            typeName: "REFUND",
            amountMinor: 10,
            walletId: wallet.id,
            categoryId: "expense-category",
            note: "Unlinked refund"
        )
        _ = try await repository.recordTransaction(
            typeName: "ADJUSTMENT",
            amountMinor: -25,
            walletId: wallet.id,
            note: "Corrected count"
        )

        let snapshot = try await repository.snapshot()
        let refund = try XCTUnwrap(snapshot.activeTransactions.first(where: { $0.typeName == "REFUND" }))
        let adjustment = try XCTUnwrap(snapshot.activeTransactions.first(where: { $0.typeName == "ADJUSTMENT" }))
        XCTAssertEqual(refund.linkedTransactionId, expense.id)
        XCTAssertEqual(refund.categoryId, "expense-category")
        XCTAssertEqual(adjustment.amountMinor, -25)
        XCTAssertNil(adjustment.categoryId)
        XCTAssertNil(adjustment.linkedTransactionId)
        XCTAssertEqual(snapshot.walletBalancesMinor[wallet.id], 860)

        do {
            _ = try await repository.recordTransaction(
                typeName: "ADJUSTMENT",
                amountMinor: 5,
                feeMinor: 1,
                walletId: wallet.id,
                note: "Reject ignored fee"
            )
            XCTFail("Expected adjustment fees to be rejected")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .transactionRejected("adjustment_fee_unsupported"))
        }

        do {
            _ = try await repository.recordTransaction(
                typeName: "REFUND",
                amountMinor: 10,
                walletId: wallet.id,
                categoryId: "expense-category",
                linkedTransactionId: "missing-expense",
                note: "Reject missing source"
            )
            XCTFail("Expected a refund with a missing linked expense to be rejected")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .refundTargetUnavailable)
        }
        let afterRejectedWrite = try await repository.snapshot()
        XCTAssertEqual(afterRejectedWrite.activeTransactions.count, 4)
        XCTAssertEqual(afterRejectedWrite.walletBalancesMinor[wallet.id], 860)
    }

    func testRejectedTransactionDoesNotWriteLedgerRows() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryValidationTests", keychain: MemoryKeychainValueStore()),
            rules: TestFinanceRules()
        )
        _ = try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 0
        )
        guard let wallet = try await repository.snapshot().activeWallets.first else {
            return XCTFail("Expected initial wallet")
        }

        do {
            _ = try await repository.recordTransaction(
                typeName: "EXPENSE",
                amountMinor: 0,
                walletId: wallet.id,
                categoryId: "expense-category",
                note: "Rejected"
            )
            XCTFail("Expected the injected validator to reject a zero amount")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .transactionRejected("amount_invalid"))
        }

        do {
            _ = try await repository.recordTransaction(
                typeName: "EXPENSE",
                amountMinor: 10,
                walletId: wallet.id,
                categoryId: "income-category",
                note: "Wrong category type"
            )
            XCTFail("Expected the repository to reject an income category on an expense")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .categoryTypeMismatch)
        }

        do {
            _ = try await repository.recordTransaction(
                typeName: "EXPENSE",
                amountMinor: 10,
                walletId: wallet.id,
                categoryId: "unknown-category",
                note: "Unknown category"
            )
            XCTFail("Expected the repository to reject an unknown category")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .categoryNotFound)
        }

        let afterRejectedWrite = try await repository.snapshot()
        XCTAssertTrue(afterRejectedWrite.transactions.isEmpty)
    }

    func testVersionOneMigrationPreservesLedgerAndAddsSharedCategories() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(service: "IOSFinanceRepositoryMigrationTests", keychain: MemoryKeychainValueStore())
        let versionOne = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        _ = try await versionOne.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 500,
            defaultCategories: rules.defaultCategories()
        )
        let wallet = try await versionOne.readFinanceSnapshot().wallets[0]
        let bankId = try await versionOne.insertWallet(
            name: "Bank",
            typeName: "BANK",
            openingBalanceMinor: 100,
            currencyCode: "UGX"
        )
        let expenseId = try await versionOne.insertTransaction(
            typeName: "EXPENSE",
            amountMinor: 75,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: "expense-category",
            feeCategoryId: nil,
            note: "Legacy expense",
            occurredAtMillis: 1_700_000_000_000
        )
        _ = try await versionOne.insertTransaction(
            typeName: "EXPENSE",
            amountMinor: 25,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: nil,
            feeCategoryId: nil,
            note: "Legacy uncategorized expense",
            occurredAtMillis: 1_700_000_001_000
        )
        _ = try await versionOne.insertTransaction(
            typeName: "REFUND",
            amountMinor: 10,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: "expense-category",
            feeCategoryId: nil,
            linkedTransactionId: expenseId,
            note: "Legacy refund",
            occurredAtMillis: 1_700_000_002_000
        )
        _ = try await versionOne.insertTransaction(
            typeName: "TRANSFER",
            amountMinor: 50,
            feeMinor: 2,
            currencyCode: "UGX",
            walletId: wallet.id,
            toWalletId: bankId,
            categoryId: nil,
            feeCategoryId: "fees-category",
            note: "Legacy transfer",
            occurredAtMillis: 1_700_000_003_000
        )
        _ = try await versionOne.insertTransaction(
            typeName: "ADJUSTMENT",
            amountMinor: -5,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: nil,
            feeCategoryId: nil,
            note: "Legacy adjustment",
            occurredAtMillis: 1_700_000_004_000
        )
        try await versionOne.executeForTesting(
            "ALTER TABLE transactions DROP COLUMN income_source_id; " +
                "DROP TABLE commitment_payments; DROP TABLE commitments; DROP TABLE investment_holdings; " +
                "DROP TABLE goal_contributions; DROP TABLE goals; " +
                "DROP TABLE income_sources; DROP TABLE categories; PRAGMA user_version = 1;"
        )
        try await versionOne.close()

        let migrated = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        let snapshot = try await migrated.readFinanceSnapshot()
        XCTAssertEqual(snapshot.transactions.count, 5)
        let categorizedTransaction = snapshot.transactions.first(where: { $0.note == "Legacy expense" })
        XCTAssertEqual(categorizedTransaction?.categoryId, "expense-category")
        let uncategorizedTransaction = snapshot.transactions.first(where: { $0.note == "Legacy uncategorized expense" })
        XCTAssertNil(uncategorizedTransaction?.categoryId)
        let migratedRefund = snapshot.transactions.first(where: { $0.note == "Legacy refund" })
        XCTAssertEqual(migratedRefund?.linkedTransactionId, expenseId)
        XCTAssertEqual(migratedRefund?.categoryId, "expense-category")
        let migratedTransfer = snapshot.transactions.first(where: { $0.note == "Legacy transfer" })
        XCTAssertEqual(migratedTransfer?.destinationWalletId, bankId)
        XCTAssertEqual(migratedTransfer?.feeMinor, 2)
        let migratedAdjustment = snapshot.transactions.first(where: { $0.note == "Legacy adjustment" })
        XCTAssertEqual(migratedAdjustment?.amountMinor, -5)
        XCTAssertEqual(rules.walletBalanceMinor(
            walletId: wallet.id,
            openingBalanceMinor: wallet.openingBalanceMinor,
            transactions: snapshot.transactions
        ), "353")
        let bank = try XCTUnwrap(snapshot.wallets.first(where: { $0.id == bankId }))
        XCTAssertEqual(rules.walletBalanceMinor(
            walletId: bank.id,
            openingBalanceMinor: bank.openingBalanceMinor,
            transactions: snapshot.transactions
        ), "150")
        XCTAssertEqual(Set(snapshot.categories.map(\.id)), Set(rules.defaultCategories().map(\.id)))
        let migratedSchemaVersion = try await migrated.textForTesting("PRAGMA user_version;")
        XCTAssertEqual(migratedSchemaVersion, "6")
        try await migrated.close()
    }

    func testVersionTwoMigrationAddsIncomeSourcesAndPreservesTransactionSourceId() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryIncomeSourceMigrationTests",
            keychain: MemoryKeychainValueStore()
        )
        let versionTwo = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        _ = try await versionTwo.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 500,
            defaultCategories: rules.defaultCategories()
        )
        let wallet = try await versionTwo.readFinanceSnapshot().wallets[0]
        let incomeCategoryId = try XCTUnwrap(rules.defaultCategories().first(where: { $0.typeName == "INCOME" })?.id)
        _ = try await versionTwo.insertTransaction(
            typeName: "INCOME",
            amountMinor: 250,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: incomeCategoryId,
            feeCategoryId: nil,
            transactionId: "migration-income",
            note: "Legacy income",
            occurredAtMillis: 1_700_000_000_000
        )
        try await versionTwo.executeForTesting(
            "UPDATE transactions SET income_source_id = 'legacy-source' WHERE id = 'migration-income'; " +
                "DROP TABLE commitment_payments; DROP TABLE commitments; DROP TABLE investment_holdings; " +
                "DROP TABLE goal_contributions; DROP TABLE goals; " +
                "DROP TABLE income_sources; PRAGMA user_version = 2;"
        )
        try await versionTwo.close()

        let migrated = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        let snapshot = try await migrated.readFinanceSnapshot()
        XCTAssertEqual(snapshot.incomeSources, [])
        XCTAssertEqual(snapshot.transactions.first(where: { $0.id == "migration-income" })?.incomeSourceId, "legacy-source")
        let migratedSchemaVersion = try await migrated.textForTesting("PRAGMA user_version;")
        XCTAssertEqual(migratedSchemaVersion, "6")
        try await migrated.close()

        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            rules: rules
        )
        let migratedRepositorySnapshot = try await repository.snapshot()
        let migratedWallet = try XCTUnwrap(migratedRepositorySnapshot.wallets.first)
        let migratedIncomeCategoryId = try XCTUnwrap(
            migratedRepositorySnapshot.categories.first(where: { $0.typeName == "INCOME" })?.id
        )
        _ = try await repository.recordTransaction(
            typeName: "INCOME",
            amountMinor: 275,
            walletId: migratedWallet.id,
            categoryId: migratedIncomeCategoryId,
            incomeSourceId: "legacy-source",
            transactionId: "migration-income",
            note: "Edited legacy income"
        )
        let editedLegacySnapshot = try await repository.snapshot()
        let editedLegacyIncome = editedLegacySnapshot.transactions.first(where: { $0.id == "migration-income" })
        XCTAssertEqual(editedLegacyIncome?.incomeSourceId, "legacy-source")
        XCTAssertEqual(editedLegacyIncome?.note, "Edited legacy income")
    }

    func testVersionThreeMigrationAddsGoalTablesWithoutChangingExistingRecords() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryGoalMigrationTests",
            keychain: MemoryKeychainValueStore()
        )
        let versionThree = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories(),
            incomeSourceKindValidator: { kindName in
                rules.incomeSourceKinds().contains(where: { $0.name == kindName })
            }
        )
        _ = try await versionThree.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 900,
            defaultCategories: rules.defaultCategories()
        )
        let seedSnapshot = try await versionThree.readFinanceSnapshot()
        let wallet = try XCTUnwrap(seedSnapshot.activeWallets.first)
        let sourceId = try await versionThree.insertIncomeSource(name: "Market", kindName: "GIG")
        let incomeId = try await versionThree.insertTransaction(
            typeName: "INCOME",
            amountMinor: 125,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: "income-category",
            feeCategoryId: nil,
            incomeSourceId: sourceId,
            transactionId: "goal-migration-income",
            note: "Keep this income",
            occurredAtMillis: 1_700_100_000_000
        )
        try await versionThree.executeForTesting(
            "DROP TABLE commitment_payments; DROP TABLE commitments; DROP TABLE investment_holdings; " +
                "DROP TABLE goal_contributions; DROP TABLE goals; PRAGMA user_version = 3;"
        )
        try await versionThree.close()

        let migrated = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        let snapshot = try await migrated.readFinanceSnapshot()
        XCTAssertEqual(snapshot.transactions.count, 1)
        XCTAssertEqual(snapshot.transactions.first?.id, incomeId)
        XCTAssertEqual(snapshot.transactions.first?.incomeSourceId, sourceId)
        XCTAssertEqual(snapshot.incomeSources.first?.id, sourceId)
        XCTAssertEqual(snapshot.goals, [])
        XCTAssertEqual(snapshot.goalContributions, [])
        let migratedVersion = try await migrated.textForTesting("PRAGMA user_version;")
        XCTAssertEqual(migratedVersion, "6")
        try await migrated.close()
    }

    func testVersionFourMigrationAddsInvestmentTableAndPreservesFinancialRecords() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryInvestmentMigrationTests",
            keychain: MemoryKeychainValueStore()
        )
        let versionFour = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        let workspaceId = try await versionFour.insertInitialWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000,
            defaultCategories: rules.defaultCategories()
        )
        let versionFourSnapshot = try await versionFour.readFinanceSnapshot()
        let wallet = try XCTUnwrap(versionFourSnapshot.activeWallets.first)
        let goalId = try await versionFour.saveGoal(
            id: nil,
            name: "Emergency",
            targetMinor: 5_000,
            targetEpochDay: nil,
            linkedWalletId: nil,
            priority: 2,
            note: "Keep this goal",
            icon: "savings"
        )
        try await versionFour.insertGoalContribution(
            goalId: goalId,
            amountMinor: 250,
            allocatedMinorAfterContribution: 250,
            fromWalletId: nil,
            localDateEpochDay: 20_000,
            note: "Keep this contribution"
        )
        let transactionId = try await versionFour.insertTransaction(
            typeName: "EXPENSE",
            amountMinor: 75,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: wallet.id,
            categoryId: "expense-category",
            feeCategoryId: nil,
            transactionId: "migration-transaction-v4",
            note: "Keep this transaction",
            occurredAtMillis: 1_700_000_000_000
        )
        XCTAssertEqual(transactionId, "migration-transaction-v4")
        try await versionFour.executeForTesting(
            "DROP TABLE commitment_payments; DROP TABLE commitments; DROP TABLE investment_holdings; " +
                "PRAGMA user_version = 4;"
        )
        try await versionFour.close()

        let migrated = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        let snapshot = try await migrated.readFinanceSnapshot()
        XCTAssertEqual(snapshot.workspace?.id, workspaceId)
        XCTAssertEqual(snapshot.goals.map(\.id), [goalId])
        XCTAssertEqual(snapshot.goalContributions.map(\.goalId), [goalId])
        XCTAssertEqual(snapshot.goalContributions.first?.amountMinor, 250)
        XCTAssertEqual(snapshot.transactions.map(\.id), [transactionId])
        XCTAssertEqual(snapshot.investments, [])
        let migratedVersion = try await migrated.textForTesting("PRAGMA user_version;")
        let investmentCount = try await migrated.textForTesting("SELECT COUNT(*) FROM investment_holdings;")
        XCTAssertEqual(migratedVersion, "6")
        XCTAssertEqual(investmentCount, "0")
        try await migrated.close()
    }

    func testVersionFiveMigrationAddsCommitmentTablesWithoutChangingExistingRecords() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryCommitmentMigrationTests",
            keychain: MemoryKeychainValueStore()
        )
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            rules: rules
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        _ = try await repository.saveInvestmentHolding(
            name: "Unit trust",
            provider: "Fund manager",
            assetTypeName: "FUNDS",
            costBasisMinor: 500,
            currentValueMinor: 550
        )
        let before = try await repository.snapshot()
        let walletId = try XCTUnwrap(before.activeWallets.first?.id)
        let transactionId = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 75,
            walletId: walletId,
            categoryId: "expense-category",
            note: "Keep this transaction"
        )
        try await repository.close()

        let versionFive = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        try await versionFive.executeForTesting(
            "DROP TABLE commitment_payments; DROP TABLE commitments; PRAGMA user_version = 5;"
        )
        try await versionFive.close()

        let migrated = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        let snapshot = try await migrated.readFinanceSnapshot()
        XCTAssertEqual(snapshot.investments.map(\.name), ["Unit trust"])
        XCTAssertEqual(snapshot.transactions.map(\.id), [transactionId])
        XCTAssertEqual(snapshot.workspace?.currencyCode, "UGX")
        let migratedVersion = try await migrated.textForTesting("PRAGMA user_version;")
        let commitmentCount = try await migrated.textForTesting("SELECT COUNT(*) FROM commitments;")
        let paymentCount = try await migrated.textForTesting("SELECT COUNT(*) FROM commitment_payments;")
        XCTAssertEqual(migratedVersion, "6")
        XCTAssertEqual(commitmentCount, "0")
        XCTAssertEqual(paymentCount, "0")
        try await migrated.close()
    }

    func testCommitmentPaymentLinksAnExpenseOnceAndTracksActiveRefunds() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryCommitmentTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: rules
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initial = try await repository.snapshot()
        let walletId = try XCTUnwrap(initial.activeWallets.first?.id)
        let expenseId = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 400,
            walletId: walletId,
            categoryId: "expense-category",
            note: "Rent payment"
        )
        let commitmentId = try await repository.saveCommitment(
            draft: IOSCommitmentDraft(
                name: "Rent",
                targetMinor: 500,
                currencyCode: "UGX",
                targetWorkspaceMinor: 500,
                exchangeRate: nil,
                exchangeRateDate: nil,
                dueEpochDay: 20_000,
                categoryId: "expense-category",
                reminderDaysBefore: 0
            )
        )
        let otherCommitmentId = try await repository.saveCommitment(
            draft: IOSCommitmentDraft(
                name: "School fees",
                targetMinor: 500,
                currencyCode: "UGX",
                targetWorkspaceMinor: 500,
                exchangeRate: nil,
                exchangeRateDate: nil,
                dueEpochDay: 20_100,
                categoryId: nil,
                reminderDaysBefore: 0
            )
        )
        let refundId = try await repository.recordTransaction(
            typeName: "REFUND",
            amountMinor: 100,
            walletId: walletId,
            categoryId: "expense-category",
            linkedTransactionId: expenseId,
            note: "Partial refund"
        )

        _ = try await repository.linkExpenseToCommitment(commitmentId: commitmentId, transactionId: expenseId)
        do {
            _ = try await repository.linkExpenseToCommitment(commitmentId: otherCommitmentId, transactionId: expenseId)
            XCTFail("An expense must not pay two commitments")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .commitmentPaymentUnavailable)
        }
        var snapshot = try await repository.snapshot()
        var progress = try XCTUnwrap(snapshot.commitmentProgress(using: rules).first(where: { $0.id == commitmentId }))
        XCTAssertEqual(progress.paidMinor, Int64(300))
        XCTAssertEqual(progress.remainingMinor, Int64(200))
        XCTAssertEqual(snapshot.transactions.count, 2)
        XCTAssertEqual(snapshot.commitmentPayments.count, 1)

        do {
            _ = try await repository.saveCommitment(
                id: commitmentId,
                draft: IOSCommitmentDraft(
                    name: "Rent",
                    targetMinor: 299,
                    currencyCode: "UGX",
                    targetWorkspaceMinor: 299,
                    exchangeRate: nil,
                    exchangeRateDate: nil,
                    dueEpochDay: 20_000,
                    categoryId: "expense-category",
                    reminderDaysBefore: 0
                )
            )
            XCTFail("The target cannot be lowered below payments already linked")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .commitmentDraftRejected("target_below_payments"))
        }

        try await repository.deleteTransaction(id: refundId)
        snapshot = try await repository.snapshot()
        progress = try XCTUnwrap(snapshot.commitmentProgress(using: rules).first(where: { $0.id == commitmentId }))
        XCTAssertEqual(progress.paidMinor, Int64(400))

        let secondExpenseId = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 20,
            walletId: walletId,
            categoryId: "expense-category",
            note: "School fee"
        )
        _ = try await repository.linkExpenseToCommitment(
            commitmentId: otherCommitmentId,
            transactionId: secondExpenseId
        )
        do {
            _ = try await repository.recordTransaction(
                typeName: "INCOME",
                amountMinor: 20,
                walletId: walletId,
                categoryId: "income-category",
                transactionId: secondExpenseId,
                note: "Invalid linked edit"
            )
            XCTFail("A linked commitment payment must remain an expense")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .commitmentPaymentUnavailable)
        }

        snapshot = try await repository.snapshot()
        let secondLinkedPayment = try XCTUnwrap(
            snapshot.commitmentPayments.first(where: { $0.transactionId == secondExpenseId })
        )
        try await repository.unlinkCommitmentPayment(id: secondLinkedPayment.id)
        snapshot = try await repository.snapshot()
        let linkedPayment = try XCTUnwrap(
            snapshot.commitmentPayments.first(where: { $0.transactionId == expenseId })
        )
        try await repository.unlinkCommitmentPayment(id: linkedPayment.id)
        snapshot = try await repository.snapshot()
        XCTAssertFalse(snapshot.commitmentPayments.contains(where: { $0.transactionId == expenseId }))
        XCTAssertTrue(snapshot.activeTransactions.contains(where: { $0.id == expenseId }))
        _ = try await repository.linkExpenseToCommitment(commitmentId: otherCommitmentId, transactionId: expenseId)
        try await repository.deleteTransaction(id: expenseId)
        snapshot = try await repository.snapshot()
        XCTAssertFalse(snapshot.commitmentPayments.contains(where: { $0.transactionId == expenseId }))
        XCTAssertEqual(snapshot.transactions.count, 3)
        try await repository.close()
    }

    func testInvestmentRepositoryValidatesPersistsArchivesAndKeepsLedgerSeparate() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryInvestmentTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: TestFinanceRules()
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let before = try await repository.snapshot()
        let walletId = try XCTUnwrap(before.activeWallets.first?.id)
        let fundId = try await repository.saveInvestmentHolding(
            name: "Unit trust",
            provider: "Fund manager",
            assetTypeName: "FUNDS",
            costBasisMinor: 500,
            currentValueMinor: 650,
            note: "Quarterly value"
        )
        let homeId = try await repository.saveInvestmentHolding(
            name: "Rental home",
            provider: "Direct",
            assetTypeName: "REAL_ESTATE",
            costBasisMinor: 2_000,
            currentValueMinor: 1_800
        )
        var snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.walletBalancesMinor[walletId], 1_000)
        XCTAssertEqual(snapshot.activeTransactions, [])
        XCTAssertEqual(snapshot.investmentSummary?.holdingCount, 2)
        XCTAssertEqual(snapshot.investmentSummary?.costBasisMinor, 2_500)
        XCTAssertEqual(snapshot.investmentSummary?.currentValueMinor, 2_450)
        XCTAssertEqual(snapshot.investmentSummary?.gainLossMinor, -50)

        try await repository.setInvestmentHoldingArchived(id: homeId, archived: true)
        snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.activeInvestments.map(\.id), [fundId])
        XCTAssertEqual(snapshot.archivedInvestments.map(\.id), [homeId])
        XCTAssertEqual(snapshot.investmentSummary?.holdingCount, 1)
        XCTAssertEqual(snapshot.investmentSummary?.gainLossMinor, 150)

        _ = try await repository.saveInvestmentHolding(
            id: fundId,
            name: "Updated unit trust",
            provider: "Fund manager",
            assetTypeName: "FUNDS",
            costBasisMinor: 550,
            currentValueMinor: 700,
            note: "Updated value"
        )
        try await repository.setInvestmentHoldingArchived(id: homeId, archived: false)
        snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.investments.first(where: { $0.id == fundId })?.costBasisMinor, 550)
        XCTAssertEqual(snapshot.investments.first(where: { $0.id == fundId })?.currentValueMinor, 700)
        XCTAssertEqual(snapshot.investmentSummary?.holdingCount, 2)

        do {
            _ = try await repository.saveInvestmentHolding(
                name: "Future valuation",
                provider: "Provider",
                assetTypeName: "FUNDS",
                costBasisMinor: 100,
                currentValueMinor: 100,
                valuationDate: Date().addingTimeInterval(86_400)
            )
            XCTFail("A future valuation date should be rejected by the shared rule")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .investmentDraftRejected("valuation_date_invalid"))
        }
        try await repository.deleteInvestmentHolding(id: homeId)
        snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.investments.first(where: { $0.id == homeId })?.deleted, true)
        XCTAssertEqual(snapshot.investmentSummary?.holdingCount, 1)
        XCTAssertEqual(snapshot.walletBalancesMinor[walletId], 1_000)
    }

    func testGoalContributionsPreserveAllocationAndCommitLinkedTransfersAtomically() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryGoalTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: TestFinanceRules()
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 500
        )
        let initialSnapshot = try await repository.snapshot()
        let cash = try XCTUnwrap(initialSnapshot.activeWallets.first)
        let savingsWalletId = try await repository.addWallet(
            name: "Savings",
            typeName: "SAVINGS",
            openingBalanceMinor: 0
        )
        let goalId = try await repository.saveGoal(
            name: "Emergency fund",
            targetMinor: 300,
            linkedWalletId: savingsWalletId,
            priority: 1,
            note: "Keep an emergency reserve"
        )

        try await repository.contributeToGoal(goalId: goalId, amountMinor: 200, fromWalletId: cash.id)
        var snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.goals.first(where: { $0.id == goalId })?.allocatedMinor, 200)
        XCTAssertEqual(snapshot.goalContributions.count, 1)
        XCTAssertEqual(snapshot.activeTransactions.filter { $0.typeName == "TRANSFER" }.count, 1)
        XCTAssertEqual(snapshot.walletBalancesMinor[cash.id], 300)
        XCTAssertEqual(snapshot.walletBalancesMinor[savingsWalletId], 200)

        _ = try await repository.saveGoal(
            id: goalId,
            name: "Emergency reserve",
            targetMinor: 250,
            linkedWalletId: savingsWalletId,
            priority: 1,
            note: "Updated without resetting progress"
        )
        try await repository.contributeToGoal(goalId: goalId, amountMinor: 50)
        snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.goals.first(where: { $0.id == goalId })?.allocatedMinor, 250)
        XCTAssertEqual(snapshot.goalContributions.count, 2)
        XCTAssertEqual(snapshot.activeTransactions.filter { $0.typeName == "TRANSFER" }.count, 1)

        try await repository.setGoalArchived(id: goalId, archived: true)
        do {
            try await repository.contributeToGoal(goalId: goalId, amountMinor: 10)
            XCTFail("Expected archived goal to reject contributions")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .goalUnavailable)
        }
        let archivedSnapshot = try await repository.snapshot()
        XCTAssertEqual(archivedSnapshot.archivedGoals.first?.id, goalId)
        try await repository.setGoalArchived(id: goalId, archived: false)
        let restoredSnapshot = try await repository.snapshot()
        XCTAssertEqual(restoredSnapshot.activeGoals.first?.id, goalId)
    }

    func testGoalContributionBalanceOverflowRollsBackTransferAndProgress() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rules = TestFinanceRules()
        let provider = KeychainDatabaseKeyProvider(
            service: "IOSFinanceRepositoryGoalRollbackTests",
            keychain: MemoryKeychainValueStore()
        )
        let legacyDatabase = try EncryptedFinanceDatabase(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            defaultCategories: rules.defaultCategories()
        )
        _ = try await legacyDatabase.insertInitialWorkspace(
            name: "Legacy workspace",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Legacy wallet",
            walletTypeName: "CASH",
            openingBalanceMinor: Int64.min,
            defaultCategories: rules.defaultCategories()
        )
        let legacySnapshot = try await legacyDatabase.readFinanceSnapshot()
        let sourceWallet = try XCTUnwrap(legacySnapshot.activeWallets.first)
        try await legacyDatabase.close()

        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: provider,
            rules: rules
        )
        let savingsWalletId = try await repository.addWallet(
            name: "Savings",
            typeName: "SAVINGS",
            openingBalanceMinor: 0
        )
        let goalId = try await repository.saveGoal(
            name: "Overflow rollback",
            targetMinor: 100,
            linkedWalletId: savingsWalletId
        )

        do {
            try await repository.contributeToGoal(goalId: goalId, amountMinor: 1, fromWalletId: sourceWallet.id)
            XCTFail("Expected the overflowing wallet balance to reject the contribution")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .balanceUnavailable)
        }

        let afterRejectedWrite = try await repository.snapshot()
        XCTAssertEqual(afterRejectedWrite.goals.first(where: { $0.id == goalId })?.allocatedMinor, 0)
        XCTAssertTrue(afterRejectedWrite.goalContributions.isEmpty)
        XCTAssertTrue(afterRejectedWrite.transactions.isEmpty)
        XCTAssertEqual(afterRejectedWrite.walletBalancesMinor[sourceWallet.id], Int64.min)
        XCTAssertEqual(afterRejectedWrite.walletBalancesMinor[savingsWalletId], 0)
    }

    func testIncomeSourceKindsAndIncomeTransactionsUseSharedStableValues() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryIncomeSourceTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: TestFinanceRules()
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initial = try await repository.snapshot()
        let wallet = try XCTUnwrap(initial.activeWallets.first)
        let incomeCategoryId = try XCTUnwrap(initial.activeCategories(typeName: "INCOME").first?.id)
        let sourceId = try await repository.addIncomeSource(name: "Weekend market", kindName: "GIG")
        let transactionId = try await repository.recordTransaction(
            typeName: "INCOME",
            amountMinor: 300,
            walletId: wallet.id,
            categoryId: incomeCategoryId,
            incomeSourceId: sourceId,
            transactionId: "linked-income",
            note: "Market sales"
        )
        try await repository.updateIncomeSource(id: sourceId, name: "Farm stand", kindName: "FARMING")
        _ = try await repository.recordTransaction(
            typeName: "INCOME",
            amountMinor: 300,
            walletId: wallet.id,
            categoryId: incomeCategoryId,
            incomeSourceId: sourceId,
            transactionId: transactionId,
            note: "Updated market sales"
        )

        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.incomeSources.first(where: { $0.id == sourceId })?.name, "Farm stand")
        XCTAssertEqual(snapshot.incomeSources.first(where: { $0.id == sourceId })?.kindName, "FARMING")
        XCTAssertEqual(snapshot.transactions.first(where: { $0.id == transactionId })?.incomeSourceId, sourceId)
        XCTAssertEqual(snapshot.transactions.first(where: { $0.id == transactionId })?.note, "Updated market sales")

        let expenseCategoryId = try XCTUnwrap(snapshot.activeCategories(typeName: "EXPENSE").first?.id)
        do {
            _ = try await repository.recordTransaction(
                typeName: "EXPENSE",
                amountMinor: 1,
                walletId: wallet.id,
                categoryId: expenseCategoryId,
                incomeSourceId: sourceId,
                note: "Invalid source assignment"
            )
            XCTFail("Income sources must not be attached to non-income transactions")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .invalidTransactionType)
        }

        do {
            _ = try await repository.addIncomeSource(name: "Unsupported", kindName: "UNSUPPORTED")
            XCTFail("An income source kind outside the KMP enum must be rejected")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .invalidIncomeSourceKind)
        }
        let afterRejectedKind = try await repository.snapshot()
        XCTAssertEqual(afterRejectedKind.incomeSources.count, 1)
        XCTAssertEqual(afterRejectedKind.transactions.count, 1)
    }

    func testCategoryRenameArchiveAndRestoreKeepTransactionIdentityAndReference() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryCategoryLifecycleTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: TestFinanceRules()
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        let initialSnapshot = try await repository.snapshot()
        let wallet = try XCTUnwrap(initialSnapshot.activeWallets.first)
        let categoryId = try await repository.addCategory(
            name: "  Travel  ",
            typeName: "EXPENSE",
            icon: "transport",
            colorHex: "#376D9D"
        )
        let transactionId = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 100,
            walletId: wallet.id,
            categoryId: categoryId,
            note: "Bus fare"
        )

        try await repository.updateCategory(
            id: categoryId,
            name: "Local travel",
            icon: "transport",
            colorHex: "#0A9C8B"
        )
        var snapshot = try await repository.snapshot()
        let renamedCategory = try XCTUnwrap(snapshot.categories.first(where: { $0.id == categoryId }))
        XCTAssertEqual(renamedCategory.name, "Local travel")
        XCTAssertEqual(renamedCategory.colorHex, "#0A9C8B")
        XCTAssertEqual(snapshot.transactions.first(where: { $0.id == transactionId })?.categoryId, categoryId)

        try await repository.setCategoryArchived(id: categoryId, archived: true)
        snapshot = try await repository.snapshot()
        XCTAssertTrue(snapshot.categories.first(where: { $0.id == categoryId })?.archived == true)
        XCTAssertEqual(snapshot.transactions.first(where: { $0.id == transactionId })?.categoryId, categoryId)

        _ = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 120,
            walletId: wallet.id,
            categoryId: categoryId,
            transactionId: transactionId,
            note: "Updated bus fare"
        )
        snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.activeTransactions.count, 1)
        XCTAssertEqual(snapshot.activeTransactions.first?.id, transactionId)
        XCTAssertEqual(snapshot.activeTransactions.first?.categoryId, categoryId)
        XCTAssertEqual(snapshot.activeTransactions.first?.note, "Updated bus fare")

        try await repository.setCategoryArchived(id: categoryId, archived: false)
        snapshot = try await repository.snapshot()
        XCTAssertFalse(snapshot.categories.first(where: { $0.id == categoryId })?.archived ?? true)
        XCTAssertEqual(snapshot.transactions.first(where: { $0.id == transactionId })?.categoryId, categoryId)
    }

    func testCategoryArchiveCannotRemoveLastActiveCategoryOfItsType() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryLastCategoryTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: TestFinanceRules()
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 0
        )

        try await repository.setCategoryArchived(id: "fees-category", archived: true)
        do {
            try await repository.setCategoryArchived(id: "expense-category", archived: true)
            XCTFail("The final active expense category must remain available")
        } catch let error as IOSFinanceRepositoryError {
            XCTAssertEqual(error, .categoryLastActive)
        }

        let snapshot = try await repository.snapshot()
        XCTAssertEqual(snapshot.activeCategories(typeName: "EXPENSE").map(\.id), ["expense-category"])
        XCTAssertTrue(snapshot.categories.first(where: { $0.id == "fees-category" })?.archived == true)
    }

    func testArchivedFeesCategoryStillReceivesAutomaticallyCategorizedFees() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryArchivedFeesTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: TestFinanceRules()
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 1_000
        )
        try await repository.setCategoryArchived(id: "fees-category", archived: true)
        let snapshot = try await repository.snapshot()
        let wallet = try XCTUnwrap(snapshot.activeWallets.first)

        _ = try await repository.recordTransaction(
            typeName: "EXPENSE",
            amountMinor: 100,
            feeMinor: 10,
            walletId: wallet.id,
            categoryId: "expense-category",
            note: "Market"
        )

        let afterWrite = try await repository.snapshot()
        XCTAssertEqual(afterWrite.activeTransactions.first?.feeCategoryId, "fees-category")
        XCTAssertEqual(afterWrite.walletBalancesMinor[wallet.id], 890)
    }

    func testCategoryReorderingIsScopedToItsType() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try IOSFinanceRepository(
            databaseDirectoryURL: directory,
            keyProvider: KeychainDatabaseKeyProvider(
                service: "IOSFinanceRepositoryCategoryOrderTests",
                keychain: MemoryKeychainValueStore()
            ),
            rules: TestFinanceRules()
        )
        try await repository.createWorkspace(
            name: "My money",
            countryCode: "UG",
            currencyCode: "UGX",
            walletName: "Cash",
            walletTypeName: "CASH",
            openingBalanceMinor: 0
        )
        let travelId = try await repository.addCategory(
            name: "Travel",
            typeName: "EXPENSE",
            icon: "transport",
            colorHex: "#376D9D"
        )

        try await repository.moveCategory(id: travelId, direction: -1)
        let snapshot = try await repository.snapshot()
        XCTAssertEqual(
            snapshot.activeCategories(typeName: "EXPENSE").map(\.id),
            ["expense-category", travelId, "fees-category"]
        )
        XCTAssertEqual(snapshot.activeCategories(typeName: "INCOME").map(\.id), ["income-category"])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("IOSFinanceRepositoryTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private struct TestFinanceRules: IOSFinanceRulesProviding {
    static let categories = [
        IOSCategorySeed(id: "expense-category", key: "other_expense", name: "Other", typeName: "EXPENSE", icon: "other", colorHex: "#6D6D6D"),
        IOSCategorySeed(id: "income-category", key: "salary", name: "Salary", typeName: "INCOME", icon: "income", colorHex: "#087F72"),
        IOSCategorySeed(id: "fees-category", key: "mobile_money_fees", name: "Mobile money fees", typeName: "EXPENSE", icon: "fees", colorHex: "#865C19"),
    ]

    func transactionValidationError(typeName: String, amountMinor: Int64, feeMinor: Int64) -> String? {
        guard ["EXPENSE", "INCOME", "TRANSFER", "REFUND", "ADJUSTMENT"].contains(typeName) else {
            return "transaction_type_invalid"
        }
        guard feeMinor >= 0 else { return "fee_invalid" }
        guard typeName == "ADJUSTMENT" ? amountMinor != 0 : amountMinor > 0 else { return "amount_invalid" }
        return nil
    }

    func isSupportedAmountMinor(_ amountMinor: Int64) -> Bool {
        amountMinor >= -9_000_000_000_000_000 && amountMinor <= 9_000_000_000_000_000
    }

    func isValidWalletTypeName(_ typeName: String) -> Bool {
        ["CASH", "MOBILE_MONEY", "BANK", "CARD", "SAVINGS", "DEBT", "OTHER"].contains(typeName)
    }

    func isSupportedCurrencyCode(_ currencyCode: String) -> Bool {
        ["UGX", "KES", "TZS", "RWF", "NGN", "GHS", "ZAR", "USD", "EUR", "GBP"].contains(currencyCode)
    }

    func canArchiveCategory(activeCategoryCount: Int64) -> Bool {
        activeCategoryCount > 1
    }

    func canAssignIncomeSource(typeName: String, hasIncomeSource: Bool) -> Bool {
        !hasIncomeSource || typeName == "INCOME"
    }

    func isSupportedGoalTargetMinor(_ amountMinor: Int64) -> Bool {
        amountMinor > 0 && amountMinor <= 9_000_000_000_000_000
    }

    func isSupportedGoalContributionMinor(_ amountMinor: Int64) -> Bool {
        amountMinor > 0 && amountMinor <= 9_000_000_000_000_000
    }

    func goalAllocatedMinorAfterContribution(currentAllocatedMinor: Int64, contributionMinor: Int64) -> String? {
        guard currentAllocatedMinor >= 0,
              currentAllocatedMinor <= 9_000_000_000_000_000,
              contributionMinor > 0,
              contributionMinor <= 9_000_000_000_000_000,
              let updated = checkedAdd(currentAllocatedMinor, contributionMinor),
              updated <= 9_000_000_000_000_000 else { return nil }
        return String(updated)
    }

    func commitmentDraftValidationError(
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        targetMinor: Int64,
        targetWorkspaceMinor: Int64,
        exchangeRate: String?,
        exchangeRateDate: String?,
        todayEpochDay: Int64
    ) -> String? {
        guard isSupportedCurrencyCode(workspaceCurrencyCode),
              isSupportedCurrencyCode(commitmentCurrencyCode) else { return "currency_unsupported" }
        guard targetMinor > 0, targetMinor <= 9_000_000_000_000_000 else { return "target_invalid" }
        guard targetWorkspaceMinor > 0, targetWorkspaceMinor <= 9_000_000_000_000_000 else {
            return "target_workspace_invalid"
        }
        if workspaceCurrencyCode == commitmentCurrencyCode {
            return targetMinor == targetWorkspaceMinor && exchangeRate == nil && exchangeRateDate == nil
                ? nil : "same_currency_target_mismatch"
        }
        guard let exchangeRate, !exchangeRate.isEmpty, let exchangeRateDate else { return "rate_missing_or_invalid" }
        guard let rate = Decimal(string: exchangeRate), rate > 0 else { return "rate_invalid" }
        guard let date = ISO8601DateFormatter().date(from: exchangeRateDate + "T00:00:00Z") else {
            return "rate_date_invalid"
        }
        let rateEpochDay = Int64(date.timeIntervalSince1970 / 86_400)
        return rateEpochDay <= todayEpochDay ? nil : "rate_date_future"
    }

    func commitmentToWorkspaceMinor(
        amountMinor: Int64,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?
    ) -> String? {
        guard workspaceCurrencyCode == commitmentCurrencyCode else { return nil }
        return String(amountMinor)
    }

    func workspaceToCommitmentMinor(
        amountMinor: Int64,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?
    ) -> String? {
        guard workspaceCurrencyCode == commitmentCurrencyCode else { return nil }
        return String(amountMinor)
    }

    func investmentAssetTypes() -> [IOSInvestmentAssetType] {
        [
            IOSInvestmentAssetType(name: "STOCKS", label: "Stocks"),
            IOSInvestmentAssetType(name: "BONDS", label: "Bonds"),
            IOSInvestmentAssetType(name: "FUNDS", label: "Funds"),
            IOSInvestmentAssetType(name: "REAL_ESTATE", label: "Real estate"),
            IOSInvestmentAssetType(name: "BUSINESS", label: "Business"),
            IOSInvestmentAssetType(name: "CASH_EQUIVALENT", label: "Cash equivalent"),
            IOSInvestmentAssetType(name: "OTHER", label: "Other"),
        ]
    }

    func investmentDraftValidationError(
        name: String,
        provider: String,
        note: String,
        assetTypeName: String,
        costBasisMinor: Int64,
        currentValueMinor: Int64,
        valuationEpochDay: Int64,
        todayEpochDay: Int64
    ) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "name_required" }
        if name.count > 80 { return "name_too_long" }
        if provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "provider_required" }
        if provider.count > 80 { return "provider_too_long" }
        if note.count > 240 { return "note_too_long" }
        if !investmentAssetTypes().contains(where: { $0.name == assetTypeName }) { return "asset_type_invalid" }
        if costBasisMinor <= 0 || costBasisMinor > 9_000_000_000_000_000 { return "cost_basis_invalid" }
        if currentValueMinor < 0 || currentValueMinor > 9_000_000_000_000_000 { return "current_value_invalid" }
        if valuationEpochDay > todayEpochDay { return "valuation_date_invalid" }
        return nil
    }

    func investmentPortfolioSummary(
        costBasisMinor: [Int64],
        currentValueMinor: [Int64],
        active: [Bool]
    ) -> IOSInvestmentPortfolioSummary? {
        guard costBasisMinor.count == currentValueMinor.count,
              costBasisMinor.count == active.count else { return nil }
        var count = 0
        var costTotal: Int64 = 0
        var valueTotal: Int64 = 0
        for index in active.indices where active[index] {
            guard costBasisMinor[index] > 0,
                  costBasisMinor[index] <= 9_000_000_000_000_000,
                  currentValueMinor[index] >= 0,
                  currentValueMinor[index] <= 9_000_000_000_000_000,
                  let nextCost = checkedAdd(costTotal, costBasisMinor[index]),
                  let nextValue = checkedAdd(valueTotal, currentValueMinor[index]) else { return nil }
            count += 1
            costTotal = nextCost
            valueTotal = nextValue
        }
        guard let gainLoss = checkedSubtract(valueTotal, costTotal) else { return nil }
        return IOSInvestmentPortfolioSummary(
            holdingCount: count,
            costBasisMinor: costTotal,
            currentValueMinor: valueTotal,
            gainLossMinor: gainLoss
        )
    }

    func defaultCategories() -> [IOSCategorySeed] { Self.categories }

    func incomeSourceKinds() -> [IOSIncomeSourceKind] {
        [
            IOSIncomeSourceKind(name: "SALARY", label: "Salary"),
            IOSIncomeSourceKind(name: "BUSINESS", label: "Business"),
            IOSIncomeSourceKind(name: "FREELANCE", label: "Freelance"),
            IOSIncomeSourceKind(name: "GIG", label: "Casual / gig work"),
            IOSIncomeSourceKind(name: "REMITTANCE", label: "Remittance"),
            IOSIncomeSourceKind(name: "FARMING", label: "Farming"),
            IOSIncomeSourceKind(name: "OTHER", label: "Other"),
        ]
    }

    func feesCategoryId() -> String { "fees-category" }

    func walletBalanceMinor(
        walletId: String,
        openingBalanceMinor: Int64,
        transactions: [IOSTransactionRecord]
    ) -> String? {
        var balance = openingBalanceMinor
        for transaction in transactions where !transaction.deleted {
            switch transaction.typeName {
            case "INCOME" where transaction.walletId == walletId:
                guard let updated = checkedAdd(balance, transaction.amountMinor) else { return nil }
                balance = updated
            case "EXPENSE" where transaction.walletId == walletId:
                guard let expense = checkedAdd(transaction.amountMinor, transaction.feeMinor),
                      let updated = checkedSubtract(balance, expense) else { return nil }
                balance = updated
            case "ADJUSTMENT" where transaction.walletId == walletId:
                guard let updated = checkedAdd(balance, transaction.amountMinor) else { return nil }
                balance = updated
            case "REFUND" where transaction.walletId == walletId:
                guard let refund = checkedSubtract(transaction.amountMinor, transaction.feeMinor),
                      let updated = checkedAdd(balance, refund) else { return nil }
                balance = updated
            case "TRANSFER":
                if transaction.walletId == walletId {
                    guard let transfer = checkedAdd(transaction.amountMinor, transaction.feeMinor),
                          let updated = checkedSubtract(balance, transfer) else { return nil }
                    balance = updated
                } else if transaction.destinationWalletId == walletId {
                    guard let updated = checkedAdd(balance, transaction.amountMinor) else { return nil }
                    balance = updated
                }
            case "INCOME", "EXPENSE", "ADJUSTMENT", "REFUND": break
            default: return nil
            }
        }
        return String(balance)
    }

    private func checkedAdd(_ left: Int64, _ right: Int64) -> Int64? {
        let (result, overflow) = left.addingReportingOverflow(right)
        return overflow ? nil : result
    }

    private func checkedSubtract(_ left: Int64, _ right: Int64) -> Int64? {
        let (result, overflow) = left.subtractingReportingOverflow(right)
        return overflow ? nil : result
    }
}

private final class MemoryKeychainValueStore: KeychainValueStoring, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()

    func read(service: String, account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values["\(service):\(account)"]
    }

    func write(_ value: Data, service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(service):\(account)"
        guard values[key] == nil else { throw KeychainValueStoreError.duplicateItem }
        values[key] = value
    }
}
