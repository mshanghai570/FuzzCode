import Foundation
import Security

/// Thread-safe Native iOS Keychain wrapper using Apple Security framework.
/// Enforces strong security attributes: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
/// Never logs secrets or returns raw credentials in plaintext diagnostic dumps.
public final class KeychainService: Sendable {
    public static let shared = KeychainService()
    
    private let serviceIdentifier = "com.fuzzcode.ios.keychain"
    
    public init() {}
    
    public enum KeychainError: Error, LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case dataConversionFailed
        
        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "The requested credential was not found in the Keychain."
            case .duplicateItem:
                return "A credential with this key already exists in the Keychain."
            case .unexpectedStatus(let status):
                return "Keychain operation failed with OSStatus \(status)."
            case .dataConversionFailed:
                return "Failed to convert string data to UTF-8 Keychain representation."
            }
        }
    }
    
    /// Stores or updates a secret key in the iOS Keychain.
    @discardableResult
    public func save(key: String, secret: String) -> Result<Void, KeychainError> {
        guard let data = secret.data(using: .utf8) else {
            return .failure(.dataConversionFailed)
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        
        // Check if item exists
        let checkStatus = SecItemCopyMatching(query as CFDictionary, nil)
        
        if checkStatus == errSecSuccess {
            // Update existing item
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus == errSecSuccess {
                return .success(())
            } else {
                return .failure(.unexpectedStatus(updateStatus))
            }
        } else if checkStatus == errSecItemNotFound {
            // Add new item
            var newAttributes = query
            newAttributes[kSecValueData as String] = data
            newAttributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            
            let addStatus = SecItemAdd(newAttributes as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return .success(())
            } else {
                return .failure(.unexpectedStatus(addStatus))
            }
        } else {
            return .failure(.unexpectedStatus(checkStatus))
        }
    }
    
    /// Retrieves a secret string from the iOS Keychain.
    public func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess, let data = dataTypeRef as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    /// Deletes a key from the iOS Keychain.
    @discardableResult
    public func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Utility to sanitize and redact any secret strings for logging or diagnostic views.
    public static func redactSecret(_ secret: String?) -> String {
        guard let secret = secret, !secret.isEmpty else { return "[None]" }
        if secret.count <= 6 {
            return "••••••"
        }
        let prefix = secret.prefix(3)
        let suffix = secret.suffix(3)
        return "\(prefix)••••\(suffix) (\(secret.count) chars)"
    }
}
