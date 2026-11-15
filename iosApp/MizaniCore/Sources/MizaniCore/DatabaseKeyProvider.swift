import Foundation
import Security

public protocol DatabaseKeyProviding {
    /// Returns exactly 32 random key bytes, creating them only for a new database.
    func databaseKey(for databaseURL: URL) throws -> Data
}

public enum DatabaseKeyError: Error, Equatable {
    case missingKeyForExistingDatabase
    case keychainStatus(Int32)
    case randomGenerationFailed(Int32)
}

public struct KeychainDatabaseKeyProvider: DatabaseKeyProviding {
    private let service: String
    private let keychain: any KeychainValueStoring

    public init(service: String) {
        self.service = service
        self.keychain = SystemKeychainValueStore()
    }

    init(service: String, keychain: any KeychainValueStoring) {
        self.service = service
        self.keychain = keychain
    }

    public func databaseKey(for databaseURL: URL) throws -> Data {
        if let key = try keychain.read(service: service, account: Self.account) {
            return key
        }

        guard !Self.hasDatabaseFiles(at: databaseURL) else {
            throw DatabaseKeyError.missingKeyForExistingDatabase
        }

        var generatedKey = Data(count: 32)
        let randomStatus = generatedKey.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            generatedKey.resetBytes(in: 0..<generatedKey.count)
            throw DatabaseKeyError.randomGenerationFailed(randomStatus)
        }

        do {
            try keychain.write(generatedKey, service: service, account: Self.account)
            return generatedKey
        } catch KeychainValueStoreError.duplicateItem {
            generatedKey.resetBytes(in: 0..<generatedKey.count)
            guard let winningKey = try keychain.read(service: service, account: Self.account) else {
                throw DatabaseKeyError.keychainStatus(errSecItemNotFound)
            }
            return winningKey
        } catch {
            generatedKey.resetBytes(in: 0..<generatedKey.count)
            throw error
        }
    }

    private static let account = "sqlcipher-database-key-v1"

    private static func hasDatabaseFiles(at databaseURL: URL) -> Bool {
        let fileManager = FileManager.default
        let paths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm",
            databaseURL.path + "-journal",
        ]
        return paths.contains { fileManager.fileExists(atPath: $0) }
    }
}

protocol KeychainValueStoring {
    func read(service: String, account: String) throws -> Data?
    func write(_ value: Data, service: String, account: String) throws
}

enum KeychainValueStoreError: Error {
    case duplicateItem
    case status(Int32)
}

private struct SystemKeychainValueStore: KeychainValueStoring {
    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw DatabaseKeyError.keychainStatus(status)
        }
        guard let key = result as? Data, key.count == 32 else {
            throw DatabaseKeyError.keychainStatus(errSecDecode)
        }
        return key
    }

    func write(_ value: Data, service: String, account: String) throws {
        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = value
        #if os(iOS)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        #else
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecUseDataProtectionKeychain as String] = true
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            throw KeychainValueStoreError.duplicateItem
        }
        guard status == errSecSuccess else {
            throw DatabaseKeyError.keychainStatus(status)
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
