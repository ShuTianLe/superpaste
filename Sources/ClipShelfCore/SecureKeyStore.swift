import CryptoKit
import Foundation
import Security

public protocol SymmetricKeyProviding {
    func loadOrCreateKey() throws -> SymmetricKey
}

public final class KeychainKeyStore: SymmetricKeyProviding {
    private let service: String
    private let account: String

    public init(service: String = "io.clipshelf.local", account: String = "master-key") {
        self.service = service
        self.account = account
    }

    public func loadOrCreateKey() throws -> SymmetricKey {
        if let data = try loadKeyData() {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.rawRepresentation
        try saveKeyData(data)
        return key
    }

    private func loadKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw ClipShelfError.keychain("SecItemCopyMatching failed with status \(status)")
        }
        return item as? Data
    }

    private func saveKeyData(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let lookup: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let update: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw ClipShelfError.keychain("SecItemUpdate failed with status \(updateStatus)")
            }
            return
        }
        guard status == errSecSuccess else {
            throw ClipShelfError.keychain("SecItemAdd failed with status \(status)")
        }
    }
}

public struct StaticKeyStore: SymmetricKeyProviding {
    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public func loadOrCreateKey() throws -> SymmetricKey {
        key
    }
}

public extension SymmetricKey {
    var rawRepresentation: Data {
        withUnsafeBytes { Data($0) }
    }
}
