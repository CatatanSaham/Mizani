import MizaniCore
import SwiftUI

struct InvestmentManagementView: View {
    let investments: [IOSInvestmentRecord]
    let summary: IOSInvestmentPortfolioSummary?
    let assetTypes: [IOSInvestmentAssetType]
    let currencyCode: String
    let balancesHidden: Bool
    let isSaving: Bool
    let formatted: (Int64) -> String
    let inputAmount: (Int64) -> String
    let onSave: (IOSInvestmentRecord?, String, String, String, String?, String?, Date, String) async -> Bool
    let onArchive: (IOSInvestmentRecord, Bool) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showArchived = false
    @State private var editingInvestment: IOSInvestmentRecord?
    @State private var isEditorPresented = false
    @State private var pendingArchive: IOSInvestmentRecord?

    private var visibleInvestments: [IOSInvestmentRecord] {
        investments.filter { $0.archived == showArchived && !$0.deleted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    portfolioCard
                    Toggle(showArchived ? "Showing archived investments" : "Show archived investments", isOn: $showArchived)
                        .font(.system(size: 14, weight: .medium))
                        .tint(MizaniColors.teal)
                    if visibleInvestments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(showArchived ? "No archived investments" : "No investments yet", systemImage: showArchived ? "archivebox" : "chart.line.uptrend.xyaxis")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(MizaniColors.ink)
                            Text(showArchived ? "Archived records appear here." : "Add a manual investment snapshot to track it alongside your finances.")
                                .font(.system(size: 13))
                                .foregroundStyle(MizaniColors.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
                    } else {
                        ForEach(visibleInvestments) { investment in
                            investmentCard(investment)
                        }
                    }
                    Text("Investment values are manual snapshots. They do not place orders, connect to providers, or change wallet balances or ledger activity.")
                        .font(.system(size: 12))
                        .foregroundStyle(MizaniColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .padding(18)
            }
            .background(MizaniColors.page.ignoresSafeArea())
            .navigationTitle("Investments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingInvestment = nil
                        isEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add investment")
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                InvestmentEditorView(
                    investment: editingInvestment,
                    assetTypes: assetTypes,
                    currencyCode: currencyCode,
                    balancesHidden: balancesHidden,
                    isSaving: isSaving,
                    inputAmount: inputAmount,
                    onSave: onSave
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Archive this investment?",
                isPresented: Binding(
                    get: { pendingArchive != nil },
                    set: { if !$0 { pendingArchive = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Archive", role: .destructive) {
                    guard let investment = pendingArchive else { return }
                    pendingArchive = nil
                    Task { _ = await onArchive(investment, true) }
                }
                Button("Cancel", role: .cancel) { pendingArchive = nil }
            } message: {
                Text("This hides the investment from the active portfolio summary. Its record is kept.")
            }
        }
    }

    private var portfolioCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Portfolio snapshot", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MizaniColors.ink)
                Spacer()
                Text(summary.map { "\($0.holdingCount) active" } ?? "Totals unavailable")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MizaniColors.muted)
            }
            if let summary {
                HStack(spacing: 12) {
                    portfolioValue(title: "Current value", amount: summary.currentValueMinor)
                    portfolioValue(title: "Cost basis", amount: summary.costBasisMinor)
                }
                HStack(spacing: 6) {
                    Text("Gain / loss")
                    Spacer()
                    Text(protectedAmount(summary.gainLossMinor))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 14))
                .foregroundStyle(MizaniColors.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(balancesHidden ? "Investment gain or loss hidden" : "Investment gain or loss \(formatted(summary.gainLossMinor))")
            } else {
                Text("Portfolio totals are unavailable until the saved values can be checked safely.")
                    .font(.system(size: 13))
                    .foregroundStyle(MizaniColors.muted)
            }
        }
        .padding(16)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func portfolioValue(title: String, amount: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundStyle(MizaniColors.muted)
            Text(protectedAmount(amount))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(balancesHidden ? "\(title) hidden" : "\(title) \(currencyCode) \(formatted(amount))")
    }

    private func investmentCard(_ investment: IOSInvestmentRecord) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(investment.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(MizaniColors.ink)
                    Text("\(investment.provider) · \(assetTypeLabel(investment.assetTypeName))")
                        .font(.system(size: 12)).foregroundStyle(MizaniColors.muted)
                }
                Spacer(minLength: 4)
                Button("Edit") {
                    editingInvestment = investment
                    isEditorPresented = true
                }
                .font(.system(size: 13, weight: .semibold))
                .tint(MizaniColors.teal)
                .disabled(isSaving)
            }
            HStack(spacing: 12) {
                recordValue(title: "Current", amount: investment.currentValueMinor, investment: investment)
                recordValue(title: "Cost basis", amount: investment.costBasisMinor, investment: investment)
            }
            let (gainLoss, overflow) = investment.currentValueMinor.subtractingReportingOverflow(investment.costBasisMinor)
            HStack {
                Text("Gain / loss")
                    .font(.system(size: 11))
                    .foregroundStyle(MizaniColors.muted)
                Spacer()
                Text(overflow ? "Unavailable" : protectedAmount(gainLoss, currencyCode: investment.currencyCode))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(overflow || gainLoss < 0 ? MizaniColors.muted : MizaniColors.teal)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                overflow ? "Investment gain or loss unavailable" :
                    (balancesHidden ? "Investment gain or loss hidden" : "Investment gain or loss \(investment.currencyCode) \(formatted(gainLoss))")
            )
            HStack {
                Text("Valued \(dateLabel(investment.valuationDateEpochDay))")
                Spacer()
                Button(investment.archived ? "Restore" : "Archive") {
                    if investment.archived {
                        Task { _ = await onArchive(investment, false) }
                    } else {
                        pendingArchive = investment
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .tint(investment.archived ? MizaniColors.teal : MizaniColors.muted)
                .disabled(isSaving)
            }
            .font(.system(size: 12))
            .foregroundStyle(MizaniColors.muted)
            if !investment.note.isEmpty {
                Text(investment.note).font(.system(size: 12)).foregroundStyle(MizaniColors.muted)
            }
        }
        .padding(15)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func recordValue(title: String, amount: Int64, investment: IOSInvestmentRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(MizaniColors.muted)
            Text(balancesHidden ? "••••••" : "\(investment.currencyCode) \(formatted(amount))")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(balancesHidden ? "\(title) hidden" : "\(title) \(investment.currencyCode) \(formatted(amount))")
    }

    private func protectedAmount(_ amount: Int64, currencyCode: String? = nil) -> String {
        let valueCurrency = currencyCode ?? self.currencyCode
        return balancesHidden ? "••••••" : "\(valueCurrency) \(formatted(amount))"
    }

    private func assetTypeLabel(_ name: String) -> String {
        assetTypes.first(where: { $0.name == name })?.label ?? "Other"
    }

    private func dateLabel(_ epochDay: Int64) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 1970
        components.month = 1
        components.day = 1
        let epochStart = calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
        let date = calendar.date(byAdding: .day, value: Int(epochDay), to: epochStart) ?? Date()
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct InvestmentEditorView: View {
    let investment: IOSInvestmentRecord?
    let assetTypes: [IOSInvestmentAssetType]
    let currencyCode: String
    let balancesHidden: Bool
    let isSaving: Bool
    let inputAmount: (Int64) -> String
    let onSave: (IOSInvestmentRecord?, String, String, String, String?, String?, Date, String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var provider: String
    @State private var assetTypeName: String
    @State private var costBasis: String
    @State private var currentValue: String
    @State private var valuationDate: Date
    @State private var note: String

    private var preserveHiddenValues: Bool { investment != nil && balancesHidden }

    init(
        investment: IOSInvestmentRecord?,
        assetTypes: [IOSInvestmentAssetType],
        currencyCode: String,
        balancesHidden: Bool,
        isSaving: Bool,
        inputAmount: @escaping (Int64) -> String,
        onSave: @escaping (IOSInvestmentRecord?, String, String, String, String?, String?, Date, String) async -> Bool
    ) {
        self.investment = investment
        self.assetTypes = assetTypes
        self.currencyCode = currencyCode
        self.balancesHidden = balancesHidden
        self.isSaving = isSaving
        self.inputAmount = inputAmount
        self.onSave = onSave
        _name = State(initialValue: investment?.name ?? "")
        _provider = State(initialValue: investment?.provider ?? "")
        _assetTypeName = State(initialValue: investment?.assetTypeName ?? assetTypes.first?.name ?? "OTHER")
        _costBasis = State(initialValue: investment.map { balancesHidden ? "" : inputAmount($0.costBasisMinor) } ?? "")
        _currentValue = State(initialValue: investment.map { balancesHidden ? "" : inputAmount($0.currentValueMinor) } ?? "")
        _valuationDate = State(initialValue: investment.map { Self.date(forEpochDay: $0.valuationDateEpochDay) } ?? Date())
        _note = State(initialValue: investment?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Investment") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Investment name")
                    TextField("Provider or where held", text: $provider)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Investment provider")
                    Picker("Asset category", selection: $assetTypeName) {
                        ForEach(assetTypes, id: \.name) { type in
                            Text(type.label).tag(type.name)
                        }
                    }
                    if preserveHiddenValues {
                        Text("Values are hidden. Reveal balances on Home before editing these amounts. Saved values will be kept.")
                            .font(.footnote)
                            .foregroundStyle(MizaniColors.muted)
                            .accessibilityLabel("Investment values are hidden and will be preserved")
                    } else {
                        TextField("Cost basis (\(currencyCode))", text: $costBasis)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Investment cost basis in \(currencyCode)")
                        TextField("Current value (\(currencyCode))", text: $currentValue)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Investment current value in \(currencyCode)")
                    }
                    DatePicker("Valuation date", selection: $valuationDate, in: ...Date(), displayedComponents: .date)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Text("This is a manual value snapshot. It does not place orders, connect to a provider, or affect wallet balances or activity.")
                        .font(.footnote)
                        .foregroundStyle(MizaniColors.muted)
                }
            }
            .navigationTitle(investment == nil ? "Add investment" : "Edit investment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task {
                            let costText: String? = preserveHiddenValues ? nil : costBasis
                            let valueText: String? = preserveHiddenValues ? nil : currentValue
                            if await onSave(investment, name, provider, assetTypeName, costText, valueText, valuationDate, note) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private static func date(forEpochDay epochDay: Int64) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.year = 1970
        components.month = 1
        components.day = 1
        guard let epochStart = calendar.date(from: components) else { return Date() }
        return calendar.date(byAdding: .day, value: Int(epochDay), to: epochStart) ?? Date()
    }
}
