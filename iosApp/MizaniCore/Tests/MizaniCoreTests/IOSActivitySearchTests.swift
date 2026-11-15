import Foundation
import XCTest
@testable import MizaniCore

final class IOSActivitySearchTests: XCTestCase {
    func testSearchMatchesNotesTypesWalletsCategoriesCurrenciesAndAmounts() {
        let transfer = transaction(
            id: "transfer",
            typeName: "TRANSFER",
            amountMinor: 1_000,
            walletId: "cash",
            destinationWalletId: "savings",
            note: "Market move"
        )
        let expense = transaction(
            id: "expense",
            typeName: "EXPENSE",
            amountMinor: 250,
            walletId: "savings",
            categoryId: "groceries",
            note: "Weekly shop"
        )
        let snapshot = IOSLedgerSnapshot(
            workspace: nil,
            wallets: [wallet(id: "cash", name: "Cash wallet"), wallet(id: "savings", name: "Savings")],
            categories: [category(id: "groceries", name: "Café and food")],
            transactions: [transfer, expense],
            walletBalancesMinor: [:]
        )
        let index = IOSActivitySearchIndex(
            snapshot: snapshot,
            normalizeSearchText: normalize,
            containsNormalized: containsNormalized
        )

        XCTAssertEqual(index.matchingTransactions([transfer, expense], query: "  market ").map(\.id), ["transfer"])
        XCTAssertEqual(index.matchingTransactions([transfer, expense], query: "transfer").map(\.id), ["transfer"])
        XCTAssertEqual(index.matchingTransactions([transfer, expense], query: "cash wallet").map(\.id), ["transfer"])
        XCTAssertEqual(index.matchingTransactions([transfer, expense], query: "CAFÉ").map(\.id), ["expense"])
        XCTAssertEqual(index.matchingTransactions([transfer, expense], query: "UGX").map(\.id), ["transfer", "expense"])
        XCTAssertEqual(index.matchingTransactions([transfer, expense], query: "1000").map(\.id), ["transfer"])
    }

    func testEmptySearchReturnsRowsInTheirOriginalOrder() {
        let first = transaction(id: "first", typeName: "INCOME", amountMinor: 10, walletId: "cash")
        let second = transaction(id: "second", typeName: "EXPENSE", amountMinor: 20, walletId: "cash")
        let index = IOSActivitySearchIndex(
            snapshot: snapshot(transactions: [first, second]),
            normalizeSearchText: normalize,
            containsNormalized: containsNormalized
        )

        XCTAssertEqual(index.matchingTransactions([second, first], query: "   ").map(\.id), ["second", "first"])
    }

    func testSearchMatchesIncomeSourceName() {
        let income = transaction(
            id: "income",
            typeName: "INCOME",
            amountMinor: 500,
            walletId: "cash",
            incomeSourceId: "salary-source"
        )
        let snapshot = IOSLedgerSnapshot(
            workspace: nil,
            wallets: [wallet(id: "cash", name: "Cash")],
            categories: [],
            incomeSources: [IOSIncomeSourceRecord(
                id: "salary-source",
                name: "Primary salary",
                kindName: "SALARY",
                archived: false,
                deleted: false
            )],
            transactions: [income],
            walletBalancesMinor: [:]
        )
        let index = IOSActivitySearchIndex(
            snapshot: snapshot,
            normalizeSearchText: normalize,
            containsNormalized: containsNormalized
        )

        XCTAssertEqual(index.matchingTransactions([income], query: "primary salary").map(\.id), ["income"])
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func containsNormalized(_ text: String, _ query: String) -> Bool {
        query.isEmpty || text.contains(query)
    }

    private func snapshot(transactions: [IOSTransactionRecord]) -> IOSLedgerSnapshot {
        IOSLedgerSnapshot(
            workspace: nil,
            wallets: [wallet(id: "cash", name: "Cash")],
            categories: [],
            transactions: transactions,
            walletBalancesMinor: [:]
        )
    }

    private func wallet(id: String, name: String) -> IOSWalletRecord {
        IOSWalletRecord(
            id: id,
            name: name,
            typeName: "CASH",
            openingBalanceMinor: 0,
            currencyCode: "UGX",
            archived: false,
            deleted: false
        )
    }

    private func category(id: String, name: String) -> IOSCategoryRecord {
        IOSCategoryRecord(
            id: id,
            name: name,
            typeName: "EXPENSE",
            icon: "basket",
            colorHex: "#008070",
            isDefault: true,
            archived: false,
            sortOrder: 0,
            deleted: false
        )
    }

    private func transaction(
        id: String,
        typeName: String,
        amountMinor: Int64,
        walletId: String,
        destinationWalletId: String? = nil,
        categoryId: String? = nil,
        incomeSourceId: String? = nil,
        note: String = ""
    ) -> IOSTransactionRecord {
        IOSTransactionRecord(
            id: id,
            typeName: typeName,
            amountMinor: amountMinor,
            feeMinor: 0,
            currencyCode: "UGX",
            walletId: walletId,
            destinationWalletId: destinationWalletId,
            categoryId: categoryId,
            feeCategoryId: nil,
            incomeSourceId: incomeSourceId,
            linkedTransactionId: nil,
            note: note,
            occurredAtMillis: 0,
            localDateEpochDay: 0,
            deleted: false
        )
    }
}
