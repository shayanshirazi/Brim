import XCTest
@testable import Brim

final class QuotaRefreshServiceTests: XCTestCase {
    func testStoreClearsExistingUsageSnapshotWhenLiveUsageIsUnavailable() async throws {
        let suiteName = "dev.brim.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        var account = testLoginAccount()
        account.hasUsageSnapshot = true
        account.refreshStatus = .ready
        account.weeklyLimitMinutes = 300
        account.usedMinutes = 45
        account.sessionLimitMinutes = 300
        account.sessionUsedMinutes = 30

        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(QuotaState(accounts: [account], selectedAccountID: account.id))

        let snapshotURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("brim-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
        let widgetSnapshotStore = QuotaWidgetSnapshotStore(repository: nil, fallbackURL: snapshotURL)
        let service = QuotaRefreshService(
            commandRunner: { _, _ in
                CommandResult(exitCode: 0, standardOutput: "Logged in", standardError: "")
            },
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

        var selectedAccount = testLoginAccount()
        selectedAccount.name = "Selected"
        selectedAccount.weeklyLimitMinutes = 300
        selectedAccount.usedMinutes = 0

        var otherAccount = testLoginAccount()
        otherAccount.id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        otherAccount.name = "Other"
        otherAccount.weeklyLimitMinutes = 300
        otherAccount.usedMinutes = 10

        let repository = QuotaRepository(defaults: defaults, previousDefaults: nil)
        repository.save(QuotaState(accounts: [selectedAccount, otherAccount], selectedAccountID: selectedAccount.id))

        let snapshotURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("brim-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
        let widgetSnapshotStore = QuotaWidgetSnapshotStore(repository: nil, fallbackURL: snapshotURL)
        let service = QuotaRefreshService(
            commandRunner: { _, _ in
                CommandResult(exitCode: 0, standardOutput: "Logged in", standardError: "")
            },
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

    func testCodexLoginUsesLiveUsageWhenAvailable() async {
        let account = testLoginAccount()
        let service = QuotaRefreshService(
            commandRunner: { _, _ in
                CommandResult(exitCode: 0, standardOutput: "Logged in as user@example.com", standardError: "")
            },
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
                        email: "live@example.com"
                    )
                )
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.message, "Loaded live Codex usage.")
        XCTAssertEqual(result.accountEmail, "live@example.com")
        XCTAssertEqual(result.quota?.weeklyLimitMinutes, 600)
        XCTAssertEqual(result.quota?.usedMinutes, 120)
        XCTAssertEqual(result.quota?.weeklyUsedPercent, 20)
        XCTAssertEqual(result.quota?.sessionUsedPercent, 10)
    }

    func testCodexLoginKeepsIdentityWhenUsageHasNoQuota() async {
        let account = testLoginAccount()
        let service = QuotaRefreshService(
            commandRunner: { _, _ in
                CommandResult(exitCode: 0, standardOutput: "Logged in", standardError: "")
            },
            usageFetcher: { _ in
                .unavailable(
                    "Codex usage response did not include rate-limit data Brim understands.",
                    accountEmail: "identity@example.com"
                )
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.accountEmail, "identity@example.com")
        XCTAssertNil(result.quota)
    }

    func testCodexLoginFallsBackToStatusEmailWhenUsageHasNoEmail() async {
        let account = testLoginAccount()
        let service = QuotaRefreshService(
            commandRunner: { _, _ in
                CommandResult(exitCode: 0, standardOutput: "Logged in as status@example.com", standardError: "")
            },
            usageFetcher: { _ in
                .success(
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

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.accountEmail, "status@example.com")
    }

    func testCodexLoginReturnsFetcherFailureWhenNoSnapshotExists() async {
        let account = testLoginAccount()
        let service = QuotaRefreshService(
            commandRunner: { _, _ in
                CommandResult(exitCode: 0, standardOutput: "Logged in", standardError: "")
            },
            usageFetcher: { _ in
                .unavailable("Codex usage request failed with HTTP 401.", accountEmail: nil)
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .ready)
        XCTAssertEqual(result.message, "Codex usage request failed with HTTP 401.")
        XCTAssertNil(result.quota)
    }

    func testCodexLoginTreatsNotLoggedInOutputAsDisconnected() async {
        let account = testLoginAccount()
        var didFetchUsage = false
        let service = QuotaRefreshService(
            commandRunner: { _, _ in
                CommandResult(exitCode: 0, standardOutput: "Not logged in", standardError: "")
            },
            usageFetcher: { _ in
                didFetchUsage = true
                return .unavailable("Should not fetch usage for a disconnected session.", accountEmail: nil)
            }
        )

        let result = await service.refresh(account)

        XCTAssertEqual(result.status, .notConnected)
        XCTAssertEqual(result.message, "Sign in with Codex to connect this account.")
        XCTAssertNil(result.quota)
        XCTAssertFalse(didFetchUsage)
    }

    func testCommandMessageKeepsStderrAfterFilteringIgnoredStdoutWarnings() {
        let result = CommandResult(
            exitCode: 1,
            standardOutput: "WARNING: proceeding despite CODEX_HOME points at a missing path",
            standardError: "Authentication token expired"
        )

        let message = CodexLoginStatusClassifier.commandMessage(
            from: result,
            fallbackMessage: "Brim could not check the Codex session.",
            ignoredFragments: ["WARNING: proceeding", "CODEX_HOME points"]
        )

        XCTAssertEqual(message, "Authentication token expired")
    }

    private func testLoginAccount() -> QuotaAccount {
        QuotaAccount(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Codex",
            colorHex: "#2CCB68",
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 9,
            resetMinute: 30,
            providerProfilePath: NSTemporaryDirectory().appending("brim-tests/missing-profile"),
            connectionKind: .login
        )
    }
}
