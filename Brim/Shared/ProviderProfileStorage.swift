import Foundation

public struct ProviderProfileMigrationResult {
    public var accounts: [QuotaAccount]
    public var didChange: Bool
    public var disconnectedAccountIDs: Set<QuotaAccount.ID>
}

public enum ProviderProfileStorage {
    private static let directoryPermissions = 0o700
    private static let credentialFilePermissions = 0o600

    public static func canonicalPath(for account: QuotaAccount) -> String {
        QuotaAccountDefaults.defaultProfilePath(for: account.id, provider: account.provider)
    }

    public static func migrateOwnedProfiles(
        in accounts: [QuotaAccount],
        applicationSupportDirectoryPath: String = QuotaFormatting.applicationSupportDirectoryPath,
        fileManager: FileManager = .default
    ) -> ProviderProfileMigrationResult {
        var migratedAccounts = accounts
        var claimedSourcePaths = Set<String>()
        var disconnectedAccountIDs = Set<QuotaAccount.ID>()
        var didChange = false

        for index in migratedAccounts.indices {
            var account = migratedAccounts[index]
            guard account.provider == .codex, account.connectionKind == .login else {
                if account.providerProfilePath != nil {
                    didChange = true
                }
                account.providerProfilePath = nil
                migratedAccounts[index] = account
                continue
            }
            let sourcePath = expandedPath(
                account.resolvedProviderProfilePath,
                applicationSupportDirectoryPath: applicationSupportDirectoryPath
            )
            let standardizedSourcePath = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
            let sourceWasAlreadyClaimed = !claimedSourcePaths.insert(standardizedSourcePath).inserted
            let canonicalRelativePath = canonicalPath(for: account)
            let canonicalExpandedPath = expandedPath(
                canonicalRelativePath,
                applicationSupportDirectoryPath: applicationSupportDirectoryPath
            )

            if sourceWasAlreadyClaimed {
                account = account.disconnectedProviderAccount(
                    message: "This account shared a login profile with another Brim account. Sign in again to finish isolating it."
                )
                account.providerProfilePath = canonicalRelativePath
                disconnectedAccountIDs.insert(account.id)
                didChange = true
                do {
                    try prepareOwnedDirectory(atPath: canonicalExpandedPath, fileManager: fileManager)
                } catch {
                    account.refreshMessage = profileSecurityFailureMessage(for: account)
                }
                migratedAccounts[index] = account
                continue
            }

            guard isOwnedPath(sourcePath, applicationSupportDirectoryPath: applicationSupportDirectoryPath) else {
                migratedAccounts[index] = account
                continue
            }

            var preparedPath = sourcePath
            if standardizedSourcePath != URL(fileURLWithPath: canonicalExpandedPath).standardizedFileURL.path {
                let didMigrate = migrateDirectory(
                    fromPath: sourcePath,
                    toPath: canonicalExpandedPath,
                    fileManager: fileManager
                )
                if didMigrate {
                    account.providerProfilePath = canonicalRelativePath
                    preparedPath = canonicalExpandedPath
                    didChange = true
                }
            } else if account.providerProfilePath != canonicalRelativePath {
                account.providerProfilePath = canonicalRelativePath
                preparedPath = canonicalExpandedPath
                didChange = true
            } else {
                preparedPath = canonicalExpandedPath
            }

            do {
                try prepareOwnedDirectory(atPath: preparedPath, fileManager: fileManager)
            } catch {
                let authURL = URL(fileURLWithPath: preparedPath, isDirectory: true)
                    .appendingPathComponent("auth.json")
                try? fileManager.removeItem(at: authURL)
                account = account.disconnectedProviderAccount(
                    message: profileSecurityFailureMessage(for: account)
                )
                disconnectedAccountIDs.insert(account.id)
                didChange = true
            }
            migratedAccounts[index] = account
        }

        return ProviderProfileMigrationResult(
            accounts: migratedAccounts,
            didChange: didChange,
            disconnectedAccountIDs: disconnectedAccountIDs
        )
    }

    public static func removeOwnedProfileIfUnreferenced(
        for account: QuotaAccount,
        remainingAccounts: [QuotaAccount],
        applicationSupportDirectoryPath: String = QuotaFormatting.applicationSupportDirectoryPath,
        fileManager: FileManager = .default
    ) throws {
        let profilePath = expandedPath(
            account.resolvedProviderProfilePath,
            applicationSupportDirectoryPath: applicationSupportDirectoryPath
        )
        guard isOwnedPath(profilePath, applicationSupportDirectoryPath: applicationSupportDirectoryPath) else {
            return
        }

        let standardizedProfilePath = URL(fileURLWithPath: profilePath).standardizedFileURL.path
        let isStillReferenced = remainingAccounts.contains { remainingAccount in
            let remainingPath = expandedPath(
                remainingAccount.resolvedProviderProfilePath,
                applicationSupportDirectoryPath: applicationSupportDirectoryPath
            )
            return URL(fileURLWithPath: remainingPath).standardizedFileURL.path == standardizedProfilePath
        }
        guard !isStillReferenced, fileManager.fileExists(atPath: profilePath) else {
            return
        }

        try fileManager.removeItem(atPath: profilePath)
    }

    @discardableResult
    public static func removeOwnedAuthIfPresent(
        for account: QuotaAccount,
        applicationSupportDirectoryPath: String = QuotaFormatting.applicationSupportDirectoryPath,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let profilePath = expandedPath(
            account.resolvedProviderProfilePath,
            applicationSupportDirectoryPath: applicationSupportDirectoryPath
        )
        guard isOwnedPath(profilePath, applicationSupportDirectoryPath: applicationSupportDirectoryPath) else {
            return false
        }

        let authURL = URL(fileURLWithPath: profilePath, isDirectory: true)
            .appendingPathComponent("auth.json")
        guard fileManager.fileExists(atPath: authURL.path) else {
            return true
        }

        try fileManager.removeItem(at: authURL)
        return true
    }

    public static func removeProfilesForDashboardOnlyProviders(
        applicationSupportDirectoryPath: String = QuotaFormatting.applicationSupportDirectoryPath,
        fileManager: FileManager = .default
    ) throws {
        var firstRemovalError: Error?
        for provider in QuotaProviderKind.allCases where provider.usesProviderDashboard {
            let providerProfilesURL = URL(fileURLWithPath: applicationSupportDirectoryPath, isDirectory: true)
                .appendingPathComponent("Profiles", isDirectory: true)
                .appendingPathComponent(provider.rawValue, isDirectory: true)
            guard fileManager.fileExists(atPath: providerProfilesURL.path) else {
                continue
            }
            do {
                try fileManager.removeItem(at: providerProfilesURL)
            } catch {
                firstRemovalError = firstRemovalError ?? error
            }
        }
        if let firstRemovalError {
            throw firstRemovalError
        }
    }

    public static func secureCredentialFile(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: credentialFilePermissions],
            ofItemAtPath: url.path
        )
        try secureProfileDirectory(at: url.deletingLastPathComponent(), fileManager: fileManager)
    }

    public static func secureProfileDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.setAttributes(
            [.posixPermissions: directoryPermissions],
            ofItemAtPath: url.path
        )
    }

    private static func migrateDirectory(
        fromPath sourcePath: String,
        toPath destinationPath: String,
        fileManager: FileManager
    ) -> Bool {
        guard sourcePath != destinationPath else {
            return true
        }

        let destinationURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return false
        }

        guard fileManager.fileExists(atPath: sourcePath) else {
            return true
        }

        guard !fileManager.fileExists(atPath: destinationPath) else {
            return false
        }

        do {
            try fileManager.moveItem(atPath: sourcePath, toPath: destinationPath)
            return true
        } catch {
            return false
        }
    }

    private static func prepareOwnedDirectory(atPath path: String, fileManager: FileManager) throws {
        let directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try secureProfileDirectory(at: directoryURL, fileManager: fileManager)

        let authURL = directoryURL.appendingPathComponent("auth.json")
        if fileManager.fileExists(atPath: authURL.path) {
            try secureCredentialFile(at: authURL, fileManager: fileManager)
        }
    }

    private static func profileSecurityFailureMessage(for account: QuotaAccount) -> String {
        "Brim could not secure this \(account.provider.displayName) login profile. Check the profile folder permissions, then sign in again."
    }

    private static func isOwnedPath(
        _ path: String,
        applicationSupportDirectoryPath: String
    ) -> Bool {
        let profilesRoot = URL(fileURLWithPath: applicationSupportDirectoryPath, isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .standardizedFileURL.path
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardizedPath == profilesRoot || standardizedPath.hasPrefix(profilesRoot + "/")
    }

    private static func expandedPath(
        _ path: String,
        applicationSupportDirectoryPath: String
    ) -> String {
        if path == "$APP_SUPPORT" {
            return applicationSupportDirectoryPath
        }
        if path.hasPrefix("$APP_SUPPORT/") {
            return applicationSupportDirectoryPath + String(path.dropFirst("$APP_SUPPORT".count))
        }
        return QuotaFormatting.expandedHomePath(path)
    }
}
