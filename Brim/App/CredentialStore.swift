import Foundation
import LocalAuthentication
import OSLog
import Security

enum CredentialStoreError: LocalizedError {
    case couldNotEncodeToken
    case keychainStatus(OSStatus)
    case localCredentialStorage(String)

    var errorDescription: String? {
        switch self {
        case .couldNotEncodeToken:
            return "Brim could not encode this API token."
        case .keychainStatus(let status):
            return "Keychain rejected the credential operation (status \(status))."
        case .localCredentialStorage(let message):
            return message
        }
    }
}

final class CredentialStore {
    static let shared = CredentialStore()
    private static let logger = Logger(subsystem: "dev.brim.app", category: "credentials")

    private let service = "dev.brim.api-token.v2"
    private let legacyServices = [
        "dev.brim.api-token",
        "dev.\(BrimStorage.previousKey("").dropLast()).api-token"
    ]

#if BRIM_CERTIFICATE_FREE_DEBUG
    private let localDebugStore: LocalDebugCredentialStore

    init(localDebugStoreURL: URL = LocalDebugCredentialStore.defaultStoreURL()) {
        localDebugStore = LocalDebugCredentialStore(storeURL: localDebugStoreURL)
    }
#else
    private init() {}
#endif

    func saveAPIToken(_ token: String, accountID: UUID) throws -> String {
        let credentialID = accountID.uuidString

#if BRIM_CERTIFICATE_FREE_DEBUG
        try localDebugStore.save(token: token, credentialID: credentialID)
        return credentialID
#else
        try saveKeychainToken(token, credentialID: credentialID)
        return credentialID
#endif
    }

    func readAPIToken(credentialID: String?) -> APITokenCredentialReadResult {
        guard let credentialID else {
            return .missing
        }

#if BRIM_CERTIFICATE_FREE_DEBUG
        do {
            return try localDebugStore.readToken(credentialID: credentialID).map(APITokenCredentialReadResult.token)
                ?? .missing
        } catch {
            return .inaccessible(error.localizedDescription)
        }
#else
        return readKeychainToken(credentialID: credentialID)
#endif
    }

    func deleteAPIToken(credentialID: String?) throws {
        guard let credentialID else {
            return
        }

#if BRIM_CERTIFICATE_FREE_DEBUG
        try localDebugStore.deleteToken(credentialID: credentialID)
#else
        var firstDeletionError: Error?
        for keychainService in [service] + legacyServices {
            do {
                try deleteKeychainToken(service: keychainService, credentialID: credentialID)
            } catch {
                firstDeletionError = firstDeletionError ?? error
            }
        }
        if let firstDeletionError {
            throw firstDeletionError
        }
#endif
    }

#if !BRIM_CERTIFICATE_FREE_DEBUG
    private func saveKeychainToken(_ token: String, credentialID: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw CredentialStoreError.couldNotEncodeToken
        }

        let existingItemQuery = Self.noninteractiveKeychainQuery(service: service, credentialID: credentialID)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(existingItemQuery as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItemQuery = Self.keychainQuery(service: service, credentialID: credentialID)
            newItemQuery[kSecValueData as String] = tokenData
            newItemQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let addStatus = SecItemAdd(newItemQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychainStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychainStatus(updateStatus)
        }

        for legacyService in legacyServices {
            do {
                try deleteKeychainToken(service: legacyService, credentialID: credentialID)
            } catch {
                Self.logger.error("Could not remove a legacy credential after migration: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func readKeychainToken(credentialID: String) -> APITokenCredentialReadResult {
        switch readToken(service: service, credentialID: credentialID) {
        case .token(let token):
            return .token(token)
        case .inaccessible(let status):
            return .inaccessible(Self.keychainAccessMessage(status: status))
        case .missing:
            break
        }

        var inaccessibleLegacyStatus: OSStatus?
        for legacyService in legacyServices {
            switch readToken(service: legacyService, credentialID: credentialID) {
            case .token(let token):
                migrateLegacyTokenIfPossible(token, legacyService: legacyService, credentialID: credentialID)
                return .token(token)
            case .missing:
                continue
            case .inaccessible(let status):
                inaccessibleLegacyStatus = inaccessibleLegacyStatus ?? status
            }
        }
        if let inaccessibleLegacyStatus {
            return .inaccessible(Self.keychainAccessMessage(status: inaccessibleLegacyStatus))
        }
        return .missing
    }

    private func readToken(service: String, credentialID: String) -> KeychainTokenLookup {
        var query = Self.noninteractiveKeychainQuery(service: service, credentialID: credentialID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return .missing
        }
        guard status == errSecSuccess else {
            return .inaccessible(status)
        }
        guard let tokenData = item as? Data, let token = String(data: tokenData, encoding: .utf8) else {
            return .inaccessible(errSecDecode)
        }
        return .token(token)
    }

    private func migrateLegacyTokenIfPossible(
        _ token: String,
        legacyService: String,
        credentialID: String
    ) {
        guard let tokenData = token.data(using: .utf8) else {
            return
        }

        var newItemQuery = Self.keychainQuery(service: service, credentialID: credentialID)
        newItemQuery[kSecValueData as String] = tokenData
        newItemQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        guard SecItemAdd(newItemQuery as CFDictionary, nil) == errSecSuccess else {
            return
        }
        do {
            try deleteKeychainToken(service: legacyService, credentialID: credentialID)
        } catch {
            Self.logger.error("Could not remove a legacy credential after migration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteKeychainToken(service: String, credentialID: String) throws {
        let query = Self.noninteractiveKeychainQuery(service: service, credentialID: credentialID)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(status)
        }
    }
#endif

    static func noninteractiveKeychainQuery(service: String, credentialID: String) -> [String: Any] {
        let context = LAContext()
        // SECURITY: Background reads fail closed instead of displaying a system
        // password dialog for an item owned by a different code signature.
        context.interactionNotAllowed = true

        var query = keychainQuery(service: service, credentialID: credentialID)
        query[kSecUseAuthenticationContext as String] = context
        return query
    }

    private static func keychainQuery(service: String, credentialID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialID
        ]
    }

    private static func keychainAccessMessage(status: OSStatus) -> String {
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return "Brim cannot access this saved token with the current signed app identity."
        }
        return "Brim could not read this saved token from Keychain (status \(status))."
    }
}

enum LocalAccountSecrets {
    static func delete(for account: QuotaAccount, remainingAccounts: [QuotaAccount]) throws {
        try CredentialStore.shared.deleteAPIToken(credentialID: account.credentialID)
        try ProviderProfileStorage.removeOwnedProfileIfUnreferenced(
            for: account,
            remainingAccounts: remainingAccounts
        )
    }

    static func deleteAllBestEffort(for accounts: [QuotaAccount]) -> [LocalAccountSecretDeletionFailure] {
        var accountsStillPendingDeletion = accounts
        var failures: [LocalAccountSecretDeletionFailure] = []
        for account in accounts {
            accountsStillPendingDeletion.removeAll { $0.id == account.id }
            do {
                try delete(for: account, remainingAccounts: accountsStillPendingDeletion)
            } catch {
                failures.append(
                    LocalAccountSecretDeletionFailure(
                        accountName: account.name,
                        message: error.localizedDescription
                    )
                )
            }
        }
        return failures
    }
}

struct LocalAccountSecretDeletionFailure: Equatable {
    var accountName: String
    var message: String
}

#if BRIM_CERTIFICATE_FREE_DEBUG
struct LocalDebugCredentialStore {
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    let storeURL: URL
    private let lock = NSLock()

    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? fileManager.homeDirectoryForCurrentUser
        return applicationSupportURL
            .appendingPathComponent("Brim", isDirectory: true)
            .appendingPathComponent("DebugCredentials", isDirectory: true)
            .appendingPathComponent("api-tokens.json")
    }

    func save(token: String, credentialID: String, fileManager: FileManager = .default) throws {
        try lock.withLock {
            var tokens = try loadTokens(fileManager: fileManager)
            tokens[credentialID] = token
            try writeTokens(tokens, fileManager: fileManager)
        }
    }

    func readToken(credentialID: String, fileManager: FileManager = .default) throws -> String? {
        try lock.withLock {
            try loadTokens(fileManager: fileManager)[credentialID]
        }
    }

    func deleteToken(credentialID: String, fileManager: FileManager = .default) throws {
        try lock.withLock {
            var tokens = try loadTokens(fileManager: fileManager)
            guard tokens.removeValue(forKey: credentialID) != nil else {
                return
            }
            try writeTokens(tokens, fileManager: fileManager)
        }
    }

    private func loadTokens(fileManager: FileManager) throws -> [String: String] {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: storeURL)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            throw CredentialStoreError.localCredentialStorage(
                "Brim could not read its private Debug credential file: \(error.localizedDescription)"
            )
        }
    }

    private func writeTokens(_ tokens: [String: String], fileManager: FileManager) throws {
        do {
            let directoryURL = storeURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: Self.directoryPermissions], ofItemAtPath: directoryURL.path)

            let data = try JSONEncoder().encode(tokens)
            try data.write(to: storeURL, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: Self.filePermissions], ofItemAtPath: storeURL.path)
        } catch {
            throw CredentialStoreError.localCredentialStorage(
                "Brim could not update its private Debug credential file: \(error.localizedDescription)"
            )
        }
    }
}
#else
private enum KeychainTokenLookup {
    case token(String)
    case missing
    case inaccessible(OSStatus)
}
#endif
