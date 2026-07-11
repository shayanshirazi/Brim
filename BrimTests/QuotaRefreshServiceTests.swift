import LocalAuthentication
import Security
import XCTest
@testable import Brim

final class QuotaRefreshServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolRefreshMock.resetHandlers()
        super.tearDown()
    }

#if BRIM_CERTIFICATE_FREE_DEBUG
    func testCertificateFreeDebugCredentialsPersistAcrossStoreInstances() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("brim-debug-credentials-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("api-tokens.json")
        let accountID = UUID()
        let firstStore = CredentialStore(localDebugStoreURL: storeURL)

        let credentialID = try firstStore.saveAPIToken("AIza-debug-token-value-1234", accountID: accountID)
        let secondStore = CredentialStore(localDebugStoreURL: storeURL)

        XCTAssertEqual(secondStore.readAPIToken(credentialID: credentialID), .token("AIza-debug-token-value-1234"))
    }

    func testCertificateFreeDebugCredentialsUseOwnerOnlyFilePermissions() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("brim-debug-credentials-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("api-tokens.json")
        let store = CredentialStore(localDebugStoreURL: storeURL)

        _ = try store.saveAPIToken("AIza-debug-token-value-1234", accountID: UUID())

        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCertificateFreeDebugCredentialDeletionPersists() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("brim-debug-credentials-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("api-tokens.json")
        let store = CredentialStore(localDebugStoreURL: storeURL)
        let credentialID = try store.saveAPIToken("AIza-debug-token-value-1234", accountID: UUID())

        try store.deleteAPIToken(credentialID: credentialID)

        XCTAssertEqual(CredentialStore(localDebugStoreURL: storeURL).readAPIToken(credentialID: credentialID), .missing)
    }
#endif

    func testAutomaticKeychainQueriesDisableAuthenticationUI() throws {
        let query = CredentialStore.noninteractiveKeychainQuery(
            service: "dev.brim.tests",
            credentialID: "credential-id"
        )

        let context = try XCTUnwrap(query[kSecUseAuthenticationContext as String] as? LAContext)
        XCTAssertTrue(context.interactionNotAllowed)
    }

    func testCodexAPITokenAccountIsStoppedBeforeKeychainOrNetworkAccess() async {
        var didReadKeychain = false
        var didFetchAPILimits = false
        let account = testAPIAccount(provider: .codex)
        let service = QuotaRefreshService(
            apiTokenProvider: { _ in
                didReadKeychain = true
                return .token("sk-project-token")
            },
            apiLimitsFetcher: { _, _ in
                didFetchAPILimits = true
                return APIRateLimitOutcome()
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .refreshFailed)
        XCTAssertEqual(
            result.message,
            "API keys cannot read Codex subscription usage. Switch this account to Login."
        )
        XCTAssertFalse(didReadKeychain)
        XCTAssertFalse(didFetchAPILimits)
    }

    func testInaccessibleKeychainTokenReturnsRefreshFailureWithoutNetworkAccess() async {
        var didFetchAPILimits = false
        let account = testAPIAccount(provider: .gemini)
        let service = QuotaRefreshService(
            apiTokenProvider: { _ in .inaccessible("Keychain access failed.") },
            apiLimitsFetcher: { _, _ in
                didFetchAPILimits = true
                return APIRateLimitOutcome()
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .refreshFailed)
        XCTAssertEqual(result.message, "Keychain access failed.")
        XCTAssertFalse(didFetchAPILimits)
    }

    func testValidAPIKeyWithoutUsageRemainsConnectedButHasNoQuotaSnapshot() async {
        let account = testAPIAccount(provider: .gemini)
        let service = QuotaRefreshService(
            apiTokenProvider: { _ in .token("AIza-test-token") },
            apiLimitsFetcher: { _, _ in
                APIRateLimitOutcome(
                    failureMessage: "Gemini key is valid, but usage is unavailable.",
                    failureKind: .validWithoutUsage
                )
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.message, "Gemini key is valid, but usage is unavailable.")
        XCTAssertNil(result.quota)
    }

    func testTransientAPIFailurePreservesAnExistingSnapshot() async {
        var account = testAPIAccount(provider: .gemini)
        account.hasUsageSnapshot = true
        let service = QuotaRefreshService(
            apiTokenProvider: { _ in .token("sk-ant-test-token") },
            apiLimitsFetcher: { _, _ in
                APIRateLimitOutcome(
                    failureMessage: "Anthropic is temporarily unavailable.",
                    failureKind: .transient
                )
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .refreshFailed)
        XCTAssertTrue(result.preservesExistingQuota)
    }

    func testProviderCapabilityMatrixDefinesOneSourceOfTruth() {
        XCTAssertEqual(QuotaProviderKind.codex.supportedConnectionKind, .login)
        XCTAssertTrue(QuotaProviderKind.codex.performsAutomaticRefresh)
        XCTAssertFalse(QuotaProviderKind.codex.usesProviderDashboard)

        XCTAssertEqual(QuotaProviderKind.chatgpt.supportedConnectionKind, .login)
        XCTAssertFalse(QuotaProviderKind.chatgpt.performsAutomaticRefresh)
        XCTAssertTrue(QuotaProviderKind.chatgpt.usesProviderDashboard)

        XCTAssertEqual(QuotaProviderKind.claude.supportedConnectionKind, .login)
        XCTAssertFalse(QuotaProviderKind.claude.performsAutomaticRefresh)
        XCTAssertTrue(QuotaProviderKind.claude.usesProviderDashboard)

        XCTAssertEqual(QuotaProviderKind.gemini.supportedConnectionKind, .apiToken)
        XCTAssertFalse(QuotaProviderKind.gemini.performsAutomaticRefresh)
        XCTAssertFalse(QuotaProviderKind.gemini.usesProviderDashboard)
    }

    func testGeminiTokenValidatorAcceptsStandardAndAuthorizationKeys() {
        let standardKey = "AIzaSyExampleKey_123456789012345"
        let authorizationKey = "AQ.ExampleAuthorizationKey-1234567890"

        XCTAssertEqual(APITokenValidator.validate(standardKey, provider: .gemini), .valid)
        XCTAssertEqual(APITokenValidator.validate(authorizationKey, provider: .gemini), .valid)
    }

    func testAPITokenValidatorRejectsUnsafeOrUnsupportedValues() {
        XCTAssertEqual(
            APITokenValidator.validate("AQ.Example AuthorizationKey-1234567890", provider: .gemini),
            .invalid("Paste the token without spaces or line breaks.")
        )
        XCTAssertEqual(
            APITokenValidator.validate("AQ.ExampleAuthorizationKey-1234567890", provider: .codex),
            .invalid("Codex accounts connect with Login, not an API key.")
        )
    }

    func testGeminiAuthorizationKeyUsesGoogleAPIKeyHeader() async throws {
        let authorizationKey = "AQ.ExampleAuthorizationKey-1234567890"
        let host = "generativelanguage.googleapis.com"
        URLProtocolRefreshMock.setHandler(for: host) { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), authorizationKey)
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"models":[]}"#.utf8)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolRefreshMock.self]

        try await APITokenValidationClient(session: URLSession(configuration: configuration))
            .validate(authorizationKey, provider: .gemini)
    }

    func testDashboardProvidersNeverCallCodexUsageFetcher() async {
        var didFetchCodexUsage = false
        let service = QuotaRefreshService(usageFetcher: { _ in
            didFetchCodexUsage = true
            return .unavailable("unexpected", accountEmail: nil)
        })

        let chatGPTResult = await service.refresh(testLoginAccount(provider: .chatgpt))
        let claudeResult = await service.refresh(testLoginAccount(provider: .claude))

        XCTAssertEqual(chatGPTResult.status, .dashboardOnly)
        XCTAssertNil(chatGPTResult.quota)
        XCTAssertEqual(claudeResult.status, .dashboardOnly)
        XCTAssertNil(claudeResult.quota)
        XCTAssertFalse(didFetchCodexUsage)
    }

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

    func testCodexTokenResponseDerivesWorkspaceIdentityFromIDToken() throws {
        let idToken = try jwt(accountID: "workspace-from-token")
        let data = try JSONSerialization.data(withJSONObject: [
            "access_token": "access-token",
            "refresh_token": "refresh-token",
            "id_token": idToken
        ])

        let response = try JSONDecoder().decode(CodexTokenResponse.self, from: data)

        XCTAssertEqual(response.codexTokens?.accountID, "workspace-from-token")
    }

    func testTransientTokenRefreshFailureDoesNotExpireSession() async throws {
        let account = try testLoginAccount()
        let host = "transient-refresh.example"
        URLProtocolRefreshMock.setHandler(for: host) { request in
            let statusCode = request.url?.path == "/usage" ? 401 : 503
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"error":"temporarily_unavailable"}"#.utf8)
            )
        }

        let client = try codexUsageClientForRefreshTests(host: host)
        let outcome = await client.fetchUsage(for: account)

        guard case .unavailable(_, _, _, let failureKind) = outcome else {
            return XCTFail("Expected unavailable outcome, got \(outcome)")
        }
        XCTAssertEqual(failureKind, .transient)
        XCTAssertFalse(outcome.isUnauthorized)
    }

    func testInvalidGrantExpiresSession() async throws {
        let account = try testLoginAccount()
        let host = "invalid-grant.example"
        URLProtocolRefreshMock.setHandler(for: host) { request in
            let isUsageRequest = request.url?.path == "/usage"
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: isUsageRequest ? 401 : 400,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(#"{"error":"invalid_grant"}"#.utf8)
            )
        }

        let client = try codexUsageClientForRefreshTests(host: host)
        let outcome = await client.fetchUsage(for: account)

        XCTAssertTrue(outcome.isUnauthorized)
    }

    func testStorePreservesExistingUsageSnapshotWhenLiveUsageIsUnavailable() async throws {
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

        let service = QuotaRefreshService(
            usageFetcher: { _ in
                .unavailable("Codex usage response did not include supported rate-limit data.", accountEmail: nil)
            }
        )
        let store = QuotaStore(
            repository: repository,
            refreshService: service
        )

        await store.refreshConnectedAccounts()

        let refreshed = try XCTUnwrap(store.accounts.first)
        XCTAssertEqual(refreshed.refreshStatus, .refreshFailed)
        XCTAssertEqual(refreshed.refreshMessage, "Codex usage response did not include supported rate-limit data.")
        XCTAssertTrue(refreshed.hasUsageSnapshot)
        XCTAssertEqual(refreshed.weeklyLimitMinutes, 300)
        XCTAssertEqual(refreshed.usedMinutes, 45)
        XCTAssertEqual(refreshed.sessionLimitMinutes, 300)
        XCTAssertEqual(refreshed.sessionUsedMinutes, 30)

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

        XCTAssertEqual(result.status, .refreshFailed)
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
                .unavailable("Codex usage response did not include supported rate-limit data.", accountEmail: nil)
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .refreshFailed)
        XCTAssertEqual(result.message, "Codex usage response did not include supported rate-limit data.")
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

    private func testAPIAccount(provider: QuotaProviderKind) -> QuotaAccount {
        QuotaAccount(
            provider: provider,
            name: provider.displayName,
            colorHex: provider.brandColorHex,
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            connectionKind: .apiToken,
            hasUsageSnapshot: false,
            credentialID: "credential-id"
        )
    }

    private func testLoginAccount(provider: QuotaProviderKind) -> QuotaAccount {
        QuotaAccount(
            provider: provider,
            name: provider.displayName,
            colorHex: provider.brandColorHex,
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            connectionKind: .login,
            refreshStatus: .dashboardOnly
        )
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

    private func codexUsageClientForRefreshTests(host: String) throws -> CodexUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolRefreshMock.self]
        return CodexUsageClient(
            session: URLSession(configuration: configuration),
            usageURL: try XCTUnwrap(URL(string: "https://\(host)/usage")),
            tokenURL: try XCTUnwrap(URL(string: "https://\(host)/token"))
        )
    }

    private func jwt(accountID: String) throws -> String {
        let header = base64URL(Data(#"{"alg":"none"}"#.utf8))
        let payload = base64URL(
            try JSONSerialization.data(withJSONObject: [
                "https://api.openai.com/auth": [
                    "chatgpt_account_id": accountID
                ]
            ])
        )
        return "\(header).\(payload).signature"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class URLProtocolRefreshMock: URLProtocol {
    private static let lock = NSLock()
    private static var requestHandlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data)] = [:]

    static func setHandler(
        for host: String,
        _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        lock.withLock {
            requestHandlers[host] = handler
        }
    }

    static func resetHandlers() {
        lock.withLock {
            requestHandlers.removeAll()
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard
            let host = request.url?.host,
            let requestHandler = Self.lock.withLock({ Self.requestHandlers[host] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
