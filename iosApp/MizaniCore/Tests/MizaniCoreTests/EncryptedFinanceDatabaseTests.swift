import Foundation
import XCTest
@testable import MizaniCore

final class EncryptedFinanceDatabaseTests: XCTestCase {
    func testDatabaseEncryptsRecordsAndReopensWithTheSameKey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MizaniCoreTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("mizani.sqlite")
        let keychain = MemoryKeychainValueStore()
        let keyProvider = KeychainDatabaseKeyProvider(service: "MizaniCoreTests", keychain: keychain)
        let marker = "mizani-private-record-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = try EncryptedFinanceDatabase(databaseDirectoryURL: directory, keyProvider: keyProvider)
        let journalMode = try await database.textForTesting("PRAGMA journal_mode;")
        XCTAssertEqual(journalMode, "wal")
        try await database.executeForTesting("PRAGMA wal_autocheckpoint = 0;")
        try await database.executeForTesting(
            "CREATE TABLE test_private_values (value TEXT NOT NULL); " +
                "INSERT INTO test_private_values(value) VALUES ('\(marker)');"
        )

        let markerBytes = Data(marker.utf8)
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        XCTAssertTrue(FileManager.default.fileExists(atPath: walURL.path))
        for path in [databaseURL.path, walURL.path, databaseURL.path + "-shm"] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let fileBytes = try Data(contentsOf: URL(fileURLWithPath: path))
            XCTAssertNil(fileBytes.range(of: markerBytes))
        }
        try await database.close()

        let bytes = try Data(contentsOf: databaseURL)
        XCTAssertFalse(bytes.starts(with: Data("SQLite format 3".utf8)))

        let reopened = try EncryptedFinanceDatabase(databaseDirectoryURL: directory, keyProvider: keyProvider)
        let storedMarker = try await reopened.textForTesting("SELECT value FROM test_private_values;")
        XCTAssertEqual(storedMarker, marker)
        try await reopened.close()
    }

    func testExistingDatabaseWithoutKeyFailsClosed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MizaniCoreTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("ledger.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalProvider = KeychainDatabaseKeyProvider(
            service: "MizaniCoreTests",
            keychain: MemoryKeychainValueStore()
        )
        let originalDatabase = try EncryptedFinanceDatabase(databaseDirectoryURL: directory, keyProvider: originalProvider)
        try await originalDatabase.close()

        XCTAssertThrowsError(
            try EncryptedFinanceDatabase(
                databaseDirectoryURL: directory,
                keyProvider: KeychainDatabaseKeyProvider(
                    service: "MizaniCoreTests-Missing",
                    keychain: MemoryKeychainValueStore()
                )
            )
        ) { error in
            XCTAssertEqual(error as? DatabaseKeyError, .missingKeyForExistingDatabase)
        }
    }

    func testProviderCreatesAndReusesAKeyOnlyForANewDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MizaniCoreTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("ledger.sqlite")
        let provider = KeychainDatabaseKeyProvider(
            service: "MizaniCoreTests-NewKey",
            keychain: MemoryKeychainValueStore()
        )

        let firstKey = try provider.databaseKey(for: databaseURL)
        let secondKey = try provider.databaseKey(for: databaseURL)

        XCTAssertEqual(firstKey.count, 32)
        XCTAssertEqual(secondKey, firstKey)
    }

    func testProviderFailsClosedWhenOnlyAWalFileRemains() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MizaniCoreTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data([0x01, 0x02, 0x03]).write(to: URL(fileURLWithPath: databaseURL.path + "-wal"))
        let provider = KeychainDatabaseKeyProvider(
            service: "MizaniCoreTests-WalOnly",
            keychain: MemoryKeychainValueStore()
        )

        XCTAssertThrowsError(try provider.databaseKey(for: databaseURL)) { error in
            XCTAssertEqual(error as? DatabaseKeyError, .missingKeyForExistingDatabase)
        }
    }

    func testWrongKeyCannotReadExistingDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MizaniCoreTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("ledger.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let correctKey = FixedDatabaseKeyProvider(key: Data(repeating: 0x2A, count: 32))
        let database = try EncryptedFinanceDatabase(databaseDirectoryURL: directory, keyProvider: correctKey)
        try await database.close()

        XCTAssertThrowsError(
            try EncryptedFinanceDatabase(
                databaseDirectoryURL: directory,
                keyProvider: FixedDatabaseKeyProvider(key: Data(repeating: 0x3B, count: 32))
            )
        )
    }

    func testTamperedDatabaseCannotBeOpened() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MizaniCoreTests-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("ledger.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyProvider = FixedDatabaseKeyProvider(key: Data(repeating: 0x2A, count: 32))
        let database = try EncryptedFinanceDatabase(databaseDirectoryURL: directory, keyProvider: keyProvider)
        try await database.executeForTesting(
            "CREATE TABLE tampered_values (value TEXT NOT NULL); " +
                "INSERT INTO tampered_values(value) VALUES ('authentic-page-data');"
        )
        try await database.close()

        var bytes = try Data(contentsOf: databaseURL)
        XCTAssertGreaterThanOrEqual(bytes.count, 4096)
        // Page one contains sqlite_master and is read during open; alter its authentication area.
        bytes[4095] ^= 0xFF
        try bytes.write(to: databaseURL, options: .atomic)

        XCTAssertThrowsError(try EncryptedFinanceDatabase(databaseDirectoryURL: directory, keyProvider: keyProvider))
    }
}

private struct FixedDatabaseKeyProvider: DatabaseKeyProviding {
    let key: Data

    func databaseKey(for databaseURL: URL) throws -> Data { key }
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
