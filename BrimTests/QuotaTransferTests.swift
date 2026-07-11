import XCTest
@testable import Brim

final class QuotaTransferTests: XCTestCase {
    func testMenuBarSettingsRouteRoundTrips() throws {
        let url = try XCTUnwrap(URL(string: AppRoute.menuBarSettings.urlString))

        XCTAssertEqual(AppRoute.parse(url), .menuBarSettings)
        XCTAssertEqual(
            AppRoute.parse(try XCTUnwrap(URL(string: "brim://settings/widget"))),
            .menuBarSettings
        )
    }

    func testMenuBarPreferencesFilterSortAndLimitAccounts() {
        var healthy = QuotaAccountDefaults.newAccount(index: 1)
        healthy.name = "Healthy"
        healthy.hasUsageSnapshot = true
        healthy.sessionUsedPercent = 10
        healthy.refreshStatus = .ready

        var urgent = QuotaAccountDefaults.newAccount(index: 2)
        urgent.name = "Urgent"
        urgent.hasUsageSnapshot = true
        urgent.sessionUsedPercent = 90
        urgent.refreshStatus = .ready

        var disconnected = QuotaAccountDefaults.newAccount(index: 3)
        disconnected.name = "Disconnected"
        disconnected.refreshStatus = .notConnected

        let preferences = MenuBarPreferences(
            accountOrder: .lowestRemaining,
            hiddenAccountIDs: [healthy.id],
            includesDisconnected: false,
            maximumRows: 1
        )

        XCTAssertEqual(
            preferences.visibleAccounts(from: [healthy, disconnected, urgent]).map(\.id),
            [urgent.id]
        )
    }

    func testStoredDashboardProviderDropsStaleQuotaAndPrivateConnectionFields() {
        var account = QuotaAccount(
            provider: .chatgpt,
            providerAccountID: "workspace-from-old-build",
            name: "ChatGPT",
            accountEmail: "owner@example.com",
            colorHex: "#10A37F",
            weeklyLimitMinutes: 600,
            usedMinutes: 300,
            weeklyUsedPercent: 50,
            sessionUsedPercent: 25,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 0,
            providerProfilePath: "$APP_SUPPORT/Profiles/chatgpt/old-profile",
            connectionKind: .login,
            hasUsageSnapshot: true,
            refreshStatus: .ready,
            credentialID: "old-credential"
        )

        account = account.normalizedForStorage()

        XCTAssertEqual(account.refreshStatus, .dashboardOnly)
        XCTAssertFalse(account.hasUsageSnapshot)
        XCTAssertNil(account.weeklyUsedPercent)
        XCTAssertNil(account.sessionUsedPercent)
        XCTAssertNil(account.providerAccountID)
        XCTAssertNil(account.accountEmail)
        XCTAssertNil(account.providerProfilePath)
        XCTAssertNil(account.credentialID)
    }

    override func tearDown() {
        URLProtocolMock.requestHandler = nil
        super.tearDown()
    }

    func testImportScrubsCredentialIDsAndReconnectsTokenAccounts() throws {
        let account = QuotaAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            providerAccountID: "remote-id",
            name: "Imported",
            accountEmail: "user@example.com",
            colorHex: "#2CCB68",
            weeklyLimitMinutes: 300,
            usedMinutes: 20,
            sessionLimitMinutes: 300,
            sessionUsedMinutes: 40,
            weeklyUsedPercent: 7,
            sessionUsedPercent: 13,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            providerProfilePath: "$HOME/.codex-accounts/old-machine",
            connectionKind: .apiToken,
            hasUsageSnapshot: true,
            refreshStatus: .ready,
            lastRefreshAttemptAt: Date(timeIntervalSince1970: 50),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 100),
            refreshMessage: "Loaded live usage.",
            credentialID: "keychain-secret"
        )
        let payload = QuotaAccountsTransferPayload(
            exportedAt: Date(timeIntervalSince1970: 200),
            accounts: [account],
            selectedAccountID: account.id
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let imported = try QuotaAccountsTransferPayload.importedState(from: encoder.encode(payload))

        XCTAssertEqual(imported.accounts.count, 1)
        XCTAssertNil(imported.accounts[0].credentialID)
        XCTAssertNil(imported.accounts[0].providerAccountID)
        XCTAssertNil(imported.accounts[0].accountEmail)
        XCTAssertNil(imported.accounts[0].providerProfilePath)
        XCTAssertEqual(imported.accounts[0].refreshStatus, .notConnected)
        XCTAssertNil(imported.accounts[0].lastRefreshAttemptAt)
        XCTAssertNil(imported.accounts[0].lastSuccessfulRefreshAt)
        XCTAssertFalse(imported.accounts[0].hasUsageSnapshot)
        XCTAssertEqual(imported.accounts[0].usedMinutes, 0)
        XCTAssertEqual(imported.accounts[0].sessionUsedMinutes, 0)
        XCTAssertNil(imported.accounts[0].weeklyUsedPercent)
        XCTAssertNil(imported.accounts[0].sessionUsedPercent)
        XCTAssertEqual(imported.accounts[0].refreshMessage, "Add this device's API token to reconnect.")
        XCTAssertEqual(imported.selectedAccountID, account.id)
    }

    func testExportScrubsPersonalLiveStateFromConnectedAccounts() throws {
        let account = QuotaAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            providerAccountID: "remote-id",
            name: "Portable",
            accountEmail: "user@example.com",
            colorHex: "#2CCB68",
            weeklyLimitMinutes: 300,
            usedMinutes: 20,
            sessionLimitMinutes: 300,
            sessionUsedMinutes: 40,
            weeklyUsedPercent: 7,
            sessionUsedPercent: 13,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            providerProfilePath: "$HOME/.codex-accounts/old-machine",
            connectionKind: .login,
            hasUsageSnapshot: true,
            refreshStatus: .ready,
            lastRefreshAttemptAt: Date(timeIntervalSince1970: 50),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 100),
            refreshMessage: "Loaded live usage.",
            credentialID: "keychain-secret"
        )

        let payload = QuotaAccountsTransferPayload(
            exportedAt: Date(timeIntervalSince1970: 200),
            accounts: [account],
            selectedAccountID: account.id
        )

        let exported = try XCTUnwrap(payload.accounts.first)
        XCTAssertEqual(exported.name, "Portable")
        XCTAssertNil(exported.providerAccountID)
        XCTAssertNil(exported.accountEmail)
        XCTAssertNil(exported.providerProfilePath)
        XCTAssertNil(exported.credentialID)
        XCTAssertNil(exported.lastRefreshAttemptAt)
        XCTAssertNil(exported.lastSuccessfulRefreshAt)
        XCTAssertNil(exported.refreshMessage)
        XCTAssertFalse(exported.hasUsageSnapshot)
        XCTAssertEqual(exported.refreshStatus, .notConnected)
        XCTAssertEqual(exported.usedMinutes, 0)
        XCTAssertEqual(exported.sessionUsedMinutes, 0)
        XCTAssertNil(exported.weeklyUsedPercent)
        XCTAssertNil(exported.sessionUsedPercent)
    }

    func testProviderUsageURLsMatchEachProviderCapability() throws {
        XCTAssertEqual(
            QuotaProviderKind.codex.usageURL(for: .login)?.absoluteString,
            "https://chatgpt.com/codex/cloud/settings/analytics#usage"
        )
        XCTAssertNil(QuotaProviderKind.codex.usageURL(for: .apiToken))
        XCTAssertTrue(QuotaProviderKind.codex.supports(.login))
        XCTAssertFalse(QuotaProviderKind.codex.supports(.apiToken))
        XCTAssertEqual(
            QuotaProviderKind.chatgpt.usageURL(for: .login)?.absoluteString,
            "https://chatgpt.com/#settings/Subscription"
        )
        XCTAssertEqual(
            QuotaProviderKind.claude.usageURL(for: .login)?.absoluteString,
            "https://claude.ai/settings/usage"
        )
        XCTAssertFalse(QuotaProviderKind.claude.supports(.apiToken))
        XCTAssertTrue(QuotaProviderKind.claude.supports(.login))
        XCTAssertEqual(
            QuotaProviderKind.gemini.usageURL(for: .apiToken)?.absoluteString,
            "https://aistudio.google.com/usage"
        )
    }

    func testImportRejectsUnsupportedTransferVersion() throws {
        let account = QuotaAccount(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Future",
            colorHex: "#2CCB68",
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30
        )
        let payload = QuotaAccountsTransferPayload(
            version: QuotaAccountsTransferPayload.supportedVersion + 1,
            accounts: [account],
            selectedAccountID: account.id
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)

        XCTAssertThrowsError(try QuotaAccountsTransferPayload.importedState(from: data)) { error in
            XCTAssertEqual(error as? QuotaAccountsTransferError, .unsupportedVersion(2))
        }
    }

    func testCodexUsageClientDecodesRemainingPercentages() async throws {
        let profileURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("brim-codex-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try Data(#"{"tokens":{"access_token":"test-token","account_id":"session-789"}}"#.utf8)
            .write(to: profileURL.appendingPathComponent("auth.json"))

        URLProtocolMock.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-ID"), "session-789")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = Data(
                """
                {
                  "account_email": "live@example.com",
                  "rate_limit": {
                    "primary_window": {
                      "remaining_percent": 84,
                      "limit_window_seconds": 18000,
                      "reset_at": 1783302960
                    },
                    "secondary_window": {
                      "remaining_percent": 40,
                      "limit_window_seconds": 604800,
                      "reset_at": 1783701180
                    }
                  }
                }
                """.utf8
            )
            return (response, data)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.self]
        let session = URLSession(configuration: configuration)
        let client = CodexUsageClient(
            session: session,
            usageURL: URL(string: "https://example.com/usage")!
        )
        let account = QuotaAccount(
            name: "Codex",
            colorHex: "#2CCB68",
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            providerProfilePath: profileURL.path,
            connectionKind: .login
        )

        let outcome = await client.fetchUsage(for: account)
        guard case .success(let result) = outcome else {
            return XCTFail("Expected live usage, got \(outcome)")
        }

        XCTAssertEqual(result.email, "live@example.com")
        XCTAssertEqual(result.accountID, "session-789")
        XCTAssertEqual(result.quota.sessionUsedPercent, 16)
        XCTAssertEqual(result.quota.weeklyUsedPercent, 60)
        XCTAssertEqual(result.quota.sessionLimitMinutes, 300)
        XCTAssertEqual(result.quota.weeklyLimitMinutes, 10_080)
    }

    func testUnknownConnectionKindFailsImport() throws {
        let data = Data(#""newProviderMode""#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(QuotaConnectionKind.self, from: data)) { error in
            guard case DecodingError.dataCorrupted(let context) = error else {
                return XCTFail("Expected a dataCorrupted error, got \(error).")
            }

            XCTAssertTrue(context.debugDescription.contains("Unknown quota connection kind"))
        }
    }
}

private final class URLProtocolMock: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
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

final class QuotaAccountColorTests: XCTestCase {
    func testNewAccountUsesFirstUnusedPresetColor() {
        let color = QuotaAccountDefaults.colorHexForNewAccount(
            existingColorHexes: ["#22c55e", "#06B6D4"]
        )

        XCTAssertEqual(color, "#3B82F6")
    }

    func testAddAccountUsesFirstUnusedPresetColorFromExistingAccounts() {
        var state = QuotaState(
            accounts: [
                testAccount(name: "First", colorHex: "#22C55E"),
                testAccount(name: "Third", colorHex: "#06B6D4")
            ]
        )

        state.addAccount()

        XCTAssertEqual(state.accounts.last?.colorHex, "#3B82F6")
    }

    func testNewAccountUsesCustomColorWhenPresetColorsAreExhausted() throws {
        let color = QuotaAccountDefaults.colorHexForNewAccount(
            existingColorHexes: QuotaAccountDefaults.presetColorHexes
        )

        XCTAssertNotNil(QuotaColor.normalizedHex(color))
        XCTAssertFalse(QuotaAccountDefaults.presetColorHexes.contains(color))
    }

    private func testAccount(name: String, colorHex: String) -> QuotaAccount {
        QuotaAccount(
            name: name,
            colorHex: colorHex,
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30
        )
    }
}
