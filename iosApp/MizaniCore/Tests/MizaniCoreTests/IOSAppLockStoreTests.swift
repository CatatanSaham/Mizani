import Foundation
import XCTest
@testable import MizaniCore

final class IOSAppLockStoreTests: XCTestCase {
    func testPINVerifierIsNotStoredAsPlaintextAndSurvivesStoreRecreation() async throws {
        let secureValues = MemoryAppLockSecureValues()
        let store = makeStore(secureValues: secureValues)
        try await store.setPIN("012345")

        let encoded = try XCTUnwrap(secureValues.read(service: "lock-tests", account: "app-lock-pin-v1"))
        XCTAssertNil(encoded.range(of: Data("012345".utf8)))

        let reopened = makeStore(secureValues: secureValues)
        let verification = try await reopened.verifyPIN("012345", nowMilliseconds: 10_000)
        let status = try await reopened.status(nowMilliseconds: 10_000)
        XCTAssertEqual(verification, .success)
        XCTAssertEqual(status.isEnabled, true)
    }

    func testWrongPINBackoffPersistsAndExpires() async throws {
        let secureValues = MemoryAppLockSecureValues()
        let store = IOSAppLockStore(
            service: "lock-tests",
            pbkdf2Iterations: 50,
            isValidPIN: Self.isValidPIN,
            backoffRemaining: Self.testBackoff,
            secureValues: secureValues
        )
        try await store.setPIN("123456")
        let firstFailure = try await store.verifyPIN("000000", nowMilliseconds: 20_000)
        let secondFailure = try await store.verifyPIN("000000", nowMilliseconds: 20_000)
        XCTAssertEqual(firstFailure, .incorrect)
        XCTAssertEqual(secondFailure, .incorrect)

        let reopened = IOSAppLockStore(
            service: "lock-tests",
            pbkdf2Iterations: 50,
            isValidPIN: Self.isValidPIN,
            backoffRemaining: Self.testBackoff,
            secureValues: secureValues
        )
        let blocked = try await reopened.verifyPIN("123456", nowMilliseconds: 20_000)
        let succeeded = try await reopened.verifyPIN("123456", nowMilliseconds: 25_000)
        XCTAssertEqual(blocked, .blocked(remainingMilliseconds: 5_000))
        XCTAssertEqual(succeeded, .success)
        let status = try await reopened.status(nowMilliseconds: 25_000)
        XCTAssertEqual(status.failedAttempts, 0)
        XCTAssertEqual(status.backoffRemainingMilliseconds, 0)
    }

    func testBiometricPreferenceAndDisableRequireAValidPIN() async throws {
        let secureValues = MemoryAppLockSecureValues()
        let store = makeStore(secureValues: secureValues)
        try await store.setPIN("654321")

        let wrongToggle = try await store.setBiometricEnabled(
            true,
            requiringPIN: "111111",
            nowMilliseconds: 1_000
        )
        let enabled = try await store.setBiometricEnabled(
            true,
            requiringPIN: "654321",
            nowMilliseconds: 2_000
        )
        let enabledStatus = try await store.status(nowMilliseconds: 2_000)
        let disabled = try await store.disable(requiringPIN: "654321", nowMilliseconds: 3_000)
        let disabledStatus = try await store.status(nowMilliseconds: 3_000)
        let afterDisable = try await store.verifyPIN("654321", nowMilliseconds: 3_000)
        XCTAssertEqual(wrongToggle, .incorrect)
        XCTAssertEqual(enabled, .success)
        XCTAssertEqual(enabledStatus.biometricEnabled, true)
        XCTAssertEqual(disabled, .success)
        XCTAssertEqual(disabledStatus.isEnabled, false)
        XCTAssertEqual(afterDisable, .notConfigured)
    }

    func testBiometricAuthenticationSuccessClearsPINRetryState() async throws {
        let secureValues = MemoryAppLockSecureValues()
        let store = IOSAppLockStore(
            service: "lock-tests",
            pbkdf2Iterations: 50,
            isValidPIN: Self.isValidPIN,
            backoffRemaining: Self.testBackoff,
            secureValues: secureValues
        )
        try await store.setPIN("123456")
        _ = try await store.setBiometricEnabled(true, requiringPIN: "123456", nowMilliseconds: 1_000)
        _ = try await store.verifyPIN("000000", nowMilliseconds: 2_000)
        _ = try await store.verifyPIN("000000", nowMilliseconds: 2_000)

        let beforeBiometric = try await store.status(nowMilliseconds: 2_000)
        let biometricAccepted = try await store.recordBiometricAuthenticationSuccess()
        let afterBiometric = try await store.status(nowMilliseconds: 2_000)
        let wrongPINAfterBiometric = try await store.verifyPIN("000000", nowMilliseconds: 2_000)

        XCTAssertEqual(beforeBiometric.backoffRemainingMilliseconds, 5_000)
        XCTAssertTrue(biometricAccepted)
        XCTAssertEqual(afterBiometric.failedAttempts, 0)
        XCTAssertEqual(afterBiometric.backoffRemainingMilliseconds, 0)
        XCTAssertEqual(wrongPINAfterBiometric, .incorrect)
    }

    func testSettingPINCannotReplaceAnExistingPINWithoutVerification() async throws {
        let store = makeStore(secureValues: MemoryAppLockSecureValues())
        try await store.setPIN("123456")

        do {
            try await store.setPIN("654321")
            XCTFail("An existing app-lock PIN must not be replaced through initial setup.")
        } catch {
            XCTAssertEqual(error as? IOSAppLockStoreError, .alreadyConfigured)
        }

        let originalPIN = try await store.verifyPIN("123456", nowMilliseconds: 5_000)
        XCTAssertEqual(originalPIN, .success)
    }

    func testUnsupportedPBKDF2WorkFactorIsRejected() async throws {
        let store = IOSAppLockStore(
            service: "lock-tests",
            pbkdf2Iterations: Int.max,
            isValidPIN: Self.isValidPIN,
            backoffRemaining: Self.testBackoff,
            secureValues: MemoryAppLockSecureValues()
        )

        do {
            try await store.setPIN("123456")
            XCTFail("An unsupported work factor must not be persisted.")
        } catch {
            XCTAssertEqual(error as? IOSAppLockStoreError, .invalidIterationCount)
        }
    }

    func testMalformedSecureStateFailsClosed() async throws {
        let secureValues = MemoryAppLockSecureValues()
        secureValues.write(Data("not-a-lock-record".utf8), service: "lock-tests", account: "app-lock-pin-v1")
        let store = makeStore(secureValues: secureValues)

        do {
            _ = try await store.status(nowMilliseconds: 1_000)
            XCTFail("Malformed lock state must prevent the app from treating lock as disabled.")
        } catch {
            XCTAssertEqual(error as? IOSAppLockStoreError, .malformedStoredState)
        }
    }

    func testChangingPINRequiresTheCurrentPINAndResetsRetryState() async throws {
        let secureValues = MemoryAppLockSecureValues()
        let store = makeStore(secureValues: secureValues)
        try await store.setPIN("123456")
        _ = try await store.verifyPIN("000000", nowMilliseconds: 1_000)

        let rejectedChange = try await store.changePIN(
            currentPIN: "000000",
            newPIN: "654321",
            nowMilliseconds: 2_000
        )
        let acceptedChange = try await store.changePIN(
            currentPIN: "123456",
            newPIN: "654321",
            nowMilliseconds: 3_000
        )
        let oldPIN = try await store.verifyPIN("123456", nowMilliseconds: 4_000)
        let newPIN = try await store.verifyPIN("654321", nowMilliseconds: 5_000)
        XCTAssertEqual(rejectedChange, .incorrect)
        XCTAssertEqual(acceptedChange, .success)
        XCTAssertEqual(oldPIN, .incorrect)
        XCTAssertEqual(newPIN, .success)
    }

    private func makeStore(secureValues: MemoryAppLockSecureValues) -> IOSAppLockStore {
        IOSAppLockStore(
            service: "lock-tests",
            pbkdf2Iterations: 100,
            isValidPIN: Self.isValidPIN,
            backoffRemaining: Self.testBackoff,
            secureValues: secureValues
        )
    }

    private static let isValidPIN: IOSPINValidationRule = { pin in
        pin.count == 6 && pin.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static let testBackoff: IOSPINBackoffRule = { failures, lastFailureAt, now in
        guard failures >= 2, lastFailureAt > 0, now >= lastFailureAt else { return 0 }
        return max(5_000 - (now - lastFailureAt), 0)
    }
}

private final class MemoryAppLockSecureValues: IOSAppLockSecureValueStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func read(service: String, account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values["\(service):\(account)"]
    }

    func write(_ value: Data, service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values["\(service):\(account)"] = value
    }

    func delete(service: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: "\(service):\(account)")
    }
}
