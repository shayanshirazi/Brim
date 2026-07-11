import XCTest
@testable import Brim

final class ProviderSessionIsolationTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testNewAccountsAlwaysReceiveUniqueUUIDProfilePaths() {
        var state = QuotaState(accounts: [])
        state.addAccount()
        state.addAccount()
        state.addAccount()
        state.removeAccounts(at: IndexSet(integer: 0))
        state.addAccount()

        let paths = state.accounts.map(\.resolvedProviderProfilePath)

        XCTAssertEqual(Set(paths).count, paths.count)
        XCTAssertTrue(
            state.accounts.allSatisfy {
                $0.resolvedProviderProfilePath.contains($0.id.uuidString.lowercased())
            }
        )
    }

    func testMigrationSplitsDuplicateProfilesAndPreservesOneCredentialOwner() throws {
        let applicationSupportURL = temporaryDirectory().appendingPathComponent("Brim", isDirectory: true)
        let legacyProfileURL = applicationSupportURL
            .appendingPathComponent("Profiles/codex/account-2", isDirectory: true)
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "workspace-1"),
            profilePath: legacyProfileURL.path
        )
        var firstAccount = testAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            profilePath: "$APP_SUPPORT/Profiles/codex/account-2"
        )
        firstAccount.accountEmail = "first@example.com"
        var secondAccount = testAccount(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            profilePath: "$APP_SUPPORT/Profiles/codex/account-2"
        )
        secondAccount.accountEmail = "first@example.com"

        let result = ProviderProfileStorage.migrateOwnedProfiles(
            in: [firstAccount, secondAccount],
            applicationSupportDirectoryPath: applicationSupportURL.path
        )

        XCTAssertEqual(Set(result.accounts.map(\.resolvedProviderProfilePath)).count, 2)
        XCTAssertEqual(result.accounts[1].refreshStatus, .notConnected)
        XCTAssertNil(result.accounts[1].accountEmail)
        XCTAssertTrue(result.disconnectedAccountIDs.contains(secondAccount.id))

        let firstAuthURL = canonicalProfileURL(for: result.accounts[0], root: applicationSupportURL)
            .appendingPathComponent("auth.json")
        let secondAuthURL = canonicalProfileURL(for: result.accounts[1], root: applicationSupportURL)
            .appendingPathComponent("auth.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstAuthURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondAuthURL.path))

        let attributes = try FileManager.default.attributesOfItem(atPath: firstAuthURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: firstAuthURL.deletingLastPathComponent().path
        )
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testMigrationKeepsLegacyProfileWhenCanonicalDestinationAlreadyExists() throws {
        let applicationSupportURL = temporaryDirectory().appendingPathComponent("Brim", isDirectory: true)
        let account = testAccount(
            id: UUID(uuidString: "23232323-2323-2323-2323-232323232323")!,
            profilePath: "$APP_SUPPORT/Profiles/codex/legacy-profile"
        )
        let legacyProfileURL = applicationSupportURL
            .appendingPathComponent("Profiles/codex/legacy-profile", isDirectory: true)
        let canonicalURL = canonicalProfileURL(for: account, root: applicationSupportURL)
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "legacy-workspace"),
            profilePath: legacyProfileURL.path
        )
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "canonical-workspace"),
            profilePath: canonicalURL.path
        )

        let result = ProviderProfileStorage.migrateOwnedProfiles(
            in: [account],
            applicationSupportDirectoryPath: applicationSupportURL.path
        )

        XCTAssertEqual(result.accounts.first?.providerProfilePath, account.providerProfilePath)
        XCTAssertFalse(result.didChange)
        XCTAssertEqual(
            CodexProfileAuthStore.tokens(profilePath: legacyProfileURL.path)?.accountID,
            "legacy-workspace"
        )
        XCTAssertEqual(
            CodexProfileAuthStore.tokens(profilePath: canonicalURL.path)?.accountID,
            "canonical-workspace"
        )
    }

    func testRemovingOwnedAccountDeletesItsUnreferencedProfile() throws {
        let applicationSupportURL = temporaryDirectory().appendingPathComponent("Brim", isDirectory: true)
        let account = testAccount(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            profilePath: "$APP_SUPPORT/Profiles/codex/33333333-3333-3333-3333-333333333333"
        )
        let profileURL = canonicalProfileURL(for: account, root: applicationSupportURL)
        try CodexProfileAuthStore.save(tokens: testTokens(accountID: "workspace-3"), profilePath: profileURL.path)

        try ProviderProfileStorage.removeOwnedProfileIfUnreferenced(
            for: account,
            remainingAccounts: [],
            applicationSupportDirectoryPath: applicationSupportURL.path
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: profileURL.path))
    }

    func testRemovingAuthPreservesExternalProfile() throws {
        let applicationSupportURL = temporaryDirectory().appendingPathComponent("Brim", isDirectory: true)
        let externalProfileURL = temporaryDirectory().appendingPathComponent("external-profile", isDirectory: true)
        let account = testAccount(id: UUID(), profilePath: externalProfileURL.path)
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "external-workspace"),
            profilePath: externalProfileURL.path
        )

        let wasOwned = try ProviderProfileStorage.removeOwnedAuthIfPresent(
            for: account,
            applicationSupportDirectoryPath: applicationSupportURL.path
        )

        XCTAssertFalse(wasOwned)
        XCTAssertTrue(CodexProfileAuthStore.hasUsableTokens(profilePath: externalProfileURL.path))
    }

    func testMigrationDisconnectsProfileWhenPermissionsCannotBeHardened() throws {
        let temporaryRootURL = temporaryDirectory()
        try FileManager.default.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)
        let applicationSupportURL = temporaryRootURL.appendingPathComponent("Brim")
        try Data("not a directory".utf8).write(to: applicationSupportURL)
        let account = testAccount(
            id: UUID(uuidString: "34343434-3434-3434-3434-343434343434")!,
            profilePath: "$APP_SUPPORT/Profiles/codex/legacy-profile"
        )

        let result = ProviderProfileStorage.migrateOwnedProfiles(
            in: [account],
            applicationSupportDirectoryPath: applicationSupportURL.path
        )

        let migratedAccount = try XCTUnwrap(result.accounts.first)
        XCTAssertEqual(migratedAccount.refreshStatus, .notConnected)
        XCTAssertTrue(migratedAccount.refreshMessage?.contains("could not secure") == true)
        XCTAssertTrue(result.disconnectedAccountIDs.contains(account.id))
    }

    func testImportRejectsDuplicateAccountIDs() throws {
        let accountID = UUID(uuidString: "35353535-3535-3535-3535-353535353535")!
        let firstAccount = testAccount(id: accountID, profilePath: "$APP_SUPPORT/Profiles/codex/first")
        var secondAccount = firstAccount
        secondAccount.name = "Duplicate"
        let payload = QuotaAccountsTransferPayload(
            accounts: [firstAccount, secondAccount],
            selectedAccountID: accountID
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        XCTAssertThrowsError(try QuotaAccountsTransferPayload.importedState(from: encoder.encode(payload))) { error in
            XCTAssertEqual(error as? QuotaAccountsTransferError, .duplicateAccountID(accountID))
        }
    }

    func testSidebarSortKeepsDisconnectedAccountsAfterConnectedAccountsWithoutSnapshots() {
        var connectedAccount = testAccount(id: UUID(), profilePath: "$APP_SUPPORT/Profiles/codex/connected")
        connectedAccount.refreshStatus = .waitingForQuotaSource
        var disconnectedAccount = testAccount(id: UUID(), profilePath: "$APP_SUPPORT/Profiles/codex/disconnected")
        disconnectedAccount.refreshStatus = .notConnected

        XCTAssertTrue(AccountUsagePriority.areInIncreasingOrder(connectedAccount, disconnectedAccount))
        XCTAssertFalse(AccountUsagePriority.areInIncreasingOrder(disconnectedAccount, connectedAccount))
    }

    func testDashboardProviderMigrationRemovesRetiredProfileDirectories() throws {
        let applicationSupportURL = temporaryDirectory().appendingPathComponent("Brim", isDirectory: true)
        let profilesURL = applicationSupportURL.appendingPathComponent("Profiles", isDirectory: true)
        let chatGPTURL = profilesURL.appendingPathComponent("chatgpt/account", isDirectory: true)
        let claudeURL = profilesURL.appendingPathComponent("claude/account", isDirectory: true)
        let codexURL = profilesURL.appendingPathComponent("codex/account", isDirectory: true)
        try FileManager.default.createDirectory(at: chatGPTURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexURL, withIntermediateDirectories: true)

        try ProviderProfileStorage.removeProfilesForDashboardOnlyProviders(
            applicationSupportDirectoryPath: applicationSupportURL.path
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: chatGPTURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: claudeURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: codexURL.path))
    }

    func testRefreshRejectsSilentIdentityChangeWithoutDeletingExternalAuth() async throws {
        let suiteName = "dev.brim.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        var account = testAccount(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            profilePath: temporaryDirectory().appendingPathComponent("profile", isDirectory: true).path
        )
        account.accountEmail = "expected@example.com"
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "workspace-4"),
            profilePath: account.resolvedProviderProfilePath
        )
        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(QuotaState(accounts: [account], selectedAccountID: account.id))
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .success(
                    CodexUsageFetchResult(
                        quota: QuotaUsageSnapshot(weeklyUsedPercent: 10, sessionUsedPercent: 20),
                        email: "different@example.com",
                        accountID: "workspace-4"
                    )
                )
            }
        )
        let store = QuotaStore(
            repository: repository,
            refreshService: service
        )

        await store.refreshAccount(id: account.id)

        let refreshedAccount = try XCTUnwrap(store.accounts.first)
        XCTAssertEqual(refreshedAccount.refreshStatus, .notConnected)
        XCTAssertNil(refreshedAccount.accountEmail)
        XCTAssertTrue(CodexProfileAuthStore.hasUsableTokens(profilePath: account.resolvedProviderProfilePath))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRefreshRejectsWorkspaceAlreadyOwnedByAccountWithoutStoredEmail() async throws {
        let suiteName = "dev.brim.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        var existingAccount = testAccount(
            id: UUID(uuidString: "45454545-4545-4545-4545-454545454545")!,
            profilePath: temporaryDirectory().appendingPathComponent("existing-profile", isDirectory: true).path
        )
        existingAccount.providerAccountID = "workspace-owner"
        let duplicateAccount = testAccount(
            id: UUID(uuidString: "46464646-4646-4646-4646-464646464646")!,
            profilePath: temporaryDirectory().appendingPathComponent("duplicate-profile", isDirectory: true).path
        )
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "workspace-owner"),
            profilePath: duplicateAccount.resolvedProviderProfilePath
        )
        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(
            QuotaState(accounts: [existingAccount, duplicateAccount], selectedAccountID: duplicateAccount.id)
        )
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .success(
                    CodexUsageFetchResult(
                        quota: QuotaUsageSnapshot(weeklyUsedPercent: 10, sessionUsedPercent: 20),
                        email: "owner@example.com",
                        accountID: "workspace-owner"
                    )
                )
            }
        )
        let store = QuotaStore(
            repository: repository,
            refreshService: service
        )

        await store.refreshAccount(id: duplicateAccount.id)

        let refreshedDuplicate = try XCTUnwrap(store.accounts.first { $0.id == duplicateAccount.id })
        XCTAssertEqual(refreshedDuplicate.refreshStatus, .notConnected)
        XCTAssertNil(refreshedDuplicate.accountEmail)
        XCTAssertTrue(
            CodexProfileAuthStore.hasUsableTokens(profilePath: duplicateAccount.resolvedProviderProfilePath)
        )
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStoreSerializesOverlappingRefreshes() async throws {
        let suiteName = "dev.brim.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let account = testAccount(
            id: UUID(uuidString: "47474747-4747-4747-4747-474747474747")!,
            profilePath: temporaryDirectory().appendingPathComponent("profile", isDirectory: true).path
        )
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "workspace-serial"),
            profilePath: account.resolvedProviderProfilePath
        )
        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(QuotaState(accounts: [account], selectedAccountID: account.id))
        let concurrency = RefreshConcurrencyTracker()
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                await concurrency.begin()
                try? await Task.sleep(nanoseconds: 30_000_000)
                await concurrency.end()
                return .success(
                    CodexUsageFetchResult(
                        quota: QuotaUsageSnapshot(weeklyUsedPercent: 10, sessionUsedPercent: 20),
                        accountID: "workspace-serial"
                    )
                )
            }
        )
        let store = QuotaStore(
            repository: repository,
            refreshService: service
        )

        async let firstRefresh: Void = store.refreshAccount(id: account.id)
        async let secondRefresh: Void = store.refreshAccount(id: account.id)
        _ = await (firstRefresh, secondRefresh)

        let maximumConcurrentRefreshes = await concurrency.maximumConcurrentRefreshes()
        XCTAssertEqual(maximumConcurrentRefreshes, 1)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRefreshMergesIntoLatestAccountWithoutRevertingConcurrentEdit() async throws {
        let suiteName = "dev.brim.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let account = testAccount(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            profilePath: temporaryDirectory().appendingPathComponent("profile", isDirectory: true).path
        )
        try CodexProfileAuthStore.save(
            tokens: testTokens(accountID: "workspace-5"),
            profilePath: account.resolvedProviderProfilePath
        )
        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(QuotaState(accounts: [account], selectedAccountID: account.id))
        let requestStarted = AsyncGate()
        let releaseRequest = AsyncGate()
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                await requestStarted.open()
                await releaseRequest.wait()
                return .success(
                    CodexUsageFetchResult(
                        quota: QuotaUsageSnapshot(
                            weeklyLimitMinutes: 600,
                            usedMinutes: 120,
                            sessionLimitMinutes: 300,
                            sessionUsedMinutes: 30
                        )
                    )
                )
            }
        )
        let store = QuotaStore(
            repository: repository,
            refreshService: service
        )

        let refreshTask = Task { await store.refreshAccount(id: account.id) }
        await requestStarted.wait()
        var renamedAccount = try XCTUnwrap(store.accounts.first)
        renamedAccount.name = "Renamed while refreshing"
        store.updateAccount(renamedAccount)
        await releaseRequest.open()
        await refreshTask.value

        let refreshedAccount = try XCTUnwrap(store.accounts.first)
        XCTAssertEqual(refreshedAccount.name, "Renamed while refreshing")
        XCTAssertEqual(refreshedAccount.weeklyLimitMinutes, 600)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func testAccount(id: UUID, profilePath: String) -> QuotaAccount {
        QuotaAccount(
            id: id,
            name: "Account",
            colorHex: "#2CCB68",
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            providerProfilePath: profilePath,
            connectionKind: .login,
            hasUsageSnapshot: false,
            refreshStatus: .ready
        )
    }

    private func testTokens(accountID: String) -> CodexAuthTokens {
        CodexAuthTokens(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            idToken: nil,
            accountID: accountID
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("brim-session-tests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func canonicalProfileURL(for account: QuotaAccount, root: URL) -> URL {
        root.appendingPathComponent(
            "Profiles/\(account.provider.rawValue)/\(account.id.uuidString.lowercased())",
            isDirectory: true
        )
    }

}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

private actor RefreshConcurrencyTracker {
    private var activeRefreshes = 0
    private var maximumRefreshes = 0

    func begin() {
        activeRefreshes += 1
        maximumRefreshes = max(maximumRefreshes, activeRefreshes)
    }

    func end() {
        activeRefreshes -= 1
    }

    func maximumConcurrentRefreshes() -> Int {
        maximumRefreshes
    }
}
