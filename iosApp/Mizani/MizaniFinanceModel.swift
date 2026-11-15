import Combine
import Foundation
import MizaniCore
import MizaniShared

struct IOSCurrencyOption: Identifiable, Hashable {
    let code: String
    let symbol: String
    let name: String
    let minorUnits: Int

    var id: String { code }
}

struct IOSCountryOption: Identifiable, Hashable {
    let code: String
    let name: String
    let currencyCode: String

    var id: String { code }
}

struct IOSWalletTypeOption: Identifiable, Hashable {
    let name: String
    let label: String

    var id: String { name }
}

@MainActor
final class MizaniFinanceModel: ObservableObject {
    @Published private(set) var snapshot = IOSLedgerSnapshot(
        workspace: nil,
        wallets: [],
        categories: [],
        transactions: [],
        walletBalancesMinor: [:]
    )
    @Published private(set) var currentMonthInsightsSummary: NativeLedgerAnalyticsSummary?
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isStorageAvailable = true
    @Published private(set) var isLockStateLoading = true
    @Published private(set) var isLocked = false
    @Published private(set) var appLockEnabled = false
    @Published private(set) var biometricUnlockEnabled = false
    @Published private(set) var lockMessage: String?
    @Published private(set) var lockStateError: String?
    @Published var errorMessage: String?
    let incomeSourceKinds: [IOSIncomeSourceKind]
    let investmentAssetTypes: [IOSInvestmentAssetType]
    var commitmentProgress: [IOSCommitmentProgress] { snapshot.commitmentProgress(using: rules) }

    private let rules: KmpFinanceRulesAdapter
    private let appLockStore: IOSAppLockStore
    private let exchangeRateRepository = IOSExchangeRateRepository()
    private let databaseDirectoryURL: URL?
    private let databaseKeyProvider: KeychainDatabaseKeyProvider?
    private var repository: IOSFinanceRepository?
    private var didReadAppLockState = false
    private var isBootstrapping = false
    private var backgroundedAt: Date?

    init() {
        let rules = KmpFinanceRulesAdapter()
        self.rules = rules
        incomeSourceKinds = rules.incomeSourceKinds()
        investmentAssetTypes = rules.investmentAssetTypes()
        appLockStore = IOSAppLockStore(
            service: "\(Bundle.main.bundleIdentifier ?? "com.mizani.money.ios").app-lock",
            pbkdf2Iterations: Int(IosFinanceRules.shared.appLockPbkdf2Iterations()),
            isValidPIN: { pin in IosFinanceRules.shared.isValidAppLockPin(pin: pin) },
            backoffRemaining: { failedAttempts, lastFailureAt, now in
                IosFinanceRules.shared.appLockBlockedRemainingMs(
                    failedAttempts: failedAttempts,
                    lastFailureAtMs: lastFailureAt,
                    nowMs: now
                )
            }
        )
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("MizaniFinance", isDirectory: true)
            databaseDirectoryURL = directory
            databaseKeyProvider = KeychainDatabaseKeyProvider(
                service: Bundle.main.bundleIdentifier ?? "com.mizani.money.ios"
            )
        } catch {
            databaseDirectoryURL = nil
            databaseKeyProvider = nil
            isLoading = false
            isLockStateLoading = false
            isLocked = false
            isStorageAvailable = false
            lockStateError = "Secure storage could not be opened. Check that this device has a passcode and try again."
        }
    }

    var currencyCode: String { snapshot.workspace?.currencyCode ?? "UGX" }

    var currencyOptions: [IOSCurrencyOption] {
        let rules = IosFinanceRules.shared
        return (0..<Int(rules.currencyCount())).compactMap { index in
            guard let item = rules.currencyAt(index: Int32(index)) else { return nil }
            return IOSCurrencyOption(
                code: item.code,
                symbol: item.symbol,
                name: item.name,
                minorUnits: Int(item.minorUnits)
            )
        }
    }

    var countryOptions: [IOSCountryOption] {
        let rules = IosFinanceRules.shared
        return (0..<Int(rules.countryCount())).compactMap { index in
            guard let item = rules.countryAt(index: Int32(index)) else { return nil }
            return IOSCountryOption(code: item.code, name: item.name, currencyCode: item.currencyCode)
        }
    }

    var walletTypeOptions: [IOSWalletTypeOption] {
        let rules = IosFinanceRules.shared
        return (0..<Int(rules.walletTypeCount())).compactMap { index in
            guard let item = rules.walletTypeAt(index: Int32(index)) else { return nil }
            return IOSWalletTypeOption(name: item.name, label: item.label)
        }
    }

    var appLockPinLength: Int { Int(IosFinanceRules.shared.appLockPinLength()) }

    func isValidAppLockPIN(_ pin: String) -> Bool {
        rules.isValidAppLockPin(pin)
    }

    private func insightsSummary(for snapshot: IOSLedgerSnapshot, at date: Date = Date()) -> NativeLedgerAnalyticsSummary? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let month = calendar.dateInterval(of: .month, for: date),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end) else {
            return nil
        }

        let epochStart = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        func epochDay(_ value: Date) -> Int64? {
            guard let day = calendar.dateComponents(
                [.day],
                from: epochStart,
                to: calendar.startOfDay(for: value)
            ).day else { return nil }
            return Int64(day)
        }
        guard let startEpochDay = epochDay(month.start),
              let endEpochDay = epochDay(lastDay) else {
            return nil
        }

        return KmpFinanceRulesAdapter().ledgerAnalyticsSummary(
            snapshot: snapshot,
            startEpochDay: startEpochDay,
            endEpochDay: endEpochDay
        )
    }

    func bootstrap() async {
        guard !didReadAppLockState, !isBootstrapping else { return }
        isBootstrapping = true
        isLockStateLoading = true
        lockStateError = nil
        defer { isBootstrapping = false }

        do {
            let status = try await appLockStore.status(nowMilliseconds: nowMilliseconds())
            didReadAppLockState = true
            appLockEnabled = status.isEnabled
            biometricUnlockEnabled = status.biometricEnabled
            if status.backoffRemainingMilliseconds > 0 {
                lockMessage = retryMessage(status.backoffRemainingMilliseconds)
            }
            if status.isEnabled {
                isLocked = true
                isLoading = false
                isLockStateLoading = false
                return
            }
            isLockStateLoading = false
            await openProtectedSession()
        } catch {
            isLocked = false
            isLoading = false
            isLockStateLoading = false
            isStorageAvailable = false
            lockStateError = "The app-lock state could not be read securely. Ledger data remains closed. Try again."
        }
    }

    func retryProtectedStorage() async {
        didReadAppLockState = false
        await bootstrap()
    }

    private func makeRepository() throws -> IOSFinanceRepository {
        guard let databaseDirectoryURL, let databaseKeyProvider else {
            throw EncryptedDatabaseError.directoryUnavailable
        }
        return try IOSFinanceRepository(
            databaseDirectoryURL: databaseDirectoryURL,
            keyProvider: databaseKeyProvider,
            rules: rules
        )
    }

    private func openProtectedSession() async {
        isLoading = true
        do {
            let openedRepository = try makeRepository()
            let loadedSnapshot = try await openedRepository.snapshot()
            repository = openedRepository
            snapshot = loadedSnapshot
            currentMonthInsightsSummary = insightsSummary(for: loadedSnapshot)
            isStorageAvailable = true
            isLocked = false
            lockStateError = nil
            lockMessage = nil
            errorMessage = snapshot.balancesAvailable
                ? nil
                : "A saved wallet balance is outside the supported range. Review Activity and delete or edit a transaction to recover it."
        } catch {
            isLocked = appLockEnabled
            isStorageAvailable = false
            lockStateError = "Secure storage could not be opened. Your saved records have not been changed. Check the device passcode and try again."
            errorMessage = nil
        }
        isLoading = false
    }

    func reload() async {
        guard let repository else {
            isLoading = false
            return
        }
        do {
            let loadedSnapshot = try await repository.snapshot()
            snapshot = loadedSnapshot
            currentMonthInsightsSummary = insightsSummary(for: loadedSnapshot)
            isStorageAvailable = true
            errorMessage = snapshot.balancesAvailable
                ? nil
                : "A saved wallet balance is outside the supported range. Review Activity and delete or edit a transaction to recover it."
        } catch {
            currentMonthInsightsSummary = nil
            isStorageAvailable = false
            errorMessage = "Your local ledger could not be read. Your saved records have not been changed."
        }
        isLoading = false
    }

    func noteBackgrounded(at date: Date) {
        backgroundedAt = date
    }

    func handleForeground(at date: Date) async {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil
        let elapsed = date.timeIntervalSince(backgroundedAt)
        let graceMilliseconds = Int64(IosFinanceRules.shared.appLockBackgroundGracePeriodMs())
        if appLockEnabled && elapsed * 1_000 >= Double(graceMilliseconds) {
            await lockAndCloseRepository()
        }
    }

    func lockAndCloseRepository() async {
        guard appLockEnabled else { return }
        isLocked = true
        clearLedgerSnapshot()
        let closingRepository = repository
        repository = nil
        guard let closingRepository else { return }
        do {
            try await closingRepository.close()
        } catch {
            lockStateError = "The secure database session could not close cleanly. The app remains locked."
        }
    }

    private func clearLedgerSnapshot() {
        snapshot = IOSLedgerSnapshot(
            workspace: nil,
            wallets: [],
            categories: [],
            transactions: [],
            walletBalancesMinor: [:]
        )
        currentMonthInsightsSummary = nil
        errorMessage = nil
    }

    func unlockWithPIN(_ pin: String) async {
        guard isLocked, !isLockStateLoading else { return }
        lockMessage = nil
        do {
            switch try await appLockStore.verifyPIN(pin, nowMilliseconds: nowMilliseconds()) {
            case .success:
                await openProtectedSession()
            case .incorrect:
                lockMessage = "That PIN is incorrect."
            case let .blocked(remainingMilliseconds):
                lockMessage = retryMessage(remainingMilliseconds)
            case .notConfigured:
                lockStateError = "The app-lock record is unavailable. Ledger data remains closed. Try again."
            }
        } catch {
            lockStateError = "The PIN could not be checked securely. Ledger data remains closed. Try again."
        }
    }

    func unlockAfterBiometricAuthentication() async {
        guard isLocked, biometricUnlockEnabled else { return }
        do {
            guard try await appLockStore.recordBiometricAuthenticationSuccess() else {
                lockStateError = "Biometric unlock is no longer enabled. Unlock with your PIN."
                return
            }
            await openProtectedSession()
        } catch {
            lockStateError = "Biometric unlock could not verify the app-lock state. Unlock with your PIN."
        }
    }

    func setAppLockPIN(_ pin: String, confirmation: String) async -> Bool {
        guard !appLockEnabled else {
            lockMessage = "Enter the current PIN before replacing an existing app lock."
            return false
        }
        guard isValidAppLockPIN(pin), pin == confirmation else {
            lockMessage = "Enter the same valid six-digit PIN twice."
            return false
        }
        do {
            try await appLockStore.setPIN(pin)
            appLockEnabled = true
            biometricUnlockEnabled = false
            lockMessage = nil
            return true
        } catch {
            lockMessage = "The PIN could not be saved in secure storage. Check that this device has a passcode."
            return false
        }
    }

    func changeAppLockPIN(currentPIN: String, newPIN: String, confirmation: String) async -> Bool {
        guard isValidAppLockPIN(newPIN), newPIN == confirmation else {
            lockMessage = "Enter the same valid six-digit new PIN twice."
            return false
        }
        do {
            switch try await appLockStore.changePIN(
                currentPIN: currentPIN,
                newPIN: newPIN,
                nowMilliseconds: nowMilliseconds()
            ) {
            case .success:
                lockMessage = nil
                return true
            case .incorrect:
                lockMessage = "The current PIN is incorrect."
            case let .blocked(remainingMilliseconds):
                lockMessage = retryMessage(remainingMilliseconds)
            case .notConfigured:
                lockMessage = "App lock is not configured."
            }
        } catch {
            lockMessage = "The PIN could not be changed securely."
        }
        return false
    }

    func setBiometricUnlock(_ enabled: Bool, currentPIN: String) async -> Bool {
        do {
            switch try await appLockStore.setBiometricEnabled(
                enabled,
                requiringPIN: currentPIN,
                nowMilliseconds: nowMilliseconds()
            ) {
            case .success:
                biometricUnlockEnabled = enabled
                lockMessage = nil
                return true
            case .incorrect:
                lockMessage = "The current PIN is incorrect."
            case let .blocked(remainingMilliseconds):
                lockMessage = retryMessage(remainingMilliseconds)
            case .notConfigured:
                lockMessage = "Set an app-lock PIN before enabling biometric unlock."
            }
        } catch {
            lockMessage = "The biometric preference could not be saved securely."
        }
        return false
    }

    func disableAppLock(currentPIN: String) async -> Bool {
        do {
            switch try await appLockStore.disable(
                requiringPIN: currentPIN,
                nowMilliseconds: nowMilliseconds()
            ) {
            case .success:
                appLockEnabled = false
                biometricUnlockEnabled = false
                lockMessage = nil
                return true
            case .incorrect:
                lockMessage = "The current PIN is incorrect."
            case let .blocked(remainingMilliseconds):
                lockMessage = retryMessage(remainingMilliseconds)
            case .notConfigured:
                lockMessage = "App lock is already disabled."
            }
        } catch {
            lockMessage = "App lock could not be disabled securely."
        }
        return false
    }

    private func nowMilliseconds() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    private func retryMessage(_ remainingMilliseconds: Int64) -> String {
        let seconds = max(1, Int((remainingMilliseconds + 999) / 1_000))
        return "Too many attempts. Try again in \(seconds) seconds."
    }

    func createFirstWallet(
        countryCode: String,
        currencyCode: String,
        walletName: String,
        walletTypeName: String,
        openingBalance: String
    ) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        let digits = currencyMinorUnits(for: currencyCode)
        let balanceInput = openingBalance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "0" : openingBalance
        guard digits >= 0,
              let amount = minorUnits(from: balanceInput, currencyCode: currencyCode) else {
            errorMessage = "Enter a valid opening balance."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.createWorkspace(
                name: "My money",
                countryCode: countryCode,
                currencyCode: currencyCode,
                walletName: walletName,
                walletTypeName: walletTypeName,
                openingBalanceMinor: amount
            )
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func addWallet(name: String, typeName: String, openingBalance: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        let digits = currencyMinorUnits(for: currencyCode)
        guard digits >= 0,
              let amount = minorUnits(from: openingBalance, currencyCode: currencyCode) else {
            errorMessage = "Enter a valid opening balance."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.addWallet(name: name, typeName: typeName, openingBalanceMinor: amount)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func addCategory(name: String, typeName: String, icon: String, colorHex: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.addCategory(name: name, typeName: typeName, icon: icon, colorHex: colorHex)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func updateCategory(id: String, name: String, icon: String, colorHex: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.updateCategory(id: id, name: name, icon: icon, colorHex: colorHex)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func setCategoryArchived(id: String, archived: Bool) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.setCategoryArchived(id: id, archived: archived)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func moveCategory(id: String, direction: Int) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.moveCategory(id: id, direction: direction)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func addIncomeSource(name: String, kindName: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.addIncomeSource(name: name, kindName: kindName)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func updateIncomeSource(id: String, name: String, kindName: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.updateIncomeSource(id: id, name: name, kindName: kindName)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func saveGoal(
        id: String?,
        name: String,
        targetAmount: String,
        targetDate: Date?,
        linkedWalletId: String?,
        priority: Int,
        note: String,
        icon: String
    ) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        guard let amount = minorUnits(from: targetAmount, currencyCode: currencyCode) else {
            errorMessage = "Enter a valid savings goal target."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await repository.saveGoal(
                id: id,
                name: name,
                targetMinor: amount,
                targetDate: targetDate,
                linkedWalletId: linkedWalletId,
                priority: priority,
                note: note,
                icon: icon
            )
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func contributeToGoal(
        goalId: String,
        amount: String,
        fromWalletId: String?,
        note: String
    ) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        guard let amountMinor = minorUnits(from: amount, currencyCode: currencyCode) else {
            errorMessage = "Enter a valid contribution amount."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.contributeToGoal(
                goalId: goalId,
                amountMinor: amountMinor,
                fromWalletId: fromWalletId,
                note: note
            )
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func setGoalArchived(id: String, archived: Bool) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.setGoalArchived(id: id, archived: archived)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func saveInvestmentHolding(
        id: String?,
        name: String,
        provider: String,
        assetTypeName: String,
        costBasis: String?,
        currentValue: String?,
        valuationDate: Date,
        note: String
    ) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        let existing = id.flatMap { existingId in snapshot.investments.first(where: { $0.id == existingId }) }
        let costBasisMinor: Int64
        if let costBasis {
            guard let parsed = minorUnits(from: costBasis, currencyCode: currencyCode) else {
                errorMessage = "Enter a valid cost basis."
                return false
            }
            costBasisMinor = parsed
        } else if let existing {
            costBasisMinor = existing.costBasisMinor
        } else {
            errorMessage = "Enter a valid cost basis."
            return false
        }
        let currentValueMinor: Int64
        if let currentValue {
            guard let parsed = minorUnits(from: currentValue, currencyCode: currencyCode) else {
                errorMessage = "Enter a valid current value."
                return false
            }
            currentValueMinor = parsed
        } else if let existing {
            currentValueMinor = existing.currentValueMinor
        } else {
            errorMessage = "Enter a valid current value."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await repository.saveInvestmentHolding(
                id: id,
                name: name,
                provider: provider,
                assetTypeName: assetTypeName,
                costBasisMinor: costBasisMinor,
                currentValueMinor: currentValueMinor,
                valuationDate: valuationDate,
                note: note
            )
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func setInvestmentHoldingArchived(id: String, archived: Bool) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.setInvestmentHoldingArchived(id: id, archived: archived)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func loadExchangeRate(baseCurrencyCode: String, quoteCurrencyCode: String) async throws -> IOSExchangeRateQuote {
        let cached = try await exchangeRateRepository.cachedRate(
            baseCurrencyCode: baseCurrencyCode,
            quoteCurrencyCode: quoteCurrencyCode
        )
        let shouldRefresh = try await exchangeRateRepository.shouldRefresh(
            baseCurrencyCode: baseCurrencyCode,
            quoteCurrencyCode: quoteCurrencyCode
        )
        if !shouldRefresh, let cached { return cached }
        do {
            return try await exchangeRateRepository.refreshRate(
                baseCurrencyCode: baseCurrencyCode,
                quoteCurrencyCode: quoteCurrencyCode
            )
        } catch {
            if let cached { return cached }
            throw error
        }
    }

    func refreshExchangeRate(baseCurrencyCode: String, quoteCurrencyCode: String) async throws -> IOSExchangeRateQuote {
        try await exchangeRateRepository.refreshRate(
            baseCurrencyCode: baseCurrencyCode,
            quoteCurrencyCode: quoteCurrencyCode
        )
    }

    func saveCommitment(
        id: String?,
        name: String,
        amount: String,
        targetCurrencyCode: String,
        exchangeRate: IOSExchangeRateQuote?,
        dueDate: Date,
        categoryId: String?,
        reminderDaysBefore: Int
    ) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        guard let targetMinor = minorUnits(from: amount, currencyCode: targetCurrencyCode),
              targetMinor > 0,
              rules.isSupportedAmountMinor(targetMinor) else {
            errorMessage = "Enter a valid commitment amount."
            return false
        }
        let savedRate: String?
        let savedRateDate: String?
        if targetCurrencyCode == currencyCode {
            savedRate = nil
            savedRateDate = nil
        } else {
            guard let exchangeRate,
                  exchangeRate.baseCurrencyCode == targetCurrencyCode,
                  exchangeRate.quoteCurrencyCode == currencyCode else {
                errorMessage = "A current exchange rate is required for this currency pair."
                return false
            }
            savedRate = exchangeRate.rate
            savedRateDate = exchangeRate.date
        }
        guard let convertedText = rules.commitmentToWorkspaceMinor(
            amountMinor: targetMinor,
            workspaceCurrencyCode: currencyCode,
            commitmentCurrencyCode: targetCurrencyCode,
            exchangeRate: savedRate
        ), let targetWorkspaceMinor = Int64(convertedText),
              targetWorkspaceMinor > 0,
              rules.isSupportedAmountMinor(targetWorkspaceMinor) else {
            errorMessage = "This amount cannot be converted safely into \(currencyCode)."
            return false
        }

        let draft = IOSCommitmentDraft(
            name: name,
            targetMinor: targetMinor,
            currencyCode: targetCurrencyCode,
            targetWorkspaceMinor: targetWorkspaceMinor,
            exchangeRate: savedRate,
            exchangeRateDate: savedRateDate,
            dueEpochDay: IOSFinanceRepository.commitmentLocalEpochDay(dueDate),
            categoryId: categoryId,
            reminderDaysBefore: reminderDaysBefore
        )
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await repository.saveCommitment(id: id, draft: draft)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func setCommitmentArchived(id: String, archived: Bool) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.setCommitmentArchived(id: id, archived: archived)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func deleteCommitment(id: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.deleteCommitment(id: id)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func linkExpenseToCommitment(commitmentId: String, transactionId: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await repository.linkExpenseToCommitment(commitmentId: commitmentId, transactionId: transactionId)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func unlinkCommitmentPayment(id: String) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.unlinkCommitmentPayment(id: id)
            await reload()
            return true
        } catch {
            errorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func record(
        existingTransaction: IOSTransactionRecord?,
        typeName: String,
        amount: String,
        fee: String,
        walletId: String,
        destinationWalletId: String,
        categoryId: String,
        incomeSourceId: String,
        linkedTransactionId: String,
        adjustmentNegative: Bool,
        note: String
    ) async -> Bool {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return false
        }
        let feeText = fee.trimmingCharacters(in: .whitespacesAndNewlines)
        let currencyDigits = currencyMinorUnits(for: currencyCode)
        guard currencyDigits >= 0,
              let amountMinor = minorUnits(from: amount, currencyCode: currencyCode),
              let feeMinor = feeText.isEmpty ? Int64(0) : minorUnits(from: feeText, currencyCode: currencyCode) else {
            errorMessage = "Enter a valid amount and fee."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let occurredAt = existingTransaction.map {
                Date(timeIntervalSince1970: TimeInterval($0.occurredAtMillis) / 1_000)
            } ?? Date()
            if typeName == "TRANSFER" {
                try await repository.recordTransfer(
                    amountMinor: amountMinor,
                    feeMinor: feeMinor,
                    sourceWalletId: walletId,
                    destinationWalletId: destinationWalletId,
                    transactionId: existingTransaction?.id,
                    note: note,
                    occurredAt: occurredAt
                )
            } else {
                let adjustmentMagnitude = amountMinor == Int64.min ? Int64.max : abs(amountMinor)
                let signedAmount = typeName == "ADJUSTMENT"
                    ? (adjustmentNegative ? -adjustmentMagnitude : adjustmentMagnitude)
                    : amountMinor
                try await repository.recordTransaction(
                    typeName: typeName,
                    amountMinor: signedAmount,
                    feeMinor: typeName == "ADJUSTMENT" ? 0 : feeMinor,
                    walletId: walletId,
                    categoryId: categoryId,
                    incomeSourceId: typeName == "INCOME" && !incomeSourceId.isEmpty ? incomeSourceId : nil,
                    linkedTransactionId: typeName == "REFUND" && !linkedTransactionId.isEmpty ? linkedTransactionId : nil,
                    transactionId: existingTransaction?.id,
                    note: note,
                    occurredAt: occurredAt
                )
            }
            await reload()
            return true
        } catch {
            if let repositoryError = error as? IOSFinanceRepositoryError,
               repositoryError == .refundTargetUnavailable,
               existingTransaction?.typeName == "REFUND",
               let linkedTransactionId = existingTransaction?.linkedTransactionId,
               snapshot.transactions.contains(where: { $0.id == linkedTransactionId && $0.deleted }) {
                errorMessage = "This linked expense is in Recently deleted. Restore it before editing this refund."
            } else {
                errorMessage = friendlyMessage(for: error)
            }
            return false
        }
    }

    func deleteTransaction(id: String) async {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.deleteTransaction(id: id)
            await reload()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func restoreTransaction(id: String) async {
        guard let repository else {
            errorMessage = "Secure storage is unavailable. No records were changed."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.restoreTransaction(id: id)
            await reload()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    func formatted(_ amountMinor: Int64, currencyCode: String? = nil) -> String {
        let digits = max(0, currencyMinorUnits(for: currencyCode ?? self.currencyCode))
        let scale = Decimal(pow10(digits))
        let majorAmount = Decimal(amountMinor) / scale
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_UG")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = digits
        return formatter.string(from: NSDecimalNumber(decimal: majorAmount)) ?? inputAmount(from: amountMinor, currencyCode: currencyCode)
    }

    func inputAmount(from amountMinor: Int64, currencyCode: String? = nil) -> String {
        let digits = max(0, currencyMinorUnits(for: currencyCode ?? self.currencyCode))
        let scale = Int64(pow10(digits))
        let negative = amountMinor < 0
        let magnitude = amountMinor == Int64.min ? Int64.max : abs(amountMinor)
        let whole = magnitude / scale
        guard digits > 0 else { return "\(negative ? "-" : "")\(whole)" }
        let rawFraction = String(magnitude % scale)
        let fraction = String(repeating: "0", count: max(0, digits - rawFraction.count)) + rawFraction
        return "\(negative ? "-" : "")\(whole).\(fraction)"
    }

    func currencyMinorUnits(for currencyCode: String) -> Int {
        Int(IosFinanceRules.shared.currencyMinorUnits(currencyCode: currencyCode))
    }

    private func minorUnits(from input: String, currencyCode: String) -> Int64? {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let groupingSeparator = Locale.current.groupingSeparator ?? ","
        guard let parsed = IosFinanceRules.shared.parseMoneyInput(
            input: input,
            currencyCode: currencyCode,
            decimalSeparator: decimalSeparator,
            groupingSeparator: groupingSeparator
        ) else { return nil }
        return Int64(parsed)
    }

    private func pow10(_ power: Int) -> Int {
        (0..<power).reduce(1) { value, _ in value * 10 }
    }

    private func friendlyMessage(for error: Error) -> String {
        guard let repositoryError = error as? IOSFinanceRepositoryError else {
            return "The change could not be saved. Your existing records were kept."
        }
        switch repositoryError {
        case .noWorkspace:
            return "Create a wallet before recording activity."
        case .invalidName:
            return "Enter a name to continue."
        case .invalidWalletType, .invalidTransactionType, .unsupportedTransactionType:
            return "This type of entry is not available yet."
        case .amountOutsideSupportedRange:
            return "That amount is outside the supported range."
        case let .transactionRejected(code):
            switch code {
            case "fee_invalid": return "Fees cannot be negative."
            case "adjustment_fee_unsupported": return "Balance adjustments cannot include a fee."
            default: return "Enter a valid amount."
            }
        case .workspaceAlreadyExists:
            return "Your workspace has already been created."
        case .walletNotFound, .walletUnavailable:
            return "Choose an active wallet."
        case .invalidTransferDestination:
            return "Choose two different active wallets in the same currency."
        case .refundTargetUnavailable:
            return "Choose an active expense to link this refund."
        case .transactionNotFound:
            return "That activity could not be found. Refresh and try again."
        case .transactionUnavailable:
            return "That activity is in Recently deleted and cannot be edited."
        case .transactionHasRefunds:
            return "This expense has linked refunds. Restore any deleted refunds and unlink them before changing its type."
        case .categoryLastActive:
            return "Keep at least one active category for each type."
        case .categoryOrderUnavailable:
            return "The category order could not be updated. Your saved categories were kept."
        case .invalidIncomeSourceKind:
            return "Choose one of the supported income source types."
        case .incomeSourceNotFound, .incomeSourceUnavailable:
            return "Choose an available income source."
        case .goalNotFound:
            return "That savings goal could not be found. Refresh and try again."
        case .goalUnavailable:
            return "That savings goal is archived or unavailable."
        case .investmentNotFound:
            return "That investment could not be found. Refresh and try again."
        case .investmentUnavailable:
            return "That investment is in Recently deleted and cannot be changed."
        case .commitmentNotFound:
            return "That commitment could not be found. Refresh and try again."
        case .commitmentUnavailable:
            return "That commitment is archived or unavailable."
        case .commitmentPaymentUnavailable:
            return "This expense cannot be linked to that commitment. Check its currency, refunds, and remaining target."
        case let .commitmentDraftRejected(code):
            switch code {
            case "name_too_long": return "Commitment name is too long."
            case "reminder_days_invalid": return "Choose a reminder between 0 and 30 days."
            case "target_below_payments": return "The target cannot be lower than payments already linked."
            case "rate_missing_or_invalid": return "A valid exchange rate is required for this currency."
            case "rate_date_future": return "The exchange-rate date cannot be in the future."
            case "converted_target_mismatch": return "The converted target does not match the saved exchange rate."
            default: return "Enter a valid commitment amount and exchange rate."
            }
        case let .investmentDraftRejected(code):
            switch code {
            case "name_required": return "Give this investment a name."
            case "name_too_long": return "Investment name is too long."
            case "provider_required": return "Enter where this investment is held."
            case "provider_too_long": return "Provider name is too long."
            case "note_too_long": return "Investment note is too long."
            case "cost_basis_invalid": return "Enter a cost basis greater than zero."
            case "current_value_invalid": return "Enter a current value in the supported range."
            case "valuation_date_invalid": return "Valuation date cannot be in the future."
            default: return "Choose a supported investment type and valid values."
            }
        case .categoryNotFound, .categoryUnavailable, .categoryTypeMismatch:
            return "Choose an active category for this entry type."
        case .sharedCatalogUnavailable:
            return "Shared finance data could not be loaded. No records were changed."
        case .invalidCurrency:
            return "The selected currency could not be used."
        case .balanceUnavailable:
            return "A balance could not be calculated safely. Your records were not changed."
        }
    }
}

private struct KmpFinanceRulesAdapter: IOSFinanceRulesProviding {
    func transactionValidationError(typeName: String, amountMinor: Int64, feeMinor: Int64) -> String? {
        IosFinanceRules.shared.transactionValidationError(
            typeName: typeName,
            amountMinor: amountMinor,
            feeMinor: feeMinor
        )
    }

    func isSupportedAmountMinor(_ amountMinor: Int64) -> Bool {
        IosFinanceRules.shared.isSupportedAmountMinor(amountMinor: amountMinor)
    }

    func isValidAppLockPin(_ pin: String) -> Bool {
        IosFinanceRules.shared.isValidAppLockPin(pin: pin)
    }

    func isValidWalletTypeName(_ typeName: String) -> Bool {
        IosFinanceRules.shared.isValidWalletTypeName(typeName: typeName)
    }

    func isSupportedCurrencyCode(_ currencyCode: String) -> Bool {
        IosFinanceRules.shared.isSupportedCurrencyCode(currencyCode: currencyCode)
    }

    func canArchiveCategory(activeCategoryCount: Int64) -> Bool {
        CategoryManagementRules.shared.canArchiveCategory(activeCategoryCount: Int32(activeCategoryCount))
    }

    func canAssignIncomeSource(typeName: String, hasIncomeSource: Bool) -> Bool {
        IosFinanceRules.shared.canAssignIncomeSource(
            transactionTypeName: typeName,
            hasIncomeSource: hasIncomeSource
        )
    }

    func defaultCategories() -> [IOSCategorySeed] {
        let count = Int(IosFinanceRules.shared.defaultCategoryCount())
        return (0..<count).compactMap { index in
            guard let category = IosFinanceRules.shared.defaultCategoryAt(index: Int32(index)) else { return nil }
            return IOSCategorySeed(
                id: category.id,
                key: category.key,
                name: category.name,
                typeName: category.typeName,
                icon: category.icon,
                colorHex: category.colorHex
            )
        }
    }

    func incomeSourceKinds() -> [IOSIncomeSourceKind] {
        let count = Int(IosFinanceRules.shared.incomeSourceKindCount())
        return (0..<count).compactMap { index in
            guard let kind = IosFinanceRules.shared.incomeSourceKindAt(index: Int32(index)) else { return nil }
            return IOSIncomeSourceKind(name: kind.name, label: kind.label)
        }
    }

    func isSupportedGoalTargetMinor(_ amountMinor: Int64) -> Bool {
        IosFinanceRules.shared.isSupportedGoalTargetMinor(amountMinor: amountMinor)
    }

    func isSupportedGoalContributionMinor(_ amountMinor: Int64) -> Bool {
        IosFinanceRules.shared.isSupportedGoalContributionMinor(amountMinor: amountMinor)
    }

    func goalAllocatedMinorAfterContribution(currentAllocatedMinor: Int64, contributionMinor: Int64) -> String? {
        IosFinanceRules.shared.goalAllocatedMinorAfterContribution(
            currentAllocatedMinor: currentAllocatedMinor,
            contributionMinor: contributionMinor
        )
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
        IosFinanceRules.shared.commitmentDraftValidationError(
            workspaceCurrencyCode: workspaceCurrencyCode,
            commitmentCurrencyCode: commitmentCurrencyCode,
            targetMinor: targetMinor,
            targetWorkspaceMinor: targetWorkspaceMinor,
            exchangeRate: exchangeRate,
            exchangeRateDate: exchangeRateDate,
            todayEpochDay: todayEpochDay
        )
    }

    func commitmentToWorkspaceMinor(
        amountMinor: Int64,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?
    ) -> String? {
        IosFinanceRules.shared.commitmentToWorkspaceMinor(
            amountMinor: amountMinor,
            workspaceCurrencyCode: workspaceCurrencyCode,
            commitmentCurrencyCode: commitmentCurrencyCode,
            exchangeRate: exchangeRate
        )
    }

    func workspaceToCommitmentMinor(
        amountMinor: Int64,
        workspaceCurrencyCode: String,
        commitmentCurrencyCode: String,
        exchangeRate: String?
    ) -> String? {
        IosFinanceRules.shared.workspaceToCommitmentMinor(
            amountMinor: amountMinor,
            workspaceCurrencyCode: workspaceCurrencyCode,
            commitmentCurrencyCode: commitmentCurrencyCode,
            exchangeRate: exchangeRate
        )
    }

    func investmentAssetTypes() -> [IOSInvestmentAssetType] {
        let count = Int(IosFinanceRules.shared.investmentAssetTypeCount())
        return (0..<count).compactMap { index in
            guard let type = IosFinanceRules.shared.investmentAssetTypeAt(index: Int32(index)) else { return nil }
            return IOSInvestmentAssetType(name: type.name, label: type.label)
        }
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
        IosFinanceRules.shared.investmentDraftValidationError(
            name: name,
            provider: provider,
            note: note,
            assetTypeName: assetTypeName,
            costBasisMinor: costBasisMinor,
            currentValueMinor: currentValueMinor,
            valuationEpochDay: valuationEpochDay,
            todayEpochDay: todayEpochDay
        )
    }

    func investmentPortfolioSummary(
        costBasisMinor: [Int64],
        currentValueMinor: [Int64],
        active: [Bool]
    ) -> IOSInvestmentPortfolioSummary? {
        guard let summary = IosFinanceRules.shared.investmentPortfolioSummary(
            costBasisMinor: costBasisMinor,
            currentValueMinor: currentValueMinor,
            active: active
        ) else { return nil }
        return IOSInvestmentPortfolioSummary(
            holdingCount: Int(summary.holdingCount),
            costBasisMinor: summary.costBasisMinor,
            currentValueMinor: summary.currentValueMinor,
            gainLossMinor: summary.gainLossMinor
        )
    }

    func feesCategoryId() -> String {
        IosFinanceRules.shared.feesCategoryId()
    }

    func walletBalanceMinor(
        walletId: String,
        openingBalanceMinor: Int64,
        transactions: [IOSTransactionRecord]
    ) -> String? {
        IosFinanceRules.shared.walletBalanceMinor(
            walletId: walletId,
            openingBalanceMinor: openingBalanceMinor,
            transactionTypes: transactions.map(\.typeName),
            amountsMinor: transactions.map(\.amountMinor),
            feesMinor: transactions.map(\.feeMinor),
            sourceWalletIds: transactions.map(\.walletId),
            destinationWalletIds: transactions.map(\.destinationWalletId),
            deleted: transactions.map(\.deleted)
        )
    }

    func ledgerAnalyticsSummary(
        snapshot: IOSLedgerSnapshot,
        startEpochDay: Int64,
        endEpochDay: Int64
    ) -> NativeLedgerAnalyticsSummary? {
        IosFinanceRules.shared.ledgerAnalyticsSummary(
            transactionTypes: snapshot.transactions.map(\.typeName),
            amountsMinor: snapshot.transactions.map(\.amountMinor),
            feesMinor: snapshot.transactions.map(\.feeMinor),
            categoryIds: snapshot.transactions.map(\.categoryId),
            feeCategoryIds: snapshot.transactions.map(\.feeCategoryId),
            localDateEpochDays: snapshot.transactions.map(\.localDateEpochDay),
            deleted: snapshot.transactions.map(\.deleted),
            startEpochDay: startEpochDay,
            endEpochDay: endEpochDay
        )
    }
}
