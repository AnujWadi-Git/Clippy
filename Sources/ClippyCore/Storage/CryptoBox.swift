import Foundation
import CryptoKit
import Security

/// AES-256-GCM sealing for long-lived (pinned) content. Key lives in the Keychain.
public struct CryptoBox: Sendable {
    private let key: SymmetricKey
    static let prefix = "enc1:"

    public init(key: SymmetricKey) { self.key = key }

    /// Loads (or creates) the key in the login Keychain. Returns nil if Keychain is unavailable.
    public static func keychainBacked(service: String = "com.anujwadi.Clippy", account: String = "pinned-content-key") -> CryptoBox? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let d = out as? Data, d.count == 32 {
            return CryptoBox(key: SymmetricKey(data: d))
        }
        let k = SymmetricKey(size: .bits256)
        let data = k.withUnsafeBytes { Data($0) }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return nil }
        return CryptoBox(key: k)
    }

    public func seal(_ s: String) -> String {
        guard let box = try? AES.GCM.seal(Data(s.utf8), using: key), let c = box.combined else { return s }
        return Self.prefix + c.base64EncodedString()
    }

    /// Returns the plaintext; non-sealed input is returned unchanged.
    public func open(_ s: String) -> String {
        guard s.hasPrefix(Self.prefix), let d = Data(base64Encoded: String(s.dropFirst(Self.prefix.count))),
              let box = try? AES.GCM.SealedBox(combined: d), let p = try? AES.GCM.open(box, using: key),
              let str = String(data: p, encoding: .utf8) else { return s }
        return str
    }

    public static func isSealed(_ s: String) -> Bool { s.hasPrefix(prefix) }
}
