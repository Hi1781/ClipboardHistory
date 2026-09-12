//
//  KeychainHelper.swift
//  ClipKit
//
//  v2.0：使用 Keychain 安全存储本地加密主密钥
//

import Foundation
import Security

public enum KeychainHelper {

    /// App Group 共享的 Keychain access group（与 entitlements 配合；无 group 时回退默认）
    public static var accessGroup: String? = nil
    /// 服务名 / 账户名
    public static let service = "com.clipboard.history.crypto"
    public static let masterKeyAccount = "local-master-key-v2"

    // MARK: - 通用读写

    /// 读取一个 generic password 条目
    @discardableResult
    public static func read(account: String, service: String = service) -> Data? {
        var query = baseQuery(account: account, service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        query[kSecUseDataProtectionKeychain as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    /// 写入（不存在则新增，存在则更新）
    @discardableResult
    public static func write(_ data: Data, account: String, service: String = service) -> Bool {
        var query = baseQuery(account: account, service: service)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecParam { return false }

        // 不存在 → 新增
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        query[kSecUseDataProtectionKeychain as String] = true
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// 删除
    @discardableResult
    public static func delete(account: String, service: String = service) -> Bool {
        let query = baseQuery(account: account, service: service)
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }

    // MARK: - 主密钥管理

    /// 获取本地 32 字节 AES-256 主密钥；不存在则生成并写入 Keychain
    public static func masterKey() -> Data {
        if let existing = read(account: masterKeyAccount), existing.count == 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let key = Data(bytes)
        if write(key, account: masterKeyAccount) {
            return key
        }
        // Keychain 不可用（极端情况，例如扩展未授予权限）→ 退化为 PBKDF2 派生固定密钥
        let salt = "ClipSalt_2024".data(using: .utf8)!
        return CryptoHelper.deriveKey(password: "ClipboardHistoryLocalKey_v1", salt: salt) ?? key
    }
}
