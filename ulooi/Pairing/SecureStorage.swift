import Foundation
import Security

/// Thread-safe wrapper for Apple Keychain Services to persist sensitive pairing credentials.
/// Isolated strictly to this device, configured to prevent iCloud leakage.
public final class SecureStorage: @unchecked Sendable {
    
    public static let shared = SecureStorage()
    
    private let queue = DispatchQueue(label: "ulooi.secure_storage.queue", attributes: .concurrent)
    
    private init() {}
    
    // --- Keys ---
    private let clientStaticKeyAttr = "ulooi.client.static_private_key"
    private let serverStaticKeyAttr = "ulooi.server.static_public_key"
    private let authTokenAttr = "ulooi.auth_token"
    private let serverNameAttr = "ulooi.paired_server_name"
    
    // --- Public Getters & Setters ---
    
    public var clientStaticPrivateKey: Data? {
        get { read(key: clientStaticKeyAttr) }
        set { write(key: clientStaticKeyAttr, value: newValue) }
    }
    
    public var serverStaticPublicKey: Data? {
        get { read(key: serverStaticKeyAttr) }
        set { write(key: serverStaticKeyAttr, value: newValue) }
    }
    
    public var authToken: Data? {
        get { read(key: authTokenAttr) }
        set { write(key: authTokenAttr, value: newValue) }
    }
    
    public var pairedServerName: String? {
        get {
            guard let data = read(key: serverNameAttr) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let data = newValue?.data(using: .utf8)
            write(key: serverNameAttr, value: data)
        }
    }
    
    public var isPaired: Bool {
        authToken != nil && serverStaticPublicKey != nil
    }
    
    public func wipeCredentials() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self.delete(key: self.clientStaticKeyAttr)
            self.delete(key: self.serverStaticKeyAttr)
            self.delete(key: self.authTokenAttr)
            self.delete(key: self.serverNameAttr)
        }
    }
    
    // --- Low-Level Keychain Access ---
    
    private func read(key: String) -> Data? {
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var dataTypeRef: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
            
            if status == errSecSuccess {
                return dataTypeRef as? Data
            }
            return nil
        }
    }
    
    private func write(key: String, value: Data?) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            
            self.delete(key: key)
            
            guard let value = value else { return }
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            
            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                print("❌ SecureStorage failed to write \(key): status \(status)")
            }
        }
    }
    
    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
