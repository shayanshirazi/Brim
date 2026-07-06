import XCTest
@testable import Brim

final class QuotaRefreshServiceTests: XCTestCase {
    func testCodexOAuthAuthorizationURLEncodesRedirectAndScopeStrictly() throws {
        let url = try XCTUnwrap(
            CodexOAuthContract.authorizationURL(
                redirectURI: "http://localhost:49152/auth/callback",
                codeChallenge: "challenge_value",
                state: "state/value"
            )
        )
        let string = url.absoluteString

        XCTAssertTrue(string.contains("redirect_uri=http%3A%2F%2Flocalhost%3A49152%2Fauth%2Fcallback"))
        XCTAssertTrue(string.contains("scope=openid%20profile%20email%20offline_access%20api.connectors.read%20api.connectors.invoke"))
        XCTAssertTrue(string.contains("state=state%2Fvalue"))
        XCTAssertTrue(string.contains("originator=Codex%20Desktop"))
    }

    func testCodexTokenResponseDecodesNestedTokensAndMergesMissingRefreshToken() throws {
        let data = Data(
            """
            {
              "tokens": {
                "access_token": "new-access",
                "account_id": "session-123"
              }
            }
            """.utf8
        )
        let response = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
        let refreshed = try XCTUnwrap(response.codexTokens)
            .mergingMissingValues(
                from: CodexAuthTokens(
                    accessToken: "old-access",
                    refreshToken: "old-refresh",
                    idToken: "old-id",
                    accountID: "old-session"
                )
            )

        XCTAssertEqual(refreshed.accessToken, "new-access")
        XCTAssertEqual(refreshed.refreshToken, "old-refresh")
        XCTAssertEqual(refreshed.idToken, "old-id")
        XCTAssertEqual(refreshed.accountID, "session-123")
    }

    func testStoreClearsExistingUsageSnapshotWhenLiveUsageIsUnavailable() async throws {
        let suiteName = "dev.brim.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        var account = try testLoginAccount()
        account.hasUsageSnapshot = true
        account.refreshStatus = .ready
        account.weeklyLimitMinutes = 300
        account.usedMinutes = 45
        account.sessionLimitMinutes = 300
        account.sessionUsedMinutes = 30

        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(QuotaState(accounts: [account], selectedAccountID: account.id))

        let snapshotURL = testSnapshotURL()
        let widgetSnapshotStore = QuotaWidgetSnapshotStore(repository: nil, fallbackURL: snapshotURL)
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .unavailable("Codex usage request failed with HTTP 401.", accountEmail: nil)
            }
        )
        let store = QuotaStore(
            repository: repository,
            widgetSnapshotStore: widgetSnapshotStore,
            refreshService: service
        )

        await store.refreshConnectedAccounts()

        let refreshed = try XCTUnwrap(store.accounts.first)
        XCTAssertEqual(refreshed.refreshStatus, .ready)
        XCTAssertEqual(refreshed.refreshMessage, "Codex usage request failed with HTTP 401.")
        XCTAssertFalse(refreshed.hasUsageSnapshot)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRefreshAccountUpdatesOnlySelectedAccount() async throws {
        let suiteName = "dev.brim.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        var selectedAccount = try testLoginAccount()
        selectedAccount.name = "Selected"
        selectedAccount.weeklyLimitMinutes = 300
        selectedAccount.usedMinutes = 0

        var otherAccount = try testLoginAccount()
        otherAccount.id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        otherAccount.name = "Other"
        otherAccount.weeklyLimitMinutes = 300
        otherAccount.usedMinutes = 10

        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(QuotaState(accounts: [selectedAccount, otherAccount], selectedAccountID: selectedAccount.id))

        let widgetSnapshotStore = QuotaWidgetSnapshotStore(repository: nil, fallbackURL: testSnapshotURL())
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .success(
                    CodexUsageFetchResult(
                        quota: QuotaUsageSnapshot(
                            weeklyLimitMinutes: 600,
                            usedMinutes: 240,
                            sessionLimitMinutes: 300,
                            sessionUsedMinutes: 90
                        )
                    )
                )
            }
        )
        let store = QuotaStore(
            repository: repository,
            widgetSnapshotStore: widgetSnapshotStore,
            refreshService: service
        )

        await store.refreshAccount(id: selectedAccount.id)

        let refreshedSelected = try XCTUnwrap(store.accounts.first { $0.id == selectedAccount.id })
        let untouchedOther = try XCTUnwrap(store.accounts.first { $0.id == otherAccount.id })
        XCTAssertTrue(refreshedSelected.hasUsageSnapshot)
        XCTAssertEqual(refreshedSelected.weeklyLimitMinutes, 600)
        XCTAssertEqual(refreshedSelected.usedMinutes, 240)
        XCTAssertEqual(refreshedSelected.sessionLimitMinutes, 300)
        XCTAssertEqual(refreshedSelected.sessionUsedMinutes, 90)
        XCTAssertEqual(untouchedOther.weeklyLimitMinutes, 300)
        XCTAssertEqual(untouchedOther.usedMinutes, 10)

        defaults.removePersistentDomain(forName: suiteName)
    }

    func testCodexLoginUsesLiveUsageWhenAvailable() async throws {
        let account = try testLoginAccount()
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .success(
                    CodexUsageFetchResult(
                        quota: QuotaUsageSnapshot(
                            weeklyLimitMinutes: 600,
                            usedMinutes: 120,
                            sessionLimitMinutes: 300,
                            sessionUsedMinutes: 30,
                            weeklyUsedPercent: 20,
                            sessionUsedPercent: 10
                        ),
                        email: "live@example.com",
                        accountID: "session-123"
                    )
                )
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.message, "Loaded live Codex usage.")
        XCTAssertEqual(result.accountEmail, "live@example.com")
        XCTAssertEqual(result.providerAccountID, "session-123")
        XCTAssertEqual(result.quota?.weeklyLimitMinutes, 600)
        XCTAssertEqual(result.quota?.usedMinutes, 120)
        XCTAssertEqual(result.quota?.weeklyUsedPercent, 20)
        XCTAssertEqual(result.quota?.sessionUsedPercent, 10)
    }

    func testCodexLoginKeepsIdentityWhenUsageHasNoQuota() async throws {
        let account = try testLoginAccount()
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .unavailable(
                    "Codex usage response did not include rate-limit data Brim understands.",
                    accountEmail: "identity@example.com",
                    accountID: "session-456"
                )
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.accountEmail, "identity@example.com")
        XCTAssertEqual(result.providerAccountID, "session-456")
        XCTAssertNil(result.quota)
    }

    func testCodexLoginReturnsNotConnectedWhenAuthFileIsMissing() async {
        let account = disconnectedLoginAccount()
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                XCTFail("Usage should not be fetched without profile auth.")
                return .unavailable("unexpected", accountEmail: nil)
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .notConnected)
        XCTAssertEqual(result.message, "Sign in with Codex to connect this account.")
    }

    func testCodexLoginReturnsFetcherFailureWhenNoSnapshotExists() async throws {
        let account = try testLoginAccount()
        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .unavailable("Codex usage request failed with HTTP 401.", accountEmail: nil)
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.message, "Codex usage request failed with HTTP 401.")
        XCTAssertNil(result.quota)
    }

    private func testLoginAccount() throws -> QuotaAccount {
        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("brim-tests-\(UUID().uuidString)", isDirectory: true)
        try CodexProfileAuthStore.save(
            tokens: CodexAuthTokens(
                accessToken: "test-access-token",
                refreshToken: "test-refresh-token",
                idToken: nil,
                accountID: "test-session-id"
            ),
            profilePath: profileURL.path
        )

        return testLoginAccount(profilePath: profileURL.path)
    }

    private func disconnectedLoginAccount() -> QuotaAccount {
        let profileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("brim-tests-missing-\(UUID().uuidString)", isDirectory: true)
        return testLoginAccount(profilePath: profileURL.path)
    }

    private func testLoginAccount(profilePath: String) -> QuotaAccount {
        QuotaAccount(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Codex",
            colorHex: "#2CCB68",
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            providerProfilePath: profilePath,
            connectionKind: .login
        )
    }

    private func testSnapshotURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("brim-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    }
}
