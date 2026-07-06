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
        let repositoryLoadResult = repository.load()
        state = repositoryLoadResult.state
        storageStatus = repositoryLoadResult.status

        if repositoryLoadResult.status == .firstRun {
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
        let repositoryLoadResult = repository.load()
        state = repositoryLoadResult.state
        storageStatus = repositoryLoadResult.status
    }

    public func addAccount(
        provider: QuotaProviderKind = .codex,
        connectionKind: QuotaConnectionKind = .login
    ) {
        state.addAccount(provider: provider, connectionKind: connectionKind)
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

    public func exportAccountsTransferData() throws -> Data {
        let accountsTransferPayload = QuotaAccountsTransferPayload(state: state)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(accountsTransferPayload)
    }

    public func importAccountsTransferData(_ accountsTransferData: Data) throws {
        state = try QuotaAccountsTransferPayload.importedState(from: accountsTransferData)
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
        let connectedAccounts = accounts.filter { $0.connectionKind != .manual }
        await refresh(accounts: connectedAccounts)
    }

    @MainActor
    public func refreshAccount(id accountID: QuotaAccount.ID) async {
        guard let account = accounts.first(where: { $0.id == accountID }), account.connectionKind != .manual else {
            return
        }

        await refresh(accounts: [account])
    }

    @MainActor
    private func refresh(accounts accountsToRefresh: [QuotaAccount]) async {
        let now = Date()

        for var account in accountsToRefresh {
            account.lastRefreshAttemptAt = now
            account.refreshStatus = .waitingForQuotaSource
            account.refreshMessage = nil
            state.updateAccount(account)
        }
        persist()

        for var account in accountsToRefresh {
            let refreshResult = await refreshService.refresh(account)
            account.lastRefreshAttemptAt = now
            account.refreshStatus = refreshResult.status
            account.refreshMessage = refreshResult.message

            if let accountEmail = refreshResult.accountEmail {
                account.accountEmail = accountEmail
            }

            if refreshResult.status == .ready {
                account.lastSuccessfulRefreshAt = Date()
            }

            if let quotaSnapshot = refreshResult.quota {
                account.weeklyLimitMinutes = quotaSnapshot.weeklyLimitMinutes ?? account.weeklyLimitMinutes
                account.usedMinutes = quotaSnapshot.usedMinutes ?? account.usedMinutes
                account.sessionLimitMinutes = quotaSnapshot.sessionLimitMinutes ?? account.sessionLimitMinutes
                account.sessionUsedMinutes = quotaSnapshot.sessionUsedMinutes ?? account.sessionUsedMinutes
                account.weeklyUsedPercent = quotaSnapshot.weeklyUsedPercent
                account.sessionUsedPercent = quotaSnapshot.sessionUsedPercent
                account.sessionResetAt = quotaSnapshot.sessionResetAt
                account.weeklyResetAt = quotaSnapshot.weeklyResetAt
                account.resetWeekday = quotaSnapshot.resetWeekday ?? account.resetWeekday
                account.resetHour = quotaSnapshot.resetHour ?? account.resetHour
                account.resetMinute = quotaSnapshot.resetMinute ?? account.resetMinute
                account.hasUsageSnapshot = true
            } else if account.connectionKind != .manual {
                account.hasUsageSnapshot = false
                account.weeklyUsedPercent = nil
                account.sessionUsedPercent = nil
                account.sessionResetAt = nil
                account.weeklyResetAt = nil
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
