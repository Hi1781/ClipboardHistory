//
//  CryptoHelper.swift
//  ClipKit
//
//  加密与哈希工具
//

import Foundation
import CommonCrypto

public enum CryptoHelper {
    /// SHA-256 哈希（字符串）
    public static func sha256(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return sha256(data)
    }

    /// SHA-256 哈希（Data）
    public static func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// AES-256-CBC 加密
    /// - Parameters:
    ///   - data: 明文数据
    ///   - key: 32 字节密钥
    ///   - iv: 16 字节初始化向量
    public static func aesEncrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        crypt(data: data, key: key, iv: iv, operation: CCOperation(kCCEncrypt))
    }

    /// AES-256-CBC 解密
    public static func aesDecrypt(_ data: Data, key: Data, iv: Data) -> Data? {
        crypt(data: data, key: key, iv: iv, operation: CCOperation(kCCDecrypt))
    }

    /// 从密码派生 32 字节密钥（PBKDF2）
    public static func deriveKey(password: String, salt: Data, iterations: UInt32 = 10_000) -> Data? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        var derivedKey = [UInt8](repeating: 0, count: kCCKeySizeAES256)
        let result = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password,
            passwordData.count,
            Array(salt),
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            iterations,
            &derivedKey,
            derivedKey.count
        )
        guard result == kCCSuccess else { return nil }
        return Data(derivedKey)
    }

    /// 生成随机字节
    public static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    // MARK: - Private

    private static func crypt(data: Data, key: Data, iv: Data, operation: CCOperation) -> Data? {
        guard key.count == kCCKeySizeAES256, iv.count == kCCBlockSizeAES128 else { return nil }
        var output = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var outputLength = 0
        let status = CCCrypt(
            operation,
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            Array(key), key.count,
            Array(iv),
            Array(data), data.count,
            &output, output.count,
            &outputLength
        )
        guard status == kCCSuccess else { return nil }
        return Data(output.prefix(outputLength))
    }
}
