import MizaniCore
import MizaniShared
import SwiftUI

private enum MizaniTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case activity = "Activity"
    case insights = "Insights"
    case more = "More"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .activity: "list.bullet.rectangle"
        case .insights: "chart.bar.xaxis"
        case .more: "ellipsis"
        }
    }
}

private enum MizaniComposer: String, Identifiable {
    case wallet
    case transaction

    var id: String { rawValue }
}

enum MizaniColors {
    static let ink = Color(red: 23.0 / 255.0, green: 53.0 / 255.0, blue: 61.0 / 255.0)
    static let teal = Color(red: 8.0 / 255.0, green: 127.0 / 255.0, blue: 114.0 / 255.0)
    static let muted = Color(red: 73.0 / 255.0, green: 101.0 / 255.0, blue: 105.0 / 255.0)
    static let page = Color(red: 242.0 / 255.0, green: 248.0 / 255.0, blue: 245.0 / 255.0)
    static let card = Color.white.opacity(0.9)
    static let line = Color(red: 222.0 / 255.0, green: 235.0 / 255.0, blue: 230.0 / 255.0)
    static let gold = Color(red: 232.0 / 255.0, green: 191.0 / 255.0, blue: 106.0 / 255.0)
}

private struct IOSInsightCategory: Identifiable {
    let id: String
    let name: String
    let colorHex: String
    let amountMinor: Int64
}

struct ContentView: View {
    @StateObject private var model = MizaniFinanceModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: MizaniTab = .home
    @State private var composer: MizaniComposer?
    @State private var editingTransaction: IOSTransactionRecord?
    @State private var transactionToDelete: IOSTransactionRecord?
    @State private var isPrivacyStatusPresented = false
    @State private var isCategoryManagementPresented = false
    @State private var isIncomeSourceManagementPresented = false
    @State private var isGoalManagementPresented = false
    @State private var isInvestmentManagementPresented = false
    @State private var isCommitmentManagementPresented = false
    @State private var isAppLockSettingsPresented = false
    @State private var isPrivacyShieldVisible = true
    @State private var balancesHidden = false
    @State private var activitySearchQuery = ""
    @State private var appliedActivitySearchQuery = ""
    @State private var activitySearchIndex: IOSActivitySearchIndex?
    @State private var matchingActivityTransactions: [IOSTransactionRecord] = []

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        pageContent
                        previewStatus
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }

                if model.snapshot.workspace != nil {
                    tabBar
                }
            }
            .background {
                LinearGradient(
                    colors: [MizaniColors.page, Color(red: 226.0 / 255.0, green: 244.0 / 255.0, blue: 237.0 / 255.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
            .allowsHitTesting(!model.isLockStateLoading && !model.isLocked && model.isStorageAvailable && !isPrivacyShieldVisible)
            .accessibilityHidden(model.isLockStateLoading || model.isLocked || !model.isStorageAvailable || isPrivacyShieldVisible)

            if model.isLockStateLoading {
                IOSAccessShield(title: "Opening secure storage", message: "Checking this device's app-lock state.")
            } else if model.isLocked {
                IOSAppLockScreen(model: model, onRetry: retryProtectedStorage)
            } else if !model.isStorageAvailable {
                IOSStorageRecoveryScreen(message: model.lockStateError, onRetry: retryProtectedStorage)
            } else if isPrivacyShieldVisible {
                IOSPrivacyShield()
            }
        }
        .preferredColorScheme(.light)
        .task {
            await model.bootstrap()
            if !model.isLocked && model.isStorageAvailable {
                isPrivacyShieldVisible = false
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .inactive:
                isPrivacyShieldVisible = true
            case .background:
                model.noteBackgrounded(at: Date())
                isPrivacyShieldVisible = true
                clearSensitiveViewState()
            case .active:
                Task {
                    await model.handleForeground(at: Date())
                    if !model.isLocked && model.isStorageAvailable {
                        isPrivacyShieldVisible = false
                    }
                }
            @unknown default:
                isPrivacyShieldVisible = true
            }
        }
        .onChange(of: model.isLocked) { locked in
            if locked {
                clearSensitiveViewState()
            } else if scenePhase == .active {
                isPrivacyShieldVisible = false
            }
        }
        .alert("Mizani", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: Binding(
                get: { transactionToDelete != nil },
                set: { if !$0 { transactionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let id = transactionToDelete?.id else { return }
                transactionToDelete = nil
                Task { await model.deleteTransaction(id: id) }
            }
            Button("Cancel", role: .cancel) { transactionToDelete = nil }
        } message: {
            Text("This transaction will move to Recently deleted and stop affecting balances.")
        }
        .sheet(item: $composer, onDismiss: { editingTransaction = nil }) { selection in
            switch selection {
            case .wallet:
                WalletEntrySheet(
                    title: "Add a wallet",
                    buttonTitle: "Save wallet",
                    currencyCode: model.currencyCode,
                    walletTypes: model.walletTypeOptions
                ) { name, typeName, opening in
                    await model.addWallet(name: name, typeName: typeName, openingBalance: opening)
                }
            case .transaction:
                TransactionEntrySheet(
                    wallets: model.snapshot.activeWallets,
                    categories: model.snapshot.categories,
                    incomeSources: model.snapshot.incomeSources,
                    expenses: refundSourceExpenses,
                    currencyCode: model.currencyCode,
                    existingTransaction: editingTransaction
                ) { existingTransaction, typeName, amount, fee, walletId, destinationWalletId, categoryId, incomeSourceId, linkedTransactionId, adjustmentNegative, note in
                    await model.record(
                        existingTransaction: existingTransaction,
                        typeName: typeName,
                        amount: amount,
                        fee: fee,
                        walletId: walletId,
                        destinationWalletId: destinationWalletId,
                        categoryId: categoryId,
                        incomeSourceId: incomeSourceId,
                        linkedTransactionId: linkedTransactionId,
                        adjustmentNegative: adjustmentNegative,
                        note: note
                    )
                }
            }
        }
        .sheet(isPresented: $isPrivacyStatusPresented) {
            privacyStatusSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isCategoryManagementPresented) {
            CategoryManagementSheet(
                categories: model.snapshot.categories,
                isSaving: model.isSaving,
                onSave: { category, name, icon, colorHex, typeName in
                    if let category {
                        return await model.updateCategory(
                            id: category.id,
                            name: name,
                            icon: icon,
                            colorHex: colorHex
                        )
                    }
                    return await model.addCategory(
                        name: name,
                        typeName: typeName,
                        icon: icon,
                        colorHex: colorHex
                    )
                },
                onArchive: { category, archived in
                    await model.setCategoryArchived(id: category.id, archived: archived)
                },
                onMove: { category, direction in
                    await model.moveCategory(id: category.id, direction: direction)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isIncomeSourceManagementPresented) {
            IncomeSourceManagementSheet(
                sources: model.snapshot.incomeSources,
                kinds: model.incomeSourceKinds,
                isSaving: model.isSaving,
                onSave: { source, name, kindName in
                    if let source {
                        return await model.updateIncomeSource(id: source.id, name: name, kindName: kindName)
                    }
                    return await model.addIncomeSource(name: name, kindName: kindName)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isGoalManagementPresented) {
            GoalManagementSheet(
                goals: model.snapshot.goals,
                contributions: model.snapshot.goalContributions,
                wallets: model.snapshot.activeWallets,
                currencyCode: model.currencyCode,
                balancesHidden: balancesHidden,
                isSaving: model.isSaving,
                formatted: { model.formatted($0) },
                inputAmount: { model.inputAmount(from: $0) },
                onSave: { goal, name, targetAmount, targetDate, linkedWalletId, priority, note in
                    await model.saveGoal(
                        id: goal?.id,
                        name: name,
                        targetAmount: targetAmount,
                        targetDate: targetDate,
                        linkedWalletId: linkedWalletId,
                        priority: priority,
                        note: note,
                        icon: goal?.icon ?? "savings"
                    )
                },
                onContribute: { goal, amount, walletId, note in
                    await model.contributeToGoal(
                        goalId: goal.id,
                        amount: amount,
                        fromWalletId: walletId,
                        note: note
                    )
                },
                onArchive: { goal, archived in
                    await model.setGoalArchived(id: goal.id, archived: archived)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isInvestmentManagementPresented) {
            InvestmentManagementView(
                investments: model.snapshot.investments,
                summary: model.snapshot.investmentSummary,
                assetTypes: model.investmentAssetTypes,
                currencyCode: model.currencyCode,
                balancesHidden: balancesHidden,
                isSaving: model.isSaving,
                formatted: { model.formatted($0) },
                inputAmount: { model.inputAmount(from: $0) },
                onSave: { investment, name, provider, assetTypeName, costBasis, currentValue, valuationDate, note in
                    await model.saveInvestmentHolding(
                        id: investment?.id,
                        name: name,
                        provider: provider,
                        assetTypeName: assetTypeName,
                        costBasis: costBasis,
                        currentValue: currentValue,
                        valuationDate: valuationDate,
                        note: note
                    )
                },
                onArchive: { investment, archived in
                    await model.setInvestmentHoldingArchived(id: investment.id, archived: archived)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isCommitmentManagementPresented) {
            CommitmentManagementView(
                commitments: model.snapshot.commitments,
                progress: model.commitmentProgress,
                payments: model.snapshot.commitmentPayments,
                transactions: model.snapshot.transactions,
                categories: model.snapshot.categories,
                currencyOptions: model.currencyOptions,
                workspaceCurrencyCode: model.currencyCode,
                balancesHidden: balancesHidden,
                isSaving: model.isSaving,
                formatted: { amount, code in model.formatted(amount, currencyCode: code) },
                inputAmount: { amount, code in model.inputAmount(from: amount, currencyCode: code) },
                loadExchangeRate: { base, quote, force in
                    if force {
                        return try await model.refreshExchangeRate(baseCurrencyCode: base, quoteCurrencyCode: quote)
                    }
                    return try await model.loadExchangeRate(baseCurrencyCode: base, quoteCurrencyCode: quote)
                },
                onSave: { commitment, name, amount, targetCurrency, rate, dueDate, categoryId in
                    await model.saveCommitment(
                        id: commitment?.id,
                        name: name,
                        amount: amount,
                        targetCurrencyCode: targetCurrency,
                        exchangeRate: rate,
                        dueDate: dueDate,
                        categoryId: categoryId,
                        reminderDaysBefore: 0
                    )
                },
                onArchive: { commitment, archived in
                    await model.setCommitmentArchived(id: commitment.id, archived: archived)
                },
                onDelete: { commitment in await model.deleteCommitment(id: commitment.id) },
                onLinkExpense: { commitment, expense in
                    await model.linkExpenseToCommitment(commitmentId: commitment.id, transactionId: expense.id)
                },
                onUnlinkPayment: { payment in await model.unlinkCommitmentPayment(id: payment.id) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isAppLockSettingsPresented) {
            IOSAppLockSettingsView(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func retryProtectedStorage() {
        Task {
            await model.retryProtectedStorage()
            if !model.isLocked && model.isStorageAvailable {
                isPrivacyShieldVisible = false
            }
        }
    }

    private func clearSensitiveViewState() {
        selectedTab = .home
        composer = nil
        editingTransaction = nil
        transactionToDelete = nil
        isPrivacyStatusPresented = false
        isCategoryManagementPresented = false
        isIncomeSourceManagementPresented = false
        isGoalManagementPresented = false
        isInvestmentManagementPresented = false
        isAppLockSettingsPresented = false
        balancesHidden = true
        activitySearchQuery = ""
        appliedActivitySearchQuery = ""
        activitySearchIndex = nil
        matchingActivityTransactions = []
    }

    @ViewBuilder
    private var pageContent: some View {
        if model.isLoading {
            ProgressView("Opening secure local storage…")
                .tint(MizaniColors.teal)
                .frame(maxWidth: .infinity, minHeight: 220)
        } else if !model.isStorageAvailable {
            emptyPage(
                title: "Secure storage unavailable",
                message: "Mizani could not safely open the local ledger. No new records can be saved. Check the device passcode and try again."
            )
        } else if model.snapshot.workspace == nil {
            IOSFirstRunView(model: model)
        } else {
            switch selectedTab {
            case .home:
                homeContent
            case .activity:
                activityContent
            case .insights:
                insightsContent
            case .more:
                moreContent
            }
        }
    }

    private var insightsContent: some View {
        let summary = model.currentMonthInsightsSummary
        let categories: [IOSInsightCategory] = summary.map { summary in
            (0..<Int(summary.categoryCount())).compactMap { index in
                guard let total = summary.categoryAt(index: Int32(index)) else { return nil }
                let category = model.snapshot.categories.first(where: { $0.id == total.categoryId })
                let fallbackName = total.categoryId == IosFinanceRules.shared.feesCategoryId()
                    ? "Fees"
                    : "Uncategorised"
                return IOSInsightCategory(
                    id: total.categoryId,
                    name: category?.name ?? fallbackName,
                    colorHex: category?.colorHex ?? "#6D6D6D",
                    amountMinor: total.amountMinor
                )
            }
        } ?? []

        return VStack(alignment: .leading, spacing: 20) {
            pageTitle("Your insights")

            if model.snapshot.workspace == nil {
                emptyCard("Create a wallet and record activity to see your monthly cash flow.", symbol: "chart.bar.xaxis")
            } else if let summary {
                Text(Date().formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MizaniColors.muted)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    insightMetric("Income", amountMinor: summary.incomeMinor)
                    insightMetric("Spending", amountMinor: summary.expenseMinor)
                    insightMetric("Net cash flow", amountMinor: summary.netMinor)
                    insightMetric("Fees", amountMinor: summary.feesMinor)
                    insightMetric("Refunds", amountMinor: summary.refundsMinor)
                }

                Text("Based on posted records for this month. Spending includes recorded fees and refunds; transfers and balance adjustments do not count as income or purchase amounts.")
                    .font(.system(size: 13))
                    .foregroundStyle(MizaniColors.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Spending by category", trailing: "\(categories.count)")
                    if categories.isEmpty {
                        emptyCard("No spending is recorded for this month.", symbol: "chart.pie")
                    } else {
                        ForEach(categories) { category in
                            insightCategoryRow(category)
                        }
                    }
                }
            } else {
                emptyCard(
                    "Insights could not safely summarize these records. Review Activity and edit or remove an unsupported entry.",
                    symbol: "exclamationmark.triangle"
                )
            }
        }
    }

    private func insightMetric(_ title: String, amountMinor: Int64) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(MizaniColors.muted)
            Text("\(model.currencyCode) \(model.formatted(amountMinor))")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(15)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(model.currencyCode) \(model.formatted(amountMinor))")
    }

    private func insightCategoryRow(_ category: IOSInsightCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: IOSCategoryAppearance.symbol(for: model.snapshot.categories.first(where: { $0.id == category.id })?.icon ?? "category"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IOSCategoryAppearance.color(for: category.colorHex))
                .frame(width: 38, height: 38)
                .background(IOSCategoryAppearance.color(for: category.colorHex).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text(category.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MizaniColors.ink)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text("\(model.currencyCode) \(model.formatted(category.amountMinor))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(13)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.name), net spending \(model.currencyCode) \(model.formatted(category.amountMinor))")
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                Circle().fill(MizaniColors.teal)
                Text("M")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .offset(y: -1)
                Circle().fill(MizaniColors.gold).frame(width: 6, height: 6).offset(y: -8)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Mizani")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MizaniColors.ink)
                Text("Your money, in balance.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MizaniColors.muted)
            }

            Spacer()

            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(MizaniColors.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(MizaniColors.teal.opacity(0.09), in: Capsule())
                .accessibilityLabel("iOS development preview")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Your money,\nin balance.")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(MizaniColors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A private place to organize the financial details you choose to record.")
                    .font(.system(size: 16))
                    .foregroundStyle(MizaniColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            balanceCard

            if model.snapshot.workspace == nil {
                emptyCard("Complete the first-run setup to create your workspace.", symbol: "wallet.pass.fill")
            } else {
                HStack(spacing: 12) {
                    actionButton(title: "Add wallet", symbol: "plus") { composer = .wallet }
                    actionButton(title: "Add activity", symbol: "arrow.left.arrow.right") { composer = .transaction }
                }
                walletSection(limit: 3)
                recentActivitySection
            }
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("CURRENT VALUE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(MizaniColors.muted)
                Spacer()
                Button {
                    balancesHidden.toggle()
                } label: {
                    Image(systemName: balancesHidden ? "eye.slash" : "eye")
                        .foregroundStyle(MizaniColors.teal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(balancesHidden ? "Show balances" : "Hide balances")
            }
            Text(balanceText)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
                .accessibilityLabel(balancesHidden ? "Balance hidden" : "Current balance \(balanceText)")
            Text(model.snapshot.activeWallets.isEmpty ? "Add a wallet to see your total here." : "Across your active wallets")
                .font(.system(size: 14))
                .foregroundStyle(MizaniColors.muted)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private var balanceText: String {
        guard !balancesHidden else { return "••••••" }
        guard let total = model.snapshot.totalBalanceMinor else { return "—" }
        return "\(model.currencyCode) \(model.formatted(total))"
    }

    private func walletSection(limit: Int? = nil) -> some View {
        let wallets = Array(model.snapshot.activeWallets.prefix(limit ?? Int.max))
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Your wallets", trailing: "\(model.snapshot.activeWallets.count)")
            if wallets.isEmpty {
                emptyCard("Your wallets will appear here after setup.", symbol: "wallet.pass")
            } else {
                ForEach(wallets, id: \.id) { wallet in
                    HStack(spacing: 13) {
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(MizaniColors.teal)
                            .frame(width: 40, height: 40)
                            .background(MizaniColors.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(wallet.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(MizaniColors.ink)
                            Text(wallet.typeName.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.system(size: 12)).foregroundStyle(MizaniColors.muted)
                        }
                        Spacer()
                        Text(walletBalanceText(wallet))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(MizaniColors.ink)
                    }
                    .padding(14)
                    .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
                }
            }
        }
    }

    private func walletBalanceText(_ wallet: IOSWalletRecord) -> String {
        guard !balancesHidden else { return "Hidden" }
        guard let balance = model.snapshot.walletBalancesMinor[wallet.id] else { return "—" }
        return "\(wallet.currencyCode) \(model.formatted(balance, currencyCode: wallet.currencyCode))"
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Recent activity", trailing: "\(model.snapshot.activeTransactions.count)")
            if model.snapshot.activeTransactions.isEmpty {
                emptyCard("Your saved income, expenses, and transfers will appear here.", symbol: "arrow.left.arrow.right")
            } else {
                ForEach(Array(model.snapshot.activeTransactions.prefix(4)), id: \.id) { transaction in
                    transactionRow(transaction)
                }
            }
        }
    }

    private var refundSourceExpenses: [IOSTransactionRecord] {
        var expenses = Array(model.snapshot.activeTransactions.filter { $0.typeName == "EXPENSE" }.prefix(20))
        if let linkedId = editingTransaction?.linkedTransactionId,
           !expenses.contains(where: { $0.id == linkedId }),
           let existingSource = model.snapshot.transactions.first(where: { $0.id == linkedId }) {
            expenses.append(existingSource)
        }
        return expenses
    }

    private var activityContent: some View {
        let visibleActivityTransactions = activitySearchIndex == nil
            ? model.snapshot.activeTransactions
            : matchingActivityTransactions
        let hasSearchQuery = !activitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return LazyVStack(alignment: .leading, spacing: 18) {
            pageTitle("Your activity")
            if model.snapshot.workspace != nil {
                actionButton(title: "Add activity", symbol: "plus") { composer = .transaction }
                if model.snapshot.activeTransactions.isEmpty && !hasSearchQuery {
                    emptyCard("Your saved income, expenses, and transfers will appear here.", symbol: "arrow.left.arrow.right")
                } else {
                    activitySearchField
                    sectionHeading("Transactions", trailing: "\(visibleActivityTransactions.count)")
                    if visibleActivityTransactions.isEmpty {
                        emptyCard("No activity matches this search. Try another search.", symbol: "magnifyingglass")
                    } else {
                        ForEach(visibleActivityTransactions, id: \.id) { transaction in
                            transactionRow(transaction)
                        }
                    }
                }
            } else {
                emptyCard("Create a wallet before recording activity.", symbol: "wallet.pass")
            }
            recentlyDeletedSection
        }
        .onAppear(perform: rebuildActivitySearchIndex)
        .onChange(of: model.snapshot) { _ in rebuildActivitySearchIndex() }
        .onChange(of: appliedActivitySearchQuery) { _ in filterActivityTransactions() }
        .task(id: activitySearchQuery) {
            let query = activitySearchQuery
            if query.isEmpty {
                appliedActivitySearchQuery = ""
                return
            }
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
            } catch {
                return
            }
            appliedActivitySearchQuery = query
        }
    }

    private var activitySearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MizaniColors.muted)
                .accessibilityHidden(true)
            TextField("Search note, wallet, category", text: $activitySearchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search activity")
                .accessibilityHint("Search notes, transaction types, wallets, categories, amounts, and currencies.")
            if !activitySearchQuery.isEmpty {
                Button {
                    activitySearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MizaniColors.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear activity search")
            }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func rebuildActivitySearchIndex() {
        activitySearchIndex = IOSActivitySearchIndex(
            snapshot: model.snapshot,
            normalizeSearchText: { text in
                ActivitySearchRules.shared.normalizeSearchText(text: text)
            },
            containsNormalized: { searchableText, query in
                ActivitySearchRules.shared.containsNormalized(
                    searchableText: searchableText,
                    normalizedQuery: query
                )
            }
        )
        filterActivityTransactions()
    }

    private func filterActivityTransactions() {
        guard let activitySearchIndex else {
            matchingActivityTransactions = model.snapshot.activeTransactions
            return
        }
        matchingActivityTransactions = activitySearchIndex.matchingTransactions(
            model.snapshot.activeTransactions,
            query: appliedActivitySearchQuery
        )
    }

    private var recentlyDeletedSection: some View {
        let deleted = Array(model.snapshot.deletedTransactions.prefix(20))
        return Group {
            if !deleted.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("Recently deleted", trailing: "\(model.snapshot.deletedTransactions.count)")
                    ForEach(deleted, id: \.id) { transaction in
                        VStack(alignment: .leading, spacing: 8) {
                            transactionRow(transaction, actionsEnabled: false)
                            Button {
                                Task { await model.restoreTransaction(id: transaction.id) }
                            } label: {
                                Label("Restore transaction", systemImage: "arrow.uturn.backward")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .disabled(model.isSaving)
                            .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private func transactionRow(_ transaction: IOSTransactionRecord, actionsEnabled: Bool = true) -> some View {
        let isIncome = transaction.typeName == "INCOME"
        let isTransfer = transaction.typeName == "TRANSFER"
        let isRefund = transaction.typeName == "REFUND"
        let isAdjustment = transaction.typeName == "ADJUSTMENT"
        let categoryName = model.snapshot.categories.first(where: { $0.id == transaction.categoryId })?.name ?? "Uncategorized"
        let typeLabel = isIncome ? "Income" : (isTransfer ? "Transfer" : (isRefund ? "Refund" : (isAdjustment ? "Adjustment" : "Expense")))
        let detail: String
        if isTransfer {
            let destination = walletName(transaction.destinationWalletId ?? "")
            let feeSuffix = transaction.feeMinor > 0
                ? "; fee \(transaction.currencyCode) \(model.formatted(transaction.feeMinor, currencyCode: transaction.currencyCode))"
                : ""
            detail = "Transfer: \(walletName(transaction.walletId)) to \(destination)\(feeSuffix)"
        } else if isRefund {
            let feeSuffix = transaction.feeMinor > 0
                ? "; fee \(transaction.currencyCode) \(model.formatted(transaction.feeMinor, currencyCode: transaction.currencyCode))"
                : ""
            detail = "Refund | \(categoryName) | \(walletName(transaction.walletId))\(feeSuffix)"
        } else if isAdjustment {
            detail = "Balance adjustment | \(walletName(transaction.walletId))"
        } else {
            let feeSuffix = transaction.feeMinor > 0
                ? "; fee \(transaction.currencyCode) \(model.formatted(transaction.feeMinor, currencyCode: transaction.currencyCode))"
                : ""
            detail = "\(typeLabel) | \(categoryName) | \(walletName(transaction.walletId))\(feeSuffix)"
        }
        let isPositive = isIncome || isRefund || (isAdjustment && transaction.amountMinor >= 0)
        let accent = isIncome || isRefund ? MizaniColors.teal : (isTransfer ? MizaniColors.gold : MizaniColors.muted)
        let content = HStack(spacing: 13) {
            Image(systemName: isIncome ? "arrow.down.left" : (isTransfer ? "arrow.left.arrow.right" : (isRefund ? "arrow.uturn.backward" : (isAdjustment ? "slider.horizontal.3" : "arrow.up.right"))))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note.isEmpty ? typeLabel : transaction.note)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MizaniColors.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 12)).foregroundStyle(MizaniColors.muted)
            }
            Spacer(minLength: 8)
            Text(transactionAmountText(transaction, isPositive: isPositive))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isPositive ? MizaniColors.teal : (isAdjustment ? MizaniColors.muted : MizaniColors.ink))
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)

        return HStack(spacing: 8) {
            content
            if actionsEnabled {
                Menu {
                    Button {
                        editingTransaction = transaction
                        composer = .transaction
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        transactionToDelete = transaction
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MizaniColors.muted)
                        .frame(width: 32, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Actions for \(transaction.note.isEmpty ? typeLabel : transaction.note)")
                .disabled(model.isSaving)
            }
        }
        .padding(14)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func walletName(_ id: String) -> String {
        model.snapshot.wallets.first(where: { $0.id == id })?.name ?? "Wallet"
    }

    private func transactionAmountText(_ transaction: IOSTransactionRecord, isPositive: Bool) -> String {
        guard !balancesHidden else { return "Hidden" }
        let magnitude = transaction.amountMinor == Int64.min ? Int64.max : abs(transaction.amountMinor)
        return "\(isPositive ? "+" : "-")\(transaction.currencyCode) \(model.formatted(magnitude, currencyCode: transaction.currencyCode))"
    }
    private var moreContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("More")
            Button {
                isPrivacyStatusPresented = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "hand.raised.fill").foregroundStyle(MizaniColors.teal)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy status").font(.system(size: 15, weight: .semibold)).foregroundStyle(MizaniColors.ink)
                        Text("What this preview stores and what is still being built")
                            .font(.system(size: 13)).foregroundStyle(MizaniColors.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(MizaniColors.muted)
                }
                .padding(18)
                .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
            }
            .buttonStyle(.plain)

            actionButton(
                title: model.appLockEnabled ? "App lock settings" : "Set up app lock",
                symbol: model.appLockEnabled ? "lock.fill" : "lock.open"
            ) {
                isAppLockSettingsPresented = true
            }

            if model.snapshot.workspace != nil {
                actionButton(title: "Manage categories", symbol: "square.grid.2x2") {
                    isCategoryManagementPresented = true
                }
                actionButton(title: "Manage savings goals", symbol: "target") {
                    isGoalManagementPresented = true
                }
                actionButton(title: "Manage investments", symbol: "chart.line.uptrend.xyaxis") {
                    isInvestmentManagementPresented = true
                }
                actionButton(title: "Manage commitments", symbol: "calendar.badge.clock") {
                    isCommitmentManagementPresented = true
                }
                actionButton(title: "Manage income sources", symbol: "banknote.fill") {
                    isIncomeSourceManagementPresented = true
                }
                walletSection()
                actionButton(title: "Add wallet", symbol: "plus") { composer = .wallet }
            }
        }
        .padding(14)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func actionCard(symbol: String, title: String, message: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(MizaniColors.teal)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(MizaniColors.ink)
            Text(message).font(.system(size: 14)).foregroundStyle(MizaniColors.muted).fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(MizaniColors.teal, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func actionButton(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MizaniColors.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(MizaniColors.card, in: Capsule())
                .overlay { Capsule().stroke(MizaniColors.line, lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }

    private func sectionHeading(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(MizaniColors.ink)
            Spacer()
            Text(trailing).font(.system(size: 12, weight: .semibold)).foregroundStyle(MizaniColors.muted)
        }
    }

    private func pageTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 29, weight: .bold, design: .rounded))
            .foregroundStyle(MizaniColors.ink)
    }

    private func emptyCard(_ message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(MizaniColors.teal)
                .accessibilityHidden(true)
            Text(message).font(.system(size: 14)).foregroundStyle(MizaniColors.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }
    }

    private func emptyPage(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle(title)
            emptyCard(message, symbol: "leaf")
        }
    }

    private var previewStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hammer.fill").foregroundStyle(MizaniColors.teal).accessibilityHidden(true)
            Text("Development preview. iOS storage and security have not been verified on Apple hardware. Use test data only while feature parity is being built.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MizaniColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MizaniTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol).font(.system(size: 17, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? MizaniColors.teal : MizaniColors.muted)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(MizaniColors.line).frame(height: 1) }
    }

    private var privacyStatusSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Privacy status")
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
            Text("This development build includes encrypted local storage, an on-device app PIN with optional biometric unlock, and initial wallet and activity entry. App lock, storage protection, and finance flows have not been verified on an Apple device. Backup and restore, exports, and full Android feature parity are not yet available. It makes no account or sync connection. Use test data only.")
                .font(.system(size: 15))
                .foregroundStyle(MizaniColors.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MizaniColors.page.ignoresSafeArea())
    }
}

private struct GoalManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goals: [IOSGoalRecord]
    let contributions: [IOSGoalContributionRecord]
    let wallets: [IOSWalletRecord]
    let currencyCode: String
    let balancesHidden: Bool
    let isSaving: Bool
    let formatted: (Int64) -> String
    let inputAmount: (Int64) -> String
    let onSave: (IOSGoalRecord?, String, String, Date?, String?, Int, String) async -> Bool
    let onContribute: (IOSGoalRecord, String, String?, String) async -> Bool
    let onArchive: (IOSGoalRecord, Bool) async -> Bool

    @State private var showArchived = false
    @State private var editingGoal: IOSGoalRecord?
    @State private var isGoalEditorPresented = false
    @State private var contributingGoal: IOSGoalRecord?

    private var visibleGoals: [IOSGoalRecord] {
        goals.filter { !$0.deleted && (showArchived ? $0.archived : !$0.archived) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show archived goals", isOn: $showArchived)
                        .tint(MizaniColors.teal)
                }

                if visibleGoals.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(showArchived ? "No archived goals" : "No savings goals yet", systemImage: "target")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(MizaniColors.ink)
                            Text(showArchived ? "Archived goals will appear here." : "Create a goal to track progress toward a savings target.")
                                .font(.system(size: 13))
                                .foregroundStyle(MizaniColors.muted)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section(showArchived ? "Archived" : "Your goals") {
                        ForEach(visibleGoals) { goal in
                            goalRow(goal)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MizaniColors.page)
            .navigationTitle("Savings goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        editingGoal = nil
                        isGoalEditorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add savings goal")
                    .disabled(isSaving || showArchived)
                }
            }
            .sheet(isPresented: $isGoalEditorPresented) {
                GoalEditorSheet(
                    goal: editingGoal,
                    wallets: wallets,
                    currencyCode: currencyCode,
                    balancesHidden: balancesHidden,
                    inputAmount: inputAmount,
                    isSaving: isSaving,
                    onSave: onSave
                )
            }
            .sheet(item: $contributingGoal) { goal in
                GoalContributionSheet(
                    goal: goal,
                    wallets: wallets,
                    currencyCode: currencyCode,
                    balancesHidden: balancesHidden,
                    formatted: formatted,
                    isSaving: isSaving,
                    onContribute: onContribute
                )
            }
        }
    }

    @ViewBuilder
    private func goalRow(_ goal: IOSGoalRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "target")
                    .foregroundStyle(MizaniColors.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(goal.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(MizaniColors.ink)
                    if balancesHidden {
                        Text("Goal amounts hidden")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MizaniColors.muted)
                    } else {
                        Text("\(formatted(goal.allocatedMinor)) saved of \(formatted(goal.targetMinor))")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MizaniColors.muted)
                    }
                    let contributionCount = contributions.filter { $0.goalId == goal.id }.count
                    if contributionCount > 0 {
                        Text("\(contributionCount) contributions")
                            .font(.system(size: 12))
                            .foregroundStyle(MizaniColors.muted)
                    }
                    if let walletId = goal.linkedWalletId,
                       let wallet = wallets.first(where: { $0.id == walletId }) {
                        Text("Linked to \(wallet.name)")
                            .font(.system(size: 12))
                            .foregroundStyle(MizaniColors.muted)
                    }
                    if !goal.note.isEmpty {
                        Text(goal.note)
                            .font(.system(size: 12))
                            .foregroundStyle(MizaniColors.muted)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                if !goal.archived {
                    Button("Contribute") { contributingGoal = goal }
                        .buttonStyle(.borderedProminent)
                        .tint(MizaniColors.teal)
                    Button("Edit") {
                        editingGoal = goal
                        isGoalEditorPresented = true
                    }
                    .buttonStyle(.bordered)
                    .tint(MizaniColors.teal)
                }
                Button(goal.archived ? "Restore" : "Archive") {
                    Task { _ = await onArchive(goal, !goal.archived) }
                }
                .buttonStyle(.bordered)
                .tint(goal.archived ? MizaniColors.teal : MizaniColors.muted)
            }
            .font(.system(size: 13, weight: .semibold))
            .disabled(isSaving)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct GoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goal: IOSGoalRecord?
    let wallets: [IOSWalletRecord]
    let currencyCode: String
    let balancesHidden: Bool
    let inputAmount: (Int64) -> String
    let isSaving: Bool
    let onSave: (IOSGoalRecord?, String, String, Date?, String?, Int, String) async -> Bool

    @State private var name: String
    @State private var targetAmount: String
    @State private var linkedWalletId: String
    @State private var note: String
    @State private var priority: Int
    @State private var hasTargetDate: Bool
    @State private var targetDate: Date
    @State private var isTargetAmountRevealed: Bool
    @State private var isSubmitting = false

    init(
        goal: IOSGoalRecord?,
        wallets: [IOSWalletRecord],
        currencyCode: String,
        balancesHidden: Bool,
        inputAmount: @escaping (Int64) -> String,
        isSaving: Bool,
        onSave: @escaping (IOSGoalRecord?, String, String, Date?, String?, Int, String) async -> Bool
    ) {
        self.goal = goal
        self.wallets = wallets
        self.currencyCode = currencyCode
        self.balancesHidden = balancesHidden
        self.inputAmount = inputAmount
        self.isSaving = isSaving
        self.onSave = onSave
        _name = State(initialValue: goal?.name ?? "")
        _targetAmount = State(initialValue: goal.map { inputAmount($0.targetMinor) } ?? "")
        _linkedWalletId = State(initialValue: goal?.linkedWalletId ?? "")
        _note = State(initialValue: goal?.note ?? "")
        _priority = State(initialValue: goal?.priority ?? 2)
        _hasTargetDate = State(initialValue: goal?.targetEpochDay != nil)
        _targetDate = State(initialValue: goal?.targetEpochDay.map { Self.date(forEpochDay: $0) } ?? Date())
        _isTargetAmountRevealed = State(initialValue: !balancesHidden || goal == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Savings goal name")
                    if goal != nil && balancesHidden && !isTargetAmountRevealed {
                        HStack {
                            Text("Target amount")
                            Spacer()
                            Text("Hidden").foregroundStyle(MizaniColors.muted)
                        }
                        Button("Reveal and edit target") { isTargetAmountRevealed = true }
                    } else {
                        TextField("Target amount (\(currencyCode))", text: $targetAmount)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Savings goal target amount")
                    }
                    Picker("Priority", selection: $priority) {
                        Text("High").tag(1)
                        Text("Normal").tag(2)
                        Text("Low").tag(3)
                    }
                }

                Section("Details") {
                    Picker("Linked savings wallet", selection: $linkedWalletId) {
                        Text("No linked wallet").tag("")
                        ForEach(wallets, id: \.id) { wallet in
                            Text(wallet.name).tag(wallet.id)
                        }
                    }
                    Toggle("Set a target date", isOn: $hasTargetDate)
                    if hasTargetDate {
                        DatePicker("Target date", selection: $targetDate, displayedComponents: .date)
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSubmitting = true
                            let saved = await onSave(
                                goal,
                                name,
                                targetAmount,
                                hasTargetDate ? targetDate : nil,
                                linkedWalletId.isEmpty ? nil : linkedWalletId,
                                priority,
                                note
                            )
                            isSubmitting = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(isSaving || isSubmitting || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || targetAmount.isEmpty)
                }
            }
        }
    }

    private static func date(forEpochDay day: Int64) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let epoch = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        return calendar.date(byAdding: .day, value: Int(day), to: epoch) ?? Date()
    }
}

private struct GoalContributionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goal: IOSGoalRecord
    let wallets: [IOSWalletRecord]
    let currencyCode: String
    let balancesHidden: Bool
    let formatted: (Int64) -> String
    let isSaving: Bool
    let onContribute: (IOSGoalRecord, String, String?, String) async -> Bool

    @State private var amount = ""
    @State private var fromWalletId = ""
    @State private var note = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section(goal.name) {
                    if balancesHidden {
                        Text("Goal progress is hidden.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MizaniColors.muted)
                    } else {
                        Text("Current progress: \(formatted(goal.allocatedMinor)) of \(formatted(goal.targetMinor))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(MizaniColors.muted)
                    }
                    TextField("Contribution amount (\(currencyCode))", text: $amount)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Goal contribution amount")
                    Picker("From wallet (optional)", selection: $fromWalletId) {
                        Text("No wallet transfer").tag("")
                        ForEach(wallets, id: \.id) { wallet in
                            Text(wallet.name).tag(wallet.id)
                        }
                    }
                    if let linkedWalletId = goal.linkedWalletId,
                       !fromWalletId.isEmpty,
                       fromWalletId != linkedWalletId {
                        Text("A transfer will be recorded from the selected wallet to the linked savings wallet.")
                            .font(.system(size: 12))
                            .foregroundStyle(MizaniColors.muted)
                    } else {
                        Text("This adds progress to the goal without changing wallet balances.")
                            .font(.system(size: 12))
                            .foregroundStyle(MizaniColors.muted)
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("Add contribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            isSubmitting = true
                            let saved = await onContribute(
                                goal,
                                amount,
                                fromWalletId.isEmpty ? nil : fromWalletId,
                                note
                            )
                            isSubmitting = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(isSaving || isSubmitting || amount.isEmpty)
                }
            }
        }
    }
}

private struct WalletEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Cash"
    @State private var openingBalance = "0"
    @State private var walletTypeName = "CASH"
    @State private var isSaving = false

    let title: String
    let buttonTitle: String
    let currencyCode: String
    let walletTypes: [IOSWalletTypeOption]
    let onSave: (String, String, String) async -> Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Wallet") {
                    Picker("Wallet type", selection: $walletTypeName) {
                        ForEach(walletTypes) { walletType in
                            Text(walletType.label).tag(walletType.name)
                        }
                    }
                    TextField("Wallet name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Wallet name")
                    TextField("Opening balance (\(currencyCode))", text: $openingBalance)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Opening balance in \(currencyCode)")
                }
                Section {
                    Text("The opening balance is stored as an integer amount in \(currencyCode).")
                        .font(.footnote)
                        .foregroundStyle(MizaniColors.muted)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(buttonTitle) {
                        Task {
                            isSaving = true
                            if await onSave(name, walletTypeName, openingBalance) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct IOSFirstRunView: View {
    @ObservedObject var model: MizaniFinanceModel
    @State private var step = 0
    @State private var hasAcknowledgedPreviewLimits = false
    @State private var countryCode: String
    @State private var currencyCode: String
    @State private var walletTypeName = "CASH"
    @State private var walletName = "Cash"
    @State private var openingBalance = ""

    private var selectedCountry: IOSCountryOption? {
        model.countryOptions.first(where: { $0.code == countryCode })
    }

    private var selectedCurrency: IOSCurrencyOption? {
        model.currencyOptions.first(where: { $0.code == currencyCode })
    }

    init(model: MizaniFinanceModel) {
        _model = ObservedObject(wrappedValue: model)
        let countries = model.countryOptions
        let currencies = model.currencyOptions
        let deviceRegion = Locale.current.region?.identifier.uppercased()
        let initialCountry = countries.first(where: { $0.code == deviceRegion })?.code ?? "OT"
        let countryCurrency = countries.first(where: { $0.code == initialCountry })?.currencyCode ?? "USD"
        let deviceCurrency = Locale.current.currency?.identifier.uppercased()
        let supportedDeviceCurrency = deviceCurrency.flatMap { code in
            currencies.contains(where: { $0.code == code }) ? code : nil
        }

        _countryCode = State(initialValue: initialCountry)
        _currencyCode = State(initialValue: initialCountry == "OT" ? (supportedDeviceCurrency ?? countryCurrency) : countryCurrency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(step == 0 ? "WELCOME" : "SET UP YOUR MONEY")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(MizaniColors.teal)
                Spacer()
                Text(step == 0 ? "1 OF 2" : "2 OF 2")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(MizaniColors.muted)
            }

            if step == 0 {
                welcomeStep
            } else {
                setupStep
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: countryCode) { selectedCode in
            guard selectedCode != "OT",
                  let country = model.countryOptions.first(where: { $0.code == selectedCode }) else { return }
            currencyCode = country.currencyCode
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Track every side of your money.")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .foregroundStyle(MizaniColors.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Mizani keeps the records you choose to enter on this device.")
                .font(.system(size: 15))
                .foregroundStyle(MizaniColors.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Label("iOS development preview", systemImage: "iphone.gen3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MizaniColors.ink)
                Text("This preview is incomplete. Backup, restore, exports, and several Android features are not available, and Apple-device security flows have not been verified. Use test data and do not rely on this app as your only financial record.")
                    .font(.system(size: 14))
                    .foregroundStyle(MizaniColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("I understand and will use test data.", isOn: $hasAcknowledgedPreviewLimits)
                    .font(.system(size: 14, weight: .medium))
                    .tint(MizaniColors.teal)
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }

            Button {
                step = 1
            } label: {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(MizaniColors.teal, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!hasAcknowledgedPreviewLimits)
            .opacity(hasAcknowledgedPreviewLimits ? 1 : 0.55)
        }
    }

    private var setupStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button {
                    step = 0
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MizaniColors.teal)
                        .frame(width: 36, height: 36)
                        .background(MizaniColors.teal.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Choose your setup")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(MizaniColors.ink)
                    Text("Choose the currency used for this workspace's totals and planning.")
                        .font(.system(size: 14))
                        .foregroundStyle(MizaniColors.muted)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Picker("Country", selection: $countryCode) {
                    ForEach(model.countryOptions) { country in
                        Text(country.name).tag(country.code)
                    }
                }
                Picker("Primary currency", selection: $currencyCode) {
                    ForEach(model.currencyOptions) { currency in
                        Text("\(currency.code) · \(currency.name)").tag(currency.code)
                    }
                }
                if let selectedCurrency {
                    Text("Workspace totals use \(selectedCurrency.code), with \(selectedCurrency.minorUnits) fractional digits.")
                        .font(.system(size: 12))
                        .foregroundStyle(MizaniColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }

            VStack(alignment: .leading, spacing: 12) {
                Text("YOUR FIRST WALLET")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(MizaniColors.muted)
                Picker("Wallet type", selection: $walletTypeName) {
                    ForEach(model.walletTypeOptions) { walletType in
                        Text(walletType.label).tag(walletType.name)
                    }
                }
                TextField("Wallet name", text: $walletName)
                    .textInputAutocapitalization(.words)
                    .accessibilityLabel("Wallet name")
                TextField("Opening balance (\(currencyCode)) · optional", text: $openingBalance)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("Optional opening balance in \(currencyCode)")
                Text("The opening balance is stored as integer minor units. This preview is designed to use encrypted local storage, but its security behavior has not yet been verified on Apple devices.")
                    .font(.system(size: 12))
                    .foregroundStyle(MizaniColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(15)
            .background(MizaniColors.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(MizaniColors.line, lineWidth: 1) }

            Button {
                Task {
                    guard let selectedCurrency else { return }
                    await model.createFirstWallet(
                        countryCode: selectedCountry?.code ?? "OT",
                        currencyCode: selectedCurrency.code,
                        walletName: walletName,
                        walletTypeName: walletTypeName,
                        openingBalance: openingBalance
                    )
                }
            } label: {
                Text(model.isSaving ? "Preparing your workspace…" : "Create workspace")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(MizaniColors.teal, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(model.isSaving || walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCurrency == nil)
            .opacity(model.isSaving || walletName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
        }
    }
}

private struct TransactionEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var typeName: String
    @State private var amount = ""
    @State private var fee = "0"
    @State private var walletId: String
    @State private var destinationWalletId: String
    @State private var categoryId: String
    @State private var incomeSourceId: String
    @State private var linkedTransactionId = ""
    @State private var adjustmentNegative = false
    @State private var note = ""
    @State private var isSaving = false

    let wallets: [IOSWalletRecord]
    let categories: [IOSCategoryRecord]
    let incomeSources: [IOSIncomeSourceRecord]
    let expenses: [IOSTransactionRecord]
    let currencyCode: String
    let currencyDigits: Int
    let existingTransaction: IOSTransactionRecord?
    let onSave: (IOSTransactionRecord?, String, String, String, String, String, String, String, String, Bool, String) async -> Bool

    init(
        wallets: [IOSWalletRecord],
        categories: [IOSCategoryRecord],
        incomeSources: [IOSIncomeSourceRecord],
        expenses: [IOSTransactionRecord],
        currencyCode: String,
        existingTransaction: IOSTransactionRecord?,
        onSave: @escaping (IOSTransactionRecord?, String, String, String, String, String, String, String, String, Bool, String) async -> Bool
    ) {
        self.wallets = wallets
        self.categories = categories
        self.incomeSources = incomeSources
        self.expenses = expenses
        self.currencyCode = currencyCode
        let digits = max(0, Int(IosFinanceRules.shared.currencyMinorUnits(currencyCode: currencyCode)))
        currencyDigits = digits
        self.existingTransaction = existingTransaction
        self.onSave = onSave
        _typeName = State(initialValue: existingTransaction?.typeName ?? "EXPENSE")
        let amountMinor = existingTransaction?.amountMinor ?? 0
        let amountMagnitude = amountMinor == Int64.min ? Int64.max : abs(amountMinor)
        _amount = State(initialValue: existingTransaction == nil ? "" : Self.inputAmount(amountMagnitude, digits: digits))
        _fee = State(initialValue: existingTransaction == nil ? "0" : Self.inputAmount(existingTransaction?.feeMinor ?? 0, digits: digits))
        _walletId = State(initialValue: existingTransaction?.walletId ?? wallets.first?.id ?? "")
        let alternativeWalletId = wallets.first(where: { $0.id != (existingTransaction?.walletId ?? wallets.first?.id) })?.id ?? ""
        _destinationWalletId = State(initialValue: existingTransaction?.destinationWalletId ?? alternativeWalletId)
        _categoryId = State(initialValue: existingTransaction?.categoryId ?? categories.first(where: {
            $0.typeName == "EXPENSE" && !$0.archived && !$0.deleted
        })?.id ?? "")
        _incomeSourceId = State(initialValue: existingTransaction?.incomeSourceId ?? "")
        _linkedTransactionId = State(initialValue: existingTransaction?.linkedTransactionId ?? "")
        _adjustmentNegative = State(initialValue: existingTransaction?.typeName == "ADJUSTMENT" && amountMinor < 0)
        _note = State(initialValue: existingTransaction?.note ?? "")
    }

    private var categoryTypeName: String {
        typeName == "INCOME" ? "INCOME" : "EXPENSE"
    }

    private static func inputAmount(_ amountMinor: Int64, digits: Int) -> String {
        let scale = Int64((0..<digits).reduce(1) { value, _ in value * 10 })
        let magnitude = amountMinor == Int64.min ? Int64.max : abs(amountMinor)
        let whole = magnitude / scale
        guard digits > 0 else { return String(whole) }
        let rawFraction = String(magnitude % scale)
        let fraction = String(repeating: "0", count: max(0, digits - rawFraction.count)) + rawFraction
        return "\(whole).\(fraction)"
    }

    private var selectableCategories: [IOSCategoryRecord] {
        var available = categories.filter {
            $0.typeName == categoryTypeName && !$0.archived && !$0.deleted
        }
        if let existingCategoryId = existingTransaction?.categoryId,
           let existingCategory = categories.first(where: {
               $0.id == existingCategoryId && $0.typeName == categoryTypeName && !$0.deleted
           }),
           !available.contains(where: { $0.id == existingCategory.id }) {
            available.append(existingCategory)
        }
        return available
    }

    private var amountLabel: String {
        switch typeName {
        case "TRANSFER": return "Amount to move (\(currencyCode))"
        case "REFUND": return "Refund amount (\(currencyCode))"
        case "ADJUSTMENT": return "Adjustment amount (\(currencyCode))"
        default: return "Amount (\(currencyCode))"
        }
    }

    private var needsCategory: Bool {
        typeName == "EXPENSE" || typeName == "INCOME" || typeName == "REFUND"
    }

    private var selectableIncomeSources: [IOSIncomeSourceRecord] {
        var available = incomeSources.filter { !$0.deleted }
        if let existingSourceId = existingTransaction?.incomeSourceId,
           !available.contains(where: { $0.id == existingSourceId }) {
            available.append(
                IOSIncomeSourceRecord(
                    id: existingSourceId,
                    name: "Unavailable source",
                    kindName: "OTHER",
                    archived: true,
                    deleted: true
                )
            )
        }
        return available
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    Picker("Type", selection: $typeName) {
                        Text("Expense").tag("EXPENSE")
                        Text("Income").tag("INCOME")
                        Text("Transfer").tag("TRANSFER")
                        Text("Refund").tag("REFUND")
                        Text("Adjustment").tag("ADJUSTMENT")
                    }
                    if needsCategory {
                        Picker(typeName == "INCOME" ? "Income category" : "Category", selection: $categoryId) {
                            ForEach(selectableCategories, id: \.id) { category in
                                Text(category.archived ? "\(category.name) (Archived)" : category.name)
                                    .tag(category.id)
                            }
                        }
                    }
                    if typeName == "INCOME" {
                        Picker("Income source (optional)", selection: $incomeSourceId) {
                            Text("Not specified").tag("")
                            ForEach(selectableIncomeSources, id: \.id) { source in
                                let label = source.deleted
                                    ? "Unavailable source"
                                    : source.archived ? "\(source.name) (Archived)" : source.name
                                Text(label).tag(source.id)
                            }
                        }
                    }
                    TextField(amountLabel, text: $amount)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel(amountLabel)
                    if typeName == "EXPENSE" || typeName == "TRANSFER" || typeName == "REFUND" {
                        TextField("Fee (\(currencyCode))", text: $fee)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Fee in \(currencyCode)")
                    }
                    if typeName == "ADJUSTMENT" {
                        Picker("Direction", selection: $adjustmentNegative) {
                            Text("Add to wallet").tag(false)
                            Text("Remove from wallet").tag(true)
                        }
                    }
                    if typeName == "REFUND" {
                        Picker("Original expense (optional)", selection: $linkedTransactionId) {
                            Text("No linked expense").tag("")
                            ForEach(expenses, id: \.id) { expense in
                                let label = expense.note.isEmpty
                                    ? "Expense (\(currencyCode) \(Self.inputAmount(expense.amountMinor, digits: currencyDigits)))"
                                    : expense.note
                                Text(expense.deleted ? "\(label) · deleted" : label)
                                    .tag(expense.id)
                            }
                        }
                    }
                    Picker(typeName == "TRANSFER" ? "From wallet" : "Wallet", selection: $walletId) {
                        ForEach(wallets, id: \.id) { wallet in Text(wallet.name).tag(wallet.id) }
                    }
                    if typeName == "TRANSFER" {
                        Picker("To wallet", selection: $destinationWalletId) {
                            ForEach(wallets.filter { $0.id != walletId }, id: \.id) { wallet in
                                Text(wallet.name).tag(wallet.id)
                            }
                        }
                        if wallets.filter({ $0.id != walletId }).isEmpty {
                            Text("Add another wallet before moving money.")
                                .font(.footnote)
                                .foregroundStyle(MizaniColors.muted)
                        }
                    }
                }
                Section("Details") {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .navigationTitle(sheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: typeName) { newType in
                if newType != "INCOME" { incomeSourceId = "" }
                if newType == "EXPENSE" || newType == "INCOME" || newType == "REFUND" {
                    let categoryType = newType == "INCOME" ? "INCOME" : "EXPENSE"
                    categoryId = categories.first(where: {
                        $0.typeName == categoryType && !$0.archived && !$0.deleted
                    })?.id ?? ""
                } else {
                    categoryId = ""
                }
            }
            .onChange(of: linkedTransactionId) { linkedId in
                guard !linkedId.isEmpty,
                      let expense = expenses.first(where: { $0.id == linkedId }),
                      let linkedCategoryId = expense.categoryId,
                      categories.contains(where: {
                          $0.id == linkedCategoryId && $0.typeName == "EXPENSE" && !$0.archived && !$0.deleted
                      }) else { return }
                categoryId = linkedCategoryId
            }
            .onChange(of: walletId) { newWalletId in
                if destinationWalletId == newWalletId {
                    destinationWalletId = wallets.first(where: { $0.id != newWalletId })?.id ?? ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        Task {
                            isSaving = true
                            if await onSave(
                                existingTransaction,
                                typeName,
                                amount,
                                typeName == "EXPENSE" || typeName == "TRANSFER" || typeName == "REFUND" ? fee : "0",
                                walletId,
                                destinationWalletId,
                                categoryId,
                                incomeSourceId,
                                linkedTransactionId,
                                adjustmentNegative,
                                note
                            ) {
                                dismiss()
                            }
                            isSaving = false
                        }
                    }
                    .disabled(
                        isSaving || wallets.isEmpty || walletId.isEmpty ||
                            (typeName == "TRANSFER" && destinationWalletId.isEmpty) ||
                            (needsCategory && categoryId.isEmpty)
                    )
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var sheetTitle: String {
        if existingTransaction != nil {
            return "Edit \(typeName.lowercased().replacingOccurrences(of: "_", with: " "))"
        }
        switch typeName {
        case "TRANSFER": return "Move money"
        case "REFUND": return "Add refund"
        case "ADJUSTMENT": return "Adjust balance"
        case "INCOME": return "Add income"
        default: return "Add expense"
        }
    }

    private var saveTitle: String {
        if existingTransaction != nil { return "Save changes" }
        switch typeName {
        case "TRANSFER": return "Move money"
        case "REFUND": return "Save refund"
        case "ADJUSTMENT": return "Save adjustment"
        default: return "Save"
        }
    }
}

private typealias IncomeSourceSaveAction = (
    IOSIncomeSourceRecord?,
    String,
    String
) async -> Bool

private struct IncomeSourceManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editingSource: IOSIncomeSourceRecord?
    @State private var isEditorPresented = false

    let sources: [IOSIncomeSourceRecord]
    let kinds: [IOSIncomeSourceKind]
    let isSaving: Bool
    let onSave: IncomeSourceSaveAction

    private var availableSources: [IOSIncomeSourceRecord] {
        sources.filter { !$0.deleted }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if availableSources.isEmpty {
                        Text("Add a source to label salary, business, remittance, or other income.")
                            .font(.subheadline)
                            .foregroundStyle(MizaniColors.muted)
                    }
                    ForEach(availableSources, id: \.id) { source in
                        Button {
                            editingSource = source
                            isEditorPresented = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "banknote.fill")
                                    .foregroundStyle(MizaniColors.teal)
                                    .frame(width: 38, height: 38)
                                    .background(MizaniColors.teal.opacity(0.10), in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(MizaniColors.ink)
                                    Text(kinds.first(where: { $0.name == source.kindName })?.label ?? "Other")
                                        .font(.system(size: 12))
                                        .foregroundStyle(MizaniColors.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(MizaniColors.muted)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .accessibilityHint("Edit this income source")
                    }
                } header: {
                    Text("Income sources")
                } footer: {
                    Text("Changing a source name or type keeps past income linked to the same source.")
                }
            }
            .navigationTitle("Income sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        editingSource = nil
                        isEditorPresented = true
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $isEditorPresented, onDismiss: { editingSource = nil }) {
                IncomeSourceEditorSheet(
                    source: editingSource,
                    kinds: kinds,
                    isSaving: isSaving,
                    onSave: onSave
                )
            }
        }
    }
}

private struct IncomeSourceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kindName: String

    let source: IOSIncomeSourceRecord?
    let kinds: [IOSIncomeSourceKind]
    let isSaving: Bool
    let onSave: IncomeSourceSaveAction

    init(
        source: IOSIncomeSourceRecord?,
        kinds: [IOSIncomeSourceKind],
        isSaving: Bool,
        onSave: @escaping IncomeSourceSaveAction
    ) {
        self.source = source
        self.kinds = kinds
        self.isSaving = isSaving
        self.onSave = onSave
        _name = State(initialValue: source?.name ?? "")
        _kindName = State(initialValue: source?.kindName ?? kinds.first?.name ?? "OTHER")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Source name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Income source name")
                    Picker("Type", selection: $kindName) {
                        ForEach(kinds, id: \.name) { kind in
                            Text(kind.label).tag(kind.name)
                        }
                    }
                }
            }
            .navigationTitle(source == nil ? "Add income source" : "Edit income source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(source == nil ? "Add" : "Save") {
                        Task {
                            if await onSave(source, name, kindName) { dismiss() }
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || kinds.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private typealias CategorySaveAction = (
    IOSCategoryRecord?,
    String,
    String,
    String,
    String
) async -> Bool

private struct CategoryManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var typeName = "EXPENSE"
    @State private var editingCategory: IOSCategoryRecord?
    @State private var isEditorPresented = false

    let categories: [IOSCategoryRecord]
    let isSaving: Bool
    let onSave: CategorySaveAction
    let onArchive: (IOSCategoryRecord, Bool) async -> Bool
    let onMove: (IOSCategoryRecord, Int) async -> Bool

    private var activeCategories: [IOSCategoryRecord] {
        categories.filter { $0.typeName == typeName && !$0.archived && !$0.deleted }
    }

    private var archivedCategories: [IOSCategoryRecord] {
        categories.filter { $0.typeName == typeName && $0.archived && !$0.deleted }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Category type", selection: $typeName) {
                        Text("Expense").tag("EXPENSE")
                        Text("Income").tag("INCOME")
                    }
                    .pickerStyle(.segmented)
                }

                Section("Active categories") {
                    if activeCategories.isEmpty {
                        Text("No active categories. Restore one from Archived or add a category.")
                            .font(.subheadline)
                            .foregroundStyle(MizaniColors.muted)
                    }
                    ForEach(Array(activeCategories.enumerated()), id: \.element.id) { index, category in
                        categoryRow(category) {
                            Menu {
                                Button {
                                    editingCategory = category
                                    isEditorPresented = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button {
                                    Task { _ = await onMove(category, -1) }
                                } label: {
                                    Label("Move up", systemImage: "arrow.up")
                                }
                                .disabled(isSaving || index == 0)
                                Button {
                                    Task { _ = await onMove(category, 1) }
                                } label: {
                                    Label("Move down", systemImage: "arrow.down")
                                }
                                .disabled(isSaving || index == activeCategories.count - 1)
                                Divider()
                                Button(role: .destructive) {
                                    Task { _ = await onArchive(category, true) }
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .disabled(isSaving || activeCategories.count <= 1)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(MizaniColors.muted)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Actions for \(category.name)")
                            .disabled(isSaving)
                        }
                    }
                }

                if !archivedCategories.isEmpty {
                    Section("Archived") {
                        ForEach(archivedCategories, id: \.id) { category in
                            categoryRow(category) {
                                Menu {
                                    Button {
                                        editingCategory = category
                                        isEditorPresented = true
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button {
                                        Task { _ = await onArchive(category, false) }
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .disabled(isSaving)
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(MizaniColors.muted)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Actions for archived category \(category.name)")
                                .disabled(isSaving)
                            }
                        }
                    }
                }

                Section {
                    Text("Renaming or archiving a category keeps past activity and reports linked to it.")
                        .font(.footnote)
                        .foregroundStyle(MizaniColors.muted)
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        editingCategory = nil
                        isEditorPresented = true
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $isEditorPresented, onDismiss: { editingCategory = nil }) {
                CategoryEditorSheet(
                    category: editingCategory,
                    typeName: typeName,
                    isSaving: isSaving,
                    onSave: onSave
                )
            }
        }
    }

    private func categoryRow<Actions: View>(
        _ category: IOSCategoryRecord,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: IOSCategoryAppearance.symbol(for: category.icon))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(IOSCategoryAppearance.color(for: category.colorHex))
                .frame(width: 38, height: 38)
                .background(IOSCategoryAppearance.color(for: category.colorHex).opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MizaniColors.ink)
                Text(category.isDefault ? "Default" : "Custom")
                    .font(.system(size: 12))
                    .foregroundStyle(MizaniColors.muted)
            }
            Spacer(minLength: 8)
            actions()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var icon: String
    @State private var colorHex: String

    let category: IOSCategoryRecord?
    let typeName: String
    let isSaving: Bool
    let onSave: CategorySaveAction

    private let iconColumns = [GridItem(.adaptive(minimum: 48), spacing: 10)]
    private let colorColumns = [GridItem(.adaptive(minimum: 48), spacing: 10)]

    private var colorOptions: [String] {
        IOSCategoryAppearance.colors.contains(where: { $0.caseInsensitiveCompare(colorHex) == .orderedSame })
            ? IOSCategoryAppearance.colors
            : [colorHex] + IOSCategoryAppearance.colors
    }

    init(
        category: IOSCategoryRecord?,
        typeName: String,
        isSaving: Bool,
        onSave: @escaping CategorySaveAction
    ) {
        self.category = category
        self.typeName = typeName
        self.isSaving = isSaving
        self.onSave = onSave
        _name = State(initialValue: category?.name ?? "")
        _icon = State(initialValue: category?.icon ?? "category")
        _colorHex = State(initialValue: category?.colorHex ?? "#087F72")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Category name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityLabel("Category name")
                }

                Section("Icon") {
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(IOSCategoryAppearance.icons, id: \.self) { option in
                            Button {
                                icon = option
                            } label: {
                                Image(systemName: IOSCategoryAppearance.symbol(for: option))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(icon == option ? MizaniColors.teal : MizaniColors.muted)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(
                                        icon == option ? MizaniColors.teal.opacity(0.12) : MizaniColors.page,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(option) icon\(icon == option ? ", selected" : "")")
                        }
                    }
                }

                Section("Colour") {
                    LazyVGrid(columns: colorColumns, spacing: 10) {
                        ForEach(colorOptions, id: \.self) { option in
                            Button {
                                colorHex = option
                            } label: {
                                Circle()
                                    .fill(IOSCategoryAppearance.color(for: option))
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        Circle().stroke(
                                            colorHex == option ? MizaniColors.ink : Color.clear,
                                            lineWidth: 3
                                        )
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(IOSCategoryAppearance.colorName(for: option))
                            .accessibilityAddTraits(colorHex == option ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle(category == nil ? "Add category" : "Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(category == nil ? "Add" : "Save") {
                        Task {
                            if await onSave(category, name, icon, colorHex, category?.typeName ?? typeName) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private enum IOSCategoryAppearance {
    static let icons = [
        "home", "food", "transport", "fuel", "phone", "fees", "bolt", "school",
        "health", "family", "debt", "savings", "giving", "business", "personal",
        "entertainment", "income", "freelance", "category",
    ]

    static let colors = [
        "#087F72", "#0A9C8B", "#3F7C63", "#376D9D",
        "#7152A0", "#B78331", "#A2445B", "#677681",
    ]

    static func colorName(for hex: String) -> String {
        switch hex.uppercased() {
        case "#087F72": "Emerald"
        case "#0A9C8B": "Jade"
        case "#3F7C63": "Forest green"
        case "#3F6F76": "Blue green"
        case "#7A6A4F": "Brown"
        case "#4F6FA8": "Blue"
        case "#865C19": "Bronze"
        case "#2F8F80": "Teal"
        case "#7E57A8": "Purple"
        case "#B5564F": "Brick red"
        case "#A0626E": "Mauve"
        case "#8C4A3C": "Chestnut"
        case "#2F7D58": "Green"
        case "#9A7B2E": "Olive"
        case "#45637A": "Steel blue"
        case "#A8698C": "Plum"
        case "#6A6FA8": "Periwinkle"
        case "#6D6D6D": "Grey"
        case "#376D9D": "Blue"
        case "#7152A0": "Violet"
        case "#B78331": "Gold"
        case "#A2445B": "Rose"
        case "#677681": "Slate"
        default: "Current category colour"
        }
    }

    static func symbol(for icon: String) -> String {
        switch icon {
        case "home": "house.fill"
        case "food": "fork.knife"
        case "transport": "tram.fill"
        case "fuel": "fuelpump.fill"
        case "phone": "iphone"
        case "fees": "creditcard.fill"
        case "bolt": "bolt.fill"
        case "school": "graduationcap.fill"
        case "health": "cross.case.fill"
        case "family": "person.2.fill"
        case "debt": "arrow.uturn.backward"
        case "savings": "banknote.fill"
        case "giving": "heart.fill"
        case "business": "briefcase.fill"
        case "personal": "person.fill"
        case "entertainment": "film.fill"
        case "income": "arrow.down.left"
        case "freelance": "laptopcomputer"
        default: "square.grid.2x2.fill"
        }
    }

    static func color(for hex: String) -> Color {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return MizaniColors.muted
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
