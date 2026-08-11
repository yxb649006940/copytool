import Foundation
import CryptoKit
import Security

/// 使用存放在 Keychain 中的随机密钥加密剪贴板历史。
nonisolated final class HistoryCrypto: @unchecked Sendable {
    static let shared = HistoryCrypto()

    private enum CryptoError: Error {
        case keychain(OSStatus)
        case invalidSealedData
    }

    private let service = "yxb.copytool.history"
    private let account = "encryption-key"
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?

    private init() {}

    func encrypt(_ data: Data) throws -> Data {
        try Self.encrypt(data, using: try encryptionKey())
    }

    func decrypt(_ data: Data) throws -> Data {
        try Self.decrypt(data, using: try encryptionKey())
    }

    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw CryptoError.invalidSealedData
        }
        return combined
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func encryptionKey() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }

        if let cachedKey {
            return cachedKey
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let keyData = result as? Data {
            let key = SymmetricKey(data: keyData)
            cachedKey = key
            return key
        }
        guard status == errSecItemNotFound else {
            throw CryptoError.keychain(status)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: keyData
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CryptoError.keychain(addStatus)
        }

        cachedKey = key
        return key
    }
}
