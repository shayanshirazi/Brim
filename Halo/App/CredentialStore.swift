import Foundation
import Security

enum CredentialStoreError: Error {
    case couldNotEncodeToken
    case keychainStatus(OSStatus)
}

final class CredentialStore {
    static let shared = CredentialStore()

    private let service = "dev.halo.api-token"

    private init() {}

    func saveAPIToken(_ token: String, accountID: UUID) throws -> String {
        let credentialID = accountID.uuidString
        guard let data = token.data(using: .utf8) else {
            throw CredentialStoreError.couldNotEncodeToken
        }

        deleteAPIToken(credentialID: credentialID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainStatus(status)
        }

        return credentialID
    }

    func hasAPIToken(credentialID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func deleteAPIToken(credentialID: String?) {
        guard let credentialID else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID
        ]

        SecItemDelete(query as CFDictionary)
    }
}
