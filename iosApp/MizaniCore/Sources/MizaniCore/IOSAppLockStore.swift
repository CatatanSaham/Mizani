import Foundation
import Security
#if canImport(CommonCrypto)
import CommonCrypto
#endif

public enum IOSAppLockStoreError: Error, Equatable {
    case invalidPIN
    case invalidIterationCount
    case alreadyConfigured
    case malformedStoredState
    case keychainStatus(Int32)
    case randomGenerationFailed(Int32)
    case keyDerivationFailed(Int32)
}

public enum IOSPINVerificationResult: Equatable, Sendable {
    case success
    case incorrect
    case blocked(remainingMilliseconds: Int64)
    case notConfigured
}

public struct IOSAppLockStatus: Equatable, Sendable {
    public let isEnabled: Bool
    public let biometricEnabled: Bool
    public let failedAttempts: Int32
    public let lastFailureAtMilliseconds: Int64
    public let backoffRemainingMilliseconds: Int64
}

public typealias IOSPINValidationRule = @Sendable (String) -> Bool
public typealias IOSPINBackoffRule = @Sendable (Int32, Int64, Int64) -> Int64

/// Stores a salted PIN verifier and retry state in a device-only, passcode-protected Keychain item.
public actor IOSAppLockStore {
    private struct StoredRecord: Codable {
        let version: Int
        let iterations: Int
        let salt: Data
        let verifier: Data
        var failedAttempts: Int32
        var lastFailureAtMilliseconds: Int64
        var biometricEnabled: Bool
    }

    private let service: String
    private let iterations: Int
    private let isValidPIN: IOSPINValidationRule
    private let backoffRemaining: IOSPINBackoffRule
    private let secureValues: any IOSAppLockSecureValueStoring

    public init(
        service: String,
        pbkdf2Iterations: Int,
        isValidPIN: @escaping IOSPINValidationRule,
        backoffRemaining: @escaping IOSPINBackoffRule
    ) {
        self.service = service
        self.iterations = pbkdf2Iterations
        self.isValidPIN = isValidPIN
        self.backoffRemaining = backoffRemaining
        self.secureValues = SystemIOSAppLockSecureValueStore()
    }

    init(
        service: String,
        pbkdf2Iterations: Int,
        isValidPIN: @escaping IOSPINValidationRule,
        backoffRemaining: @escaping IOSPINBackoffRule,
        secureValues: any IOSAppLockSecureValueStoring
    ) {
        self.service = service
        self.iterations = pbkdf2Iterations
        self.isValidPIN = isValidPIN
        self.backoffRemaining = backoffRemaining
        self.secureValues = secureValues
    }

    public func status(nowMilliseconds: Int64) throws -> IOSAppLockStatus {
        guard let record = try readRecord() else {
            return IOSAppLockStatus(
                isEnabled: false,
                biometricEnabled: false,
                failedAttempts: 0,
                lastFailureAtMilliseconds: 0,
                backoffRemainingMilliseconds: 0
            )
        }
        return IOSAppLockStatus(
            isEnabled: true,
            biometricEnabled: record.biometricEnabled,
            failedAttempts: record.failedAttempts,
            lastFailureAtMilliseconds: record.lastFailureAtMilliseconds,
            backoffRemainingMilliseconds: backoffRemaining(
                record.failedAttempts,
                record.lastFailureAtMilliseconds,
                nowMilliseconds
            )
        )
    }

    public func setPIN(_ pin: String) throws {
        guard isValidPIN(pin) else { throw IOSAppLockStoreError.invalidPIN }
        let existingRecord = try readRecord()
        guard case nil = existingRecord else { throw IOSAppLockStoreError.alreadyConfigured }
        try storePIN(pin)
    }

    private func storePIN(_ pin: String) throws {
        guard iterations > 0, iterations <= Self.maximumSupportedIterations else {
            throw IOSAppLockStoreError.invalidIterationCount
        }
        let salt = try Self.randomSalt()
        var verifier = try Self.deriveVerifier(pin, salt: salt, iterations: iterations)
        defer { verifier.resetBytes(in: 0..<verifier.count) }
        let record = StoredRecord(
            version: 1,
            iterations: iterations,
            salt: salt,
            verifier: verifier,
            failedAttempts: 0,
            lastFailureAtMilliseconds: 0,
            biometricEnabled: false
        )
        try write(record)
    }

    public func verifyPIN(_ pin: String, nowMilliseconds: Int64) throws -> IOSPINVerificationResult {
        guard var record = try readRecord() else { return .notConfigured }
        let blockedFor = backoffRemaining(
            record.failedAttempts,
            record.lastFailureAtMilliseconds,
            nowMilliseconds
        )
        if blockedFor > 0 { return .blocked(remainingMilliseconds: blockedFor) }
        guard isValidPIN(pin) else {
            recordFailedAttempt(&record, nowMilliseconds: nowMilliseconds)
            try write(record)
            return .incorrect
        }

        var candidate = try Self.deriveVerifier(pin, salt: record.salt, iterations: record.iterations)
        defer { candidate.resetBytes(in: 0..<candidate.count) }
        guard Self.constantTimeEqual(candidate, record.verifier) else {
            recordFailedAttempt(&record, nowMilliseconds: nowMilliseconds)
            try write(record)
            return .incorrect
        }

        record.failedAttempts = 0
        record.lastFailureAtMilliseconds = 0
        try write(record)
        return .success
    }

    public func changePIN(
        currentPIN: String,
        newPIN: String,
        nowMilliseconds: Int64
    ) throws -> IOSPINVerificationResult {
        guard isValidPIN(newPIN) else { throw IOSAppLockStoreError.invalidPIN }
        let verification = try verifyPIN(currentPIN, nowMilliseconds: nowMilliseconds)
        guard verification == .success else { return verification }
        try storePIN(newPIN)
        return .success
    }

    public func setBiometricEnabled(
        _ enabled: Bool,
        requiringPIN pin: String,
        nowMilliseconds: Int64
    ) throws -> IOSPINVerificationResult {
        let verification = try verifyPIN(pin, nowMilliseconds: nowMilliseconds)
        guard verification == .success else { return verification }
        guard var record = try readRecord() else { return .notConfigured }
        record.biometricEnabled = enabled
        try write(record)
        return .success
    }

    /// Clears PIN retry state after LocalAuthentication has independently succeeded.
    /// Call only from the native app after a biometric-only authentication prompt succeeds.
    public func recordBiometricAuthenticationSuccess() throws -> Bool {
        guard var record = try readRecord(), record.biometricEnabled else { return false }
        record.failedAttempts = 0
        record.lastFailureAtMilliseconds = 0
        try write(record)
        return true
    }

    public func disable(requiringPIN pin: String, nowMilliseconds: Int64) throws -> IOSPINVerificationResult {
        let verification = try verifyPIN(pin, nowMilliseconds: nowMilliseconds)
        guard verification == .success else { return verification }
        try secureValues.delete(service: service, account: Self.account)
        return .success
    }

    private func recordFailedAttempt(_ record: inout StoredRecord, nowMilliseconds: Int64) {
        if record.failedAttempts < Int32.max {
            record.failedAttempts += 1
        }
        record.lastFailureAtMilliseconds = nowMilliseconds
    }

    private func readRecord() throws -> StoredRecord? {
        guard let data = try secureValues.read(service: service, account: Self.account) else { return nil }
        guard let record = try? PropertyListDecoder().decode(StoredRecord.self, from: data),
              record.version == 1,
              record.iterations > 0,
              record.iterations <= Self.maximumSupportedIterations,
              record.salt.count == Self.saltLength,
              record.verifier.count == Self.verifierLength,
              record.failedAttempts >= 0,
              record.lastFailureAtMilliseconds >= 0 else {
            throw IOSAppLockStoreError.malformedStoredState
        }
        return record
    }

    private func write(_ record: StoredRecord) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try secureValues.write(encoder.encode(record), service: service, account: Self.account)
    }

    private static func randomSalt() throws -> Data {
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, bytes.count, baseAddress)
        }
        guard status == errSecSuccess else {
            salt.resetBytes(in: 0..<salt.count)
            throw IOSAppLockStoreError.randomGenerationFailed(status)
        }
        return salt
    }

    private static func deriveVerifier(_ pin: String, salt: Data, iterations: Int) throws -> Data {
        guard iterations > 0, iterations <= maximumSupportedIterations else {
            throw IOSAppLockStoreError.invalidIterationCount
        }
        var derived = Data(count: verifierLength)
        let status = pin.withCString { password in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBytes { outputBytes in
                    guard let saltAddress = saltBytes.bindMemory(to: UInt8.self).baseAddress,
                          let outputAddress = outputBytes.bindMemory(to: UInt8.self).baseAddress else {
                        return Int32(kCCParamError)
                    }
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        password,
                        pin.utf8.count,
                        saltAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        outputAddress,
                        derived.count
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            derived.resetBytes(in: 0..<derived.count)
            throw IOSAppLockStoreError.keyDerivationFailed(status)
        }
        return derived
    }

    private static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<left.count {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }

    private static let account = "app-lock-pin-v1"
    private static let saltLength = 16
    private static let verifierLength = 32
    private static let maximumSupportedIterations = 1_000_000
}

protocol IOSAppLockSecureValueStoring: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ value: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

private struct SystemIOSAppLockSecureValueStore: IOSAppLockSecureValueStoring {
    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw IOSAppLockStoreError.keychainStatus(status)
        }
        return data
    }

    func write(_ value: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let attributes = [kSecValueData as String: value] as CFDictionary
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw IOSAppLockStoreError.keychainStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = value
        #if os(iOS)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        #else
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        item[kSecUseDataProtectionKeychain as String] = true
        #endif
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes)
            guard retryStatus == errSecSuccess else {
                throw IOSAppLockStoreError.keychainStatus(retryStatus)
            }
            return
        }
        guard addStatus == errSecSuccess else { throw IOSAppLockStoreError.keychainStatus(addStatus) }
    }

    func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw IOSAppLockStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}
