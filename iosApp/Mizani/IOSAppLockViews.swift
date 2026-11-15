import LocalAuthentication
import SwiftUI

private enum IOSLockColors {
    static let ink = Color(red: 23.0 / 255.0, green: 53.0 / 255.0, blue: 61.0 / 255.0)
    static let teal = Color(red: 8.0 / 255.0, green: 127.0 / 255.0, blue: 114.0 / 255.0)
    static let muted = Color(red: 73.0 / 255.0, green: 101.0 / 255.0, blue: 105.0 / 255.0)
    static let page = Color(red: 242.0 / 255.0, green: 248.0 / 255.0, blue: 245.0 / 255.0)
}

struct IOSAppLockScreen: View {
    @ObservedObject var model: MizaniFinanceModel
    let onRetry: () -> Void
    @State private var pin = ""
    @State private var isWorking = false
    @State private var biometricMessage: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(IOSLockColors.teal)
                .accessibilityHidden(true)
            Text("Mizani is locked")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(IOSLockColors.ink)
            Text("Enter your app PIN to open your private ledger.")
                .font(.system(size: 15))
                .foregroundStyle(IOSLockColors.muted)
                .multilineTextAlignment(.center)
            SecureField("Six-digit PIN", text: $pin)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .padding(15)
                .background(.white, in: RoundedRectangle(cornerRadius: 15))
                .onChange(of: pin) { pin = sixDigitInput($0, limit: model.appLockPinLength) }
                .accessibilityLabel("Six-digit app PIN")
            Button {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    await model.unlockWithPIN(pin)
                    pin = ""
                }
            } label: {
                Text(isWorking ? "Checking…" : "Unlock")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(IOSLockColors.teal, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isWorking || !model.isValidAppLockPIN(pin))

            if model.biometricUnlockEnabled {
                Button {
                    authenticateBiometrics()
                } label: {
                    Label("Unlock with biometrics", systemImage: "faceid")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(IOSLockColors.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }

            if let lockMessage = model.lockMessage ?? biometricMessage {
                Text(lockMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let lockStateError = model.lockStateError {
                Text(lockStateError)
                    .font(.system(size: 13))
                    .foregroundStyle(IOSLockColors.muted)
                    .multilineTextAlignment(.center)
                Button("Check secure storage again", action: onRetry)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IOSLockColors.teal)
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IOSLockColors.page.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func authenticateBiometrics() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            biometricMessage = "Biometric unlock is unavailable. Enter your app PIN."
            return
        }
        isWorking = true
        Task {
            let authenticated = await evaluateBiometrics(context)
            if authenticated {
                await model.unlockAfterBiometricAuthentication()
                if !model.isLocked { pin = "" }
                biometricMessage = model.lockStateError
            } else {
                biometricMessage = "Biometric verification did not complete. Enter your app PIN."
            }
            isWorking = false
        }
    }

    private func evaluateBiometrics(_ context: LAContext) async -> Bool {
        defer { context.invalidate() }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Mizani to view your private ledger"
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

struct IOSAppLockSettingsView: View {
    @ObservedObject var model: MizaniFinanceModel
    @Environment(\.dismiss) private var dismiss
    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmationPIN = ""
    @State private var isWorking = false
    @State private var localMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(model.appLockEnabled
                         ? "Your ledger is protected by an app PIN."
                         : "Add an app PIN to require verification when you return to Mizani.")
                        .font(.system(size: 15))
                        .foregroundStyle(IOSLockColors.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    if model.appLockEnabled {
                        pinField("Current PIN", text: $currentPIN)
                    }
                    pinField(model.appLockEnabled ? "New six-digit PIN" : "Six-digit PIN", text: $newPIN)
                    pinField("Confirm PIN", text: $confirmationPIN)

                    Button(model.appLockEnabled ? "Change app PIN" : "Set up app PIN") {
                        Task {
                            isWorking = true
                            defer { isWorking = false }
                            let saved: Bool
                            if model.appLockEnabled {
                                saved = await model.changeAppLockPIN(
                                    currentPIN: currentPIN,
                                    newPIN: newPIN,
                                    confirmation: confirmationPIN
                                )
                            } else {
                                saved = await model.setAppLockPIN(newPIN, confirmation: confirmationPIN)
                            }
                            currentPIN = ""
                            newPIN = ""
                            confirmationPIN = ""
                            if saved {
                                localMessage = "App PIN saved on this device."
                            }
                        }
                    }
                    .buttonStyle(IOSLockPrimaryButtonStyle())
                    .disabled(isWorking || !model.isValidAppLockPIN(newPIN) || newPIN != confirmationPIN || (model.appLockEnabled && !model.isValidAppLockPIN(currentPIN)))

                    if model.appLockEnabled {
                        Button {
                            Task { await changeBiometrics() }
                        } label: {
                            Label(
                                model.biometricUnlockEnabled ? "Turn off biometric unlock" : "Enable biometric unlock",
                                systemImage: model.biometricUnlockEnabled ? "faceid.slash" : "faceid"
                            )
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(IOSLockColors.teal)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorking || !model.isValidAppLockPIN(currentPIN))

                        Button("Disable app lock", role: .destructive) {
                            Task {
                                isWorking = true
                                defer { isWorking = false }
                                let disabled = await model.disableAppLock(currentPIN: currentPIN)
                                currentPIN = ""
                                if disabled {
                                    dismiss()
                                }
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .disabled(isWorking || !model.isValidAppLockPIN(currentPIN))
                    }

                    if let message = model.lockMessage ?? localMessage {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(model.lockMessage == nil ? IOSLockColors.teal : .red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(IOSLockColors.page.ignoresSafeArea())
            .navigationTitle("App lock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .disabled(isWorking)
                }
            }
        }
        .tint(IOSLockColors.teal)
    }

    private func pinField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text)
            .keyboardType(.numberPad)
            .padding(14)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .onChange(of: text.wrappedValue) { text.wrappedValue = sixDigitInput($0, limit: model.appLockPinLength) }
            .accessibilityLabel(title)
    }

    private func changeBiometrics() async {
        let enabling = !model.biometricUnlockEnabled
        if enabling {
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                localMessage = "Set up Face ID or Touch ID on this device before enabling biometric unlock."
                return
            }
            guard await evaluateBiometrics(context) else {
                localMessage = "Biometric verification did not complete."
                return
            }
        }
        isWorking = true
        defer { isWorking = false }
        let saved = await model.setBiometricUnlock(enabling, currentPIN: currentPIN)
        currentPIN = ""
        if saved {
            localMessage = enabling ? "Biometric unlock enabled." : "Biometric unlock disabled."
        }
    }

    private func evaluateBiometrics(_ context: LAContext) async -> Bool {
        defer { context.invalidate() }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Confirm your identity for Mizani app-lock settings"
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

struct IOSAccessShield: View {
    let title: String
    let message: String

    var body: some View {
        shieldContent
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isModal)
    }

    private var shieldContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(IOSLockColors.teal)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(IOSLockColors.ink)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(IOSLockColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IOSLockColors.page.ignoresSafeArea())
    }
}

struct IOSStorageRecoveryScreen: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(IOSLockColors.teal)
                .accessibilityHidden(true)
            Text("Secure storage unavailable")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(IOSLockColors.ink)
            Text(message ?? "Mizani could not safely open the local ledger. Your records have not been changed.")
                .font(.system(size: 14))
                .foregroundStyle(IOSLockColors.muted)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(IOSLockPrimaryButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(IOSLockColors.page.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}

struct IOSPrivacyShield: View {
    var body: some View {
        IOSAccessShield(title: "Mizani", message: "Your private financial information is hidden.")
            .allowsHitTesting(true)
    }
}

private struct IOSLockPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(IOSLockColors.teal.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
    }
}

private func sixDigitInput(_ value: String, limit: Int) -> String {
    String(value.filter { $0 >= "0" && $0 <= "9" }.prefix(limit))
}
