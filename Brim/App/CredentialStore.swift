import Foundation
import Security

enum CredentialStoreError: Error {
    case couldNotEncodeToken
    case keychainStatus(OSStatus)
}

final class CredentialStore {
    static let shared = CredentialStore()

    private let service = "dev.brim.api-token"
    private let previousService = "dev.\(BrimStorage.previousKey("").dropLast()).api-token"

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
        services.contains { service in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: credentialID,
                kSecReturnData as String: false,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
        }
    }

    func apiToken(credentialID: String?) -> String? {
        guard let credentialID else {
            return nil
        }

        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: credentialID,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var item: CFTypeRef?
            guard
                SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                let data = item as? Data,
                let token = String(data: data, encoding: .utf8)
            else {
                continue
            }

            return token
        }

        return nil
    }

    func deleteAPIToken(credentialID: String?) {
        guard let credentialID else {
            return
        }

        for service in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: credentialID
            ]

            SecItemDelete(query as CFDictionary)
        }
    }

    private var services: [String] {
        [service, previousService]
    }
}
