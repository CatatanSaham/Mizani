import MizaniCore
import SwiftUI

struct CommitmentManagementView: View {
    let commitments: [IOSCommitmentRecord]
    let progress: [IOSCommitmentProgress]
    let payments: [IOSCommitmentPaymentRecord]
    let transactions: [IOSTransactionRecord]
    let categories: [IOSCategoryRecord]
    let currencyOptions: [IOSCurrencyOption]
    let workspaceCurrencyCode: String
    let balancesHidden: Bool
    let isSaving: Bool
    let formatted: (Int64, String?) -> String
    let inputAmount: (Int64, String?) -> String
    let loadExchangeRate: (String, String, Bool) async throws -> IOSExchangeRateQuote
    let onSave: (IOSCommitmentRecord?, String, String, String, IOSExchangeRateQuote?, Date, String?) async -> Bool
    let onArchive: (IOSCommitmentRecord, Bool) async -> Bool
    let onDelete: (IOSCommitmentRecord) async -> Bool
    let onLinkExpense: (IOSCommitmentRecord, IOSTransactionRecord) async -> Bool
    let onUnlinkPayment: (IOSCommitmentPaymentRecord) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showArchived = false
    @State private var editingCommitment: IOSCommitmentRecord?
    @State private var isEditorPresented = false
    @State private var linkingCommitment: IOSCommitmentRecord?
    @State private var pendingDelete: IOSCommitmentRecord?

    private var visibleCommitments: [IOSCommitmentRecord] {
        commitments
            .filter { $0.archived == showArchived && !$0.deleted }
            .sorted { lhs, rhs in
                lhs.dueEpochDay == rhs.dueEpochDay
                    ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    : lhs.dueEpochDay < rhs.dueEpochDay
            }
    }

    private var transactionsById: [String: IOSTransactionRecord] {
        Dictionary(uniqueKeysWithValues: transactions.map { ($0.id, $0) })
    }

    private var alreadyLinkedTransactionIds: Set<String> {
        Set(payments.map(\.transactionId))
    }

    private var linkableExpenses: [IOSTransactionRecord] {
        var refundsByExpenseId: [String: Int64] = [:]
        var invalidRefundTotals = Set<String>()
        for transaction in transactions where !transaction.deleted && transaction.typeName == "REFUND" {
            guard let expenseId = transaction.linkedTransactionId else { continue }
            let (sum, overflow) = (refundsByExpenseId[expenseId] ?? 0)
                .addingReportingOverflow(transaction.amountMinor)
            if overflow {
                invalidRefundTotals.insert(expenseId)
            } else {
                refundsByExpenseId[expenseId] = sum
            }
        }
        return transactions.filter { transaction in
            transaction.typeName == "EXPENSE" && !transaction.deleted &&
                transaction.currencyCode == workspaceCurrencyCode &&
                !alreadyLinkedTransactionIds.contains(transaction.id) &&
                !invalidRefundTotals.contains(transaction.id) &&
                transaction.amountMinor > (refundsByExpenseId[transaction.id] ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(showArchived ? "Showing archived commitments" : "Show archived commitments", isOn: $showArchived)
                        .font(.system(size: 14, weight: .medium))
                        .tint(MizaniColors.teal)

                    if visibleCommitments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(showArchived ? "No archived commitments" : "No commitments yet", systemImage: "calendar.badge.clock")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(MizaniColors.ink)
                            Text(showArchived ? "Archived commitments remain saved here." : "Track bills and planned expenses, then link expenses you already recorded.")
                                .font(.system(size: 13))
                                .foregroundStyle(MizaniColors.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
                        .padding(16)
                        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        ForEach(visibleCommitments) { commitment in
                            commitmentCard(commitment)
                        }
                    }

                    Text("Linked expenses stay in the ledger and are not copied. iOS reminders and backup/restore are not available in this preview.")
                        .font(.system(size: 12))
                        .foregroundStyle(MizaniColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(18)
            }
            .background(MizaniColors.page.ignoresSafeArea())
            .navigationTitle("Commitments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingCommitment = nil
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add commitment")
                    .disabled(isSaving || showArchived)
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                CommitmentEditorView(
                    commitment: editingCommitment,
                    categories: categories,
                    currencyOptions: currencyOptions,
                    workspaceCurrencyCode: workspaceCurrencyCode,
                    balancesHidden: balancesHidden,
                    isSaving: isSaving,
                    formatted: formatted,
                    inputAmount: inputAmount,
                    loadExchangeRate: loadExchangeRate,
                    onSave: onSave
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $linkingCommitment) { commitment in
                CommitmentExpensePicker(
                    commitment: commitment,
                    expenses: linkableExpenses,
                    balancesHidden: balancesHidden,
                    isSaving: isSaving,
                    formatted: formatted,
                    onSelect: { expense in
                        let linked = await onLinkExpense(commitment, expense)
                        if linked { linkingCommitment = nil }
                        return linked
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Delete this commitment?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete commitment", role: .destructive) {
                    guard let commitment = pendingDelete else { return }
                    pendingDelete = nil
                    Task { _ = await onDelete(commitment) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This removes the payment links only. The expenses remain in your ledger.")
            }
        }
    }

    private func commitmentCard(_ commitment: IOSCommitmentRecord) -> some View {
        let item = progress.first(where: { $0.id == commitment.id })
        let linkedPayments = payments.filter { $0.commitmentId == commitment.id }
        let dueDate = IOSFinanceRepository.commitmentDate(fromEpochDay: commitment.dueEpochDay)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(commitment.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MizaniColors.ink)
                    Text("Due \(dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundStyle(MizaniColors.muted)
                }
                Spacer(minLength: 4)
                Button("Edit") {
                    editingCommitment = commitment
                    isEditorPresented = true
                }
                .font(.system(size: 13, weight: .semibold))
                .tint(MizaniColors.teal)
                .disabled(isSaving)
            }

            if let item, item.isAvailable,
               let paidMinor = item.paidMinor,
               let remainingMinor = item.remainingMinor {
                ProgressView(value: min(1, max(0, Double(paidMinor) / Double(max(commitment.targetMinor, 1)))))
                    .tint(MizaniColors.teal)
                    .accessibilityLabel("Commitment progress")
                HStack(alignment: .firstTextBaseline) {
                    Text("Paid \(protectedAmount(paidMinor, currencyCode: commitment.currencyCode)) of \(protectedAmount(commitment.targetMinor, currencyCode: commitment.currencyCode))")
                    Spacer(minLength: 8)
                    Text("\(protectedAmount(remainingMinor, currencyCode: commitment.currencyCode)) left")
                        .fontWeight(.semibold)
                }
                .font(.system(size: 13))
                .foregroundStyle(MizaniColors.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    balancesHidden
                        ? "Commitment amounts hidden"
                        : "Paid \(commitment.currencyCode) \(formatted(paidMinor, commitment.currencyCode)) of \(commitment.currencyCode) \(formatted(commitment.targetMinor, commitment.currencyCode)); \(formatted(remainingMinor, commitment.currencyCode)) remaining"
                )
            } else {
                Text("Progress is unavailable until the saved payment totals can be checked safely.")
                    .font(.system(size: 13))
                    .foregroundStyle(MizaniColors.muted)
            }

            if !linkedPayments.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Linked expenses")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MizaniColors.muted)
                    ForEach(linkedPayments) { payment in
                        if let transaction = transactionsById[payment.transactionId] {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(transaction.note.isEmpty ? "Expense" : transaction.note)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(MizaniColors.ink)
                                        .lineLimit(1)
                                    Text(transaction.currencyCode + " " + protectedValue(transaction.amountMinor, currencyCode: transaction.currencyCode))
                                        .font(.system(size: 12))
                                        .foregroundStyle(MizaniColors.muted)
                                        .accessibilityLabel(balancesHidden ? "Expense amount hidden" : "\(transaction.currencyCode) \(formatted(transaction.amountMinor, transaction.currencyCode))")
                                }
                                Spacer(minLength: 4)
                                Button("Unlink") {
                                    Task { _ = await onUnlinkPayment(payment) }
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .tint(MizaniColors.teal)
                                .disabled(isSaving)
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }

            HStack(spacing: 10) {
                if !commitment.archived {
                    Button {
                        linkingCommitment = commitment
                    } label: {
                        Label("Link expense", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MizaniColors.teal)
                    .disabled(isSaving || linkableExpenses.isEmpty)
                }
                Button(commitment.archived ? "Restore" : "Archive") {
                    Task { _ = await onArchive(commitment, !commitment.archived) }
                }
                .buttonStyle(.bordered)
                .tint(MizaniColors.ink)
                .disabled(isSaving)
                if !commitment.archived {
                    Button(role: .destructive) { pendingDelete = commitment } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Delete commitment")
                    .disabled(isSaving)
                }
            }
        }
        .padding(16)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func protectedAmount(_ amount: Int64, currencyCode: String) -> String {
        balancesHidden ? "••••••" : "\(currencyCode) \(formatted(amount, currencyCode))"
    }

    private func protectedValue(_ amount: Int64, currencyCode: String) -> String {
        balancesHidden ? "••••••" : formatted(amount, currencyCode)
    }
}

private struct CommitmentEditorView: View {
    let commitment: IOSCommitmentRecord?
    let categories: [IOSCategoryRecord]
    let currencyOptions: [IOSCurrencyOption]
    let workspaceCurrencyCode: String
    let balancesHidden: Bool
    let isSaving: Bool
    let formatted: (Int64, String?) -> String
    let inputAmount: (Int64, String?) -> String
    let loadExchangeRate: (String, String, Bool) async throws -> IOSExchangeRateQuote
    let onSave: (IOSCommitmentRecord?, String, String, String, IOSExchangeRateQuote?, Date, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var amount: String
    @State private var targetCurrencyCode: String
    @State private var dueDate: Date
    @State private var categoryId: String?
    @State private var exchangeRate: IOSExchangeRateQuote?
    @State private var isRateLoading = false
    @State private var rateError: String?
    @State private var localError: String?

    init(
        commitment: IOSCommitmentRecord?,
        categories: [IOSCategoryRecord],
        currencyOptions: [IOSCurrencyOption],
        workspaceCurrencyCode: String,
        balancesHidden: Bool,
        isSaving: Bool,
        formatted: @escaping (Int64, String?) -> String,
        inputAmount: @escaping (Int64, String?) -> String,
        loadExchangeRate: @escaping (String, String, Bool) async throws -> IOSExchangeRateQuote,
        onSave: @escaping (IOSCommitmentRecord?, String, String, String, IOSExchangeRateQuote?, Date, String?) async -> Bool
    ) {
        self.commitment = commitment
        self.categories = categories
        self.currencyOptions = currencyOptions
        self.workspaceCurrencyCode = workspaceCurrencyCode
        self.balancesHidden = balancesHidden
        self.isSaving = isSaving
        self.formatted = formatted
        self.inputAmount = inputAmount
        self.loadExchangeRate = loadExchangeRate
        self.onSave = onSave
        _name = State(initialValue: commitment?.name ?? "")
        _amount = State(initialValue: commitment.map {
            balancesHidden ? "" : inputAmount($0.targetMinor, $0.currencyCode)
        } ?? "")
        _targetCurrencyCode = State(initialValue: commitment?.currencyCode ?? workspaceCurrencyCode)
        _dueDate = State(initialValue: commitment.map {
            IOSFinanceRepository.commitmentDate(fromEpochDay: $0.dueEpochDay)
        } ?? Date())
        _categoryId = State(initialValue: commitment?.categoryId)
        if let savedRate = commitment?.exchangeRate,
           let savedDate = commitment?.exchangeRateDate {
            _exchangeRate = State(initialValue: IOSExchangeRateQuote(
                baseCurrencyCode: commitment?.currencyCode ?? workspaceCurrencyCode,
                quoteCurrencyCode: workspaceCurrencyCode,
                rate: savedRate,
                date: savedDate
            ))
        } else {
            _exchangeRate = State(initialValue: nil)
        }
    }

    private var targetCurrency: IOSCurrencyOption? {
        currencyOptions.first(where: { $0.code == targetCurrencyCode })
    }

    private var isForeignCurrency: Bool {
        targetCurrencyCode != workspaceCurrencyCode
    }

    private var targetCurrencyLabel: String {
        guard let currency = targetCurrency else { return targetCurrencyCode }
        return "\(currency.code) · \(currency.name)"
    }

    private var selectedCategoryLabel: String {
        guard let category = availableCategories.first(where: { $0.id == categoryId }) else { return "None" }
        return category.name
    }

    private var availableCategories: [IOSCategoryRecord] {
        categories.filter { $0.typeName == "EXPENSE" && !$0.deleted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            commitmentForm
                .navigationTitle(commitment == nil ? "Add commitment" : "Edit commitment")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSaving ? "Saving…" : "Save") { save() }
                            .disabled(isSaving || (isForeignCurrency && isRateLoading))
                    }
                }
                .task(id: targetCurrencyCode + "|" + workspaceCurrencyCode) {
                    await refreshQuoteIfNeeded()
                }
        }
    }

    @ViewBuilder
    private var commitmentForm: some View {
        Form {
            detailsSection
            if let localError {
                Section { Text(localError).foregroundStyle(.red).font(.footnote) }
            }
            Section {
                Text("Scheduled reminders are not available in this iOS preview.")
                    .font(.footnote)
                    .foregroundStyle(MizaniColors.muted)
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
                .accessibilityLabel("Commitment name")
            TextField("Target amount", text: $amount)
                .keyboardType(.decimalPad)
                .accessibilityLabel("Commitment target amount")
            currencyMenu
            if isForeignCurrency {
                exchangeRateStatus
            }
            DatePicker("Due date", selection: $dueDate, displayedComponents: .date)
            categoryMenu
        } header: {
            Text(commitment == nil ? "New commitment" : "Edit commitment")
        } footer: {
            Text("Saved foreign-currency targets use the displayed daily reference rate. The rate request sends currency codes only.")
        }
    }

    @ViewBuilder
    private var currencyMenu: some View {
        Menu {
            ForEach(currencyOptions) { option in
                Button("\(option.code) · \(option.name)") {
                    guard option.code != targetCurrencyCode else { return }
                    targetCurrencyCode = option.code
                    amount = ""
                    exchangeRate = nil
                    rateError = nil
                    localError = nil
                }
            }
        } label: {
            HStack {
                Text("Target currency")
                Spacer()
                Text(targetCurrencyLabel)
                    .foregroundStyle(MizaniColors.muted)
            }
        }
    }

    @ViewBuilder
    private var categoryMenu: some View {
        Menu {
            Button("No category") { categoryId = nil }
            ForEach(availableCategories) { category in
                Button(category.name) { categoryId = category.id }
            }
        } label: {
            HStack {
                Text("Expense category")
                Spacer()
                Text(selectedCategoryLabel)
                    .foregroundStyle(MizaniColors.muted)
            }
        }
    }

    private func save() {
        Task {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                localError = "Enter a commitment name."
                return
            }
            guard !amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                localError = "Enter a target amount."
                return
            }
            if isForeignCurrency && exchangeRate == nil {
                localError = rateError ?? "Wait for a reference rate before saving."
                return
            }
            let saved = await onSave(
                commitment,
                name,
                amount,
                targetCurrencyCode,
                isForeignCurrency ? exchangeRate : nil,
                dueDate,
                categoryId
            )
            if saved { dismiss() }
        }
    }

    @ViewBuilder
    private var exchangeRateStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRateLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Getting the latest daily reference rate…")
                }
                .font(.footnote)
            } else if let exchangeRate {
                Text("1 \(exchangeRate.baseCurrencyCode) = \(exchangeRate.rate) \(exchangeRate.quoteCurrencyCode) · \(exchangeRate.date)")
                    .font(.footnote)
                    .foregroundStyle(MizaniColors.muted)
                Button("Refresh rate") {
                    Task { await refreshQuote(force: true) }
                }
                .font(.footnote.weight(.semibold))
                .disabled(isRateLoading || isSaving)
            } else {
                Text(rateError ?? "No reference rate is available for this currency pair.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("Try again") {
                    Task { await refreshQuote(force: true) }
                }
                .font(.footnote.weight(.semibold))
                .disabled(isRateLoading || isSaving)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func refreshQuoteIfNeeded() async {
        guard isForeignCurrency else {
            exchangeRate = nil
            rateError = nil
            isRateLoading = false
            return
        }
        if let commitment,
           commitment.currencyCode == targetCurrencyCode,
           let rate = commitment.exchangeRate,
           let date = commitment.exchangeRateDate {
            exchangeRate = IOSExchangeRateQuote(
                baseCurrencyCode: targetCurrencyCode,
                quoteCurrencyCode: workspaceCurrencyCode,
                rate: rate,
                date: date
            )
            rateError = nil
            return
        }
        await refreshQuote(force: false)
    }

    private func refreshQuote(force: Bool) async {
        isRateLoading = true
        rateError = nil
        defer { isRateLoading = false }
        do {
            exchangeRate = try await loadExchangeRate(targetCurrencyCode, workspaceCurrencyCode, force)
        } catch is CancellationError {
            return
        } catch {
            rateError = "The reference rate could not be loaded. Check your connection and try again."
        }
    }
}

private struct CommitmentExpensePicker: View {
    let commitment: IOSCommitmentRecord
    let expenses: [IOSTransactionRecord]
    let balancesHidden: Bool
    let isSaving: Bool
    let formatted: (Int64, String?) -> String
    let onSelect: (IOSTransactionRecord) async -> Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if expenses.isEmpty {
                    Text("No unlinked expenses in \(commitment.currencyCode) are available.")
                        .font(.footnote)
                        .foregroundStyle(MizaniColors.muted)
                } else {
                    ForEach(expenses) { expense in
                        Button {
                            Task {
                                if await onSelect(expense) { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(expense.note.isEmpty ? "Expense" : expense.note)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(MizaniColors.ink)
                                        .lineLimit(1)
                                    Text(Date(timeIntervalSince1970: TimeInterval(expense.occurredAtMillis) / 1_000)
                                        .formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 12))
                                        .foregroundStyle(MizaniColors.muted)
                                }
                                Spacer(minLength: 8)
                                Text(balancesHidden ? "••••••" : "\(expense.currencyCode) \(formatted(expense.amountMinor, expense.currencyCode))")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(MizaniColors.ink)
                                    .accessibilityLabel(balancesHidden ? "Expense amount hidden" : "\(expense.currencyCode) \(formatted(expense.amountMinor, expense.currencyCode))")
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle("Link an expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
