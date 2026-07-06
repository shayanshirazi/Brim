import Combine
import Foundation
import WidgetKit

public final class QuotaStore: ObservableObject {
    private let repository: QuotaRepository
    private let widgetSnapshotStore: QuotaWidgetSnapshotStore
    private let refreshService: QuotaRefreshService

    @Published public private(set) var state: QuotaState
    @Published public private(set) var storageStatus: QuotaStorageStatus

    public var accounts: [QuotaAccount] {
        state.accounts
    }

    public var selectedAccountID: QuotaAccount.ID? {
        state.selectedAccountID
    }

    public init() {
        let repository = QuotaRepository()
        let widgetSnapshotStore = QuotaWidgetSnapshotStore()
        self.repository = repository
        self.widgetSnapshotStore = widgetSnapshotStore
        refreshService = QuotaRefreshService()
        let result = repository.load()
        state = result.state
        storageStatus = result.status

        if result.status == .firstRun {
            persist()
        }
    }

    public init(
        repository: QuotaRepository,
        widgetSnapshotStore: QuotaWidgetSnapshotStore = QuotaWidgetSnapshotStore(),
        refreshService: QuotaRefreshService = QuotaRefreshService()
    ) {
        self.repository = repository
        self.widgetSnapshotStore = widgetSnapshotStore
        self.refreshService = refreshService
        let result = repository.load()
        state = result.state
        storageStatus = result.status
    }

    public func addAccount(connectionKind: QuotaConnectionKind = .codexLogin) {
        state.addAccount(connectionKind: connectionKind)
        persist()
    }

    public func removeAccounts(at offsets: IndexSet) {
        state.removeAccounts(at: offsets)
        persist()
    }

    public func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        state.moveAccounts(fromOffsets: source, toOffset: destination)
        persist()
    }

    public func updateAccount(_ account: QuotaAccount) {
        state.updateAccount(account)
        persist()
    }

    public func selectAccount(id: QuotaAccount.ID?) {
        state.selectAccount(id: id)
        persist()
    }

    public func resetSeedData() {
        state.resetSeedData()
        persist()
    }

    public func markRefreshAttempt(for accountID: QuotaAccount.ID) {
        guard var account = accounts.first(where: { $0.id == accountID }) else {
            return
        }

        account.lastRefreshAttemptAt = Date()
        account.refreshStatus = account.connectionKind == .manual ? .manual : .waitingForQuotaSource
        account.refreshMessage = nil
        updateAccount(account)
    }

    @MainActor
    public func refreshConnectedAccounts() async {
        let now = Date()
        let connectedAccounts = accounts.filter { $0.connectionKind != .manual }

        for var account in connectedAccounts {
            account.lastRefreshAttemptAt = now
            account.refreshStatus = .waitingForQuotaSource
            account.refreshMessage = nil
            state.updateAccount(account)
        }
        persist()

        for var account in connectedAccounts {
            let result = await refreshService.refresh(account)
            account.lastRefreshAttemptAt = now
            account.refreshStatus = result.status
            account.refreshMessage = result.message

            if let accountEmail = result.accountEmail {
                account.accountEmail = accountEmail
            }

            if result.status == .ready {
                account.lastSuccessfulRefreshAt = Date()
            }

            if let quota = result.quota {
                account.weeklyLimitMinutes = quota.weeklyLimitMinutes ?? account.weeklyLimitMinutes
                account.usedMinutes = quota.usedMinutes ?? account.usedMinutes
                account.sessionLimitMinutes = quota.sessionLimitMinutes ?? account.sessionLimitMinutes
                account.sessionUsedMinutes = quota.sessionUsedMinutes ?? account.sessionUsedMinutes
                account.resetWeekday = quota.resetWeekday ?? account.resetWeekday
                account.resetHour = quota.resetHour ?? account.resetHour
                account.resetMinute = quota.resetMinute ?? account.resetMinute
            }

            state.updateAccount(account)
        }
        persist()
    }

    private func persist(reloadWidget: Bool = true) {
        storageStatus = repository.save(state)
        if reloadWidget {
            let widgetStatus = widgetSnapshotStore.save(state)
            if storageStatus == .ready, widgetStatus == .unavailable {
                storageStatus = .unavailable
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

public enum QuotaWidgetCommands {
    public static func snapshot() -> QuotaState {
        let result = QuotaWidgetSnapshotStore().load()
        if result.status == .unavailable {
            return QuotaRepository().load().state
        }
        return result.state
    }

    public static func selectAccount(id: QuotaAccount.ID?) {
        update { state in
            state.selectAccount(id: id)
        }
    }

    public static func setAccountTextHidden(_ isHidden: Bool) {
        update { state in
            state.setAccountTextHidden(isHidden)
        }
    }

    public static func toggleAccountTextHidden() {
        update { state in
            state.toggleAccountTextHidden()
        }
    }

    public static func setWidgetPageIndex(_ pageIndex: Int, pageSize: Int) {
        update { state in
            state.setWidgetPageIndex(pageIndex, pageSize: pageSize)
        }
    }

    public static func moveWidgetPage(by offset: Int, pageSize: Int) {
        update { state in
            state.moveWidgetPage(by: offset, pageSize: pageSize)
        }
    }

    private static func update(_ mutate: (inout QuotaState) -> Void) {
        let snapshotStore = QuotaWidgetSnapshotStore()
        var state = snapshotStore.load().state
        mutate(&state)
        _ = snapshotStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

public struct QuotaRefreshService {
    public var apiTokenIsAvailable: (String) -> Bool
    public var commandRunner: (String, String) async -> CommandResult

    public init(
        apiTokenIsAvailable: @escaping (String) -> Bool = { _ in false },
        commandRunner: @escaping (String, String) async -> CommandResult = { _, _ in
            CommandResult(
                exitCode: -1,
                standardOutput: "",
                standardError: "Codex status runner is not configured."
            )
        }
    ) {
        self.apiTokenIsAvailable = apiTokenIsAvailable
        self.commandRunner = commandRunner
    }

    public func refresh(_ account: QuotaAccount) async -> QuotaRefreshResult {
        switch account.connectionKind {
        case .manual:
            return QuotaRefreshResult(status: .manual, message: "Manual values are used.", quota: nil)
        case .apiToken:
            guard let credentialID = account.credentialID, apiTokenIsAvailable(credentialID) else {
                return QuotaRefreshResult(
                    status: .notConnected,
                    message: "Add an API token before automatic quota refresh can run.",
                    quota: nil
                )
            }

            let quota = readLocalQuotaSnapshot(for: account)
            return QuotaRefreshResult(
                status: .ready,
                message: quota == nil
                    ? "API token is saved in Keychain. Brim has no configured quota endpoint yet."
                    : "Loaded quota snapshot from local profile.",
                quota: quota
            )
        case .codexLogin:
            let profilePath = QuotaFormatting.expandedHomePath(account.resolvedCodexProfilePath)
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: profilePath, isDirectory: true),
                    withIntermediateDirectories: true
                )
            } catch {
                return QuotaRefreshResult(
                    status: .refreshFailed,
                    message: "Brim could not create the Codex profile folder.",
                    quota: nil
                )
            }

            let result = await commandRunner(profilePath, "login status")
            let output = (result.standardOutput + "\n" + result.standardError).lowercased()

            if result.exitCode == 0, output.contains("logged in") {
                let quota = readLocalQuotaSnapshot(for: account)
                return QuotaRefreshResult(
                    status: .ready,
                    message: quota == nil
                        ? "Codex login is valid. Add a local quota snapshot when Codex exposes usage data."
                        : "Loaded quota snapshot from local profile.",
                    quota: quota,
                    accountEmail: QuotaFormatting.emailAddress(in: result.standardOutput + "\n" + result.standardError)
                )
            }

            if output.contains("not logged in") {
                return QuotaRefreshResult(
                    status: .notConnected,
                    message: "Sign in with Codex to connect this account.",
                    quota: nil
                )
            }

            return QuotaRefreshResult(
                status: .refreshFailed,
                message: "Brim could not check the Codex session.",
                quota: nil
            )
        }
    }

    private func readLocalQuotaSnapshot(for account: QuotaAccount) -> QuotaUsageSnapshot? {
        let profilePath = QuotaFormatting.expandedHomePath(account.resolvedCodexProfilePath)
        let previousQuotaFilename = "\(BrimStorage.previousKey("").dropLast())-quota.json"
        let candidates = [
            URL(fileURLWithPath: profilePath).appendingPathComponent("brim-quota.json"),
            URL(fileURLWithPath: profilePath).appendingPathComponent(previousQuotaFilename),
            URL(fileURLWithPath: profilePath).appendingPathComponent("quota.json")
        ]

        for url in candidates {
            guard
                let data = try? Data(contentsOf: url),
                let quota = try? JSONDecoder().decode(QuotaUsageSnapshot.self, from: data)
            else {
                continue
            }

            return quota
        }

        return nil
    }

}

public struct QuotaRefreshResult {
    public var status: QuotaRefreshStatus
    public var message: String?
    public var quota: QuotaUsageSnapshot?
    public var accountEmail: String?

    public init(status: QuotaRefreshStatus, message: String?, quota: QuotaUsageSnapshot?, accountEmail: String? = nil) {
        self.status = status
        self.message = message
        self.quota = quota
        self.accountEmail = accountEmail
    }
}

public struct QuotaUsageSnapshot: Codable, Hashable {
    public var weeklyLimitMinutes: Int?
    public var usedMinutes: Int?
    public var sessionLimitMinutes: Int?
    public var sessionUsedMinutes: Int?
    public var resetWeekday: Int?
    public var resetHour: Int?
    public var resetMinute: Int?

    public init(
        weeklyLimitMinutes: Int? = nil,
        usedMinutes: Int? = nil,
        sessionLimitMinutes: Int? = nil,
        sessionUsedMinutes: Int? = nil,
        resetWeekday: Int? = nil,
        resetHour: Int? = nil,
        resetMinute: Int? = nil
    ) {
        self.weeklyLimitMinutes = weeklyLimitMinutes
        self.usedMinutes = usedMinutes
        self.sessionLimitMinutes = sessionLimitMinutes
        self.sessionUsedMinutes = sessionUsedMinutes
        self.resetWeekday = resetWeekday
        self.resetHour = resetHour
        self.resetMinute = resetMinute
    }
}

public struct CommandResult: Hashable {
    public var exitCode: Int32
    public var standardOutput: String
    public var standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
