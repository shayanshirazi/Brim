import Combine
import Foundation
import WidgetKit

public final class QuotaStore: ObservableObject {
    private let repository: QuotaRepository
    private let widgetSnapshotStore: QuotaWidgetSnapshotStore
    private let refreshService: QuotaRefreshService

    @Published public private(set) var state: QuotaState
    @Published public private(set) var storageStatus: QuotaStorageStatus
    private var activeRefresh: Task<Void, Never>?

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

        // Publish the widget snapshot on every launch so the shared container is
        // populated even when no mutation happens this session.
        if result.status == .ready || result.status == .firstRun {
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

        if result.status == .ready || result.status == .firstRun {
            persist()
        }
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

    public func exportAccountsData() throws -> Data {
        let payload = QuotaAccountsTransferPayload(state: state)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    public func importAccountsData(_ data: Data) throws {
        state = try QuotaAccountsTransferPayload.importedState(from: data)
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
        // Concurrent refreshes race the OAuth refresh-token rotation and can save
        // a revoked token, killing the session. Serialize: chain onto any run in
        // flight rather than dropping the request. Only IDs are captured — the
        // accounts are re-read when the run starts so a queued refresh cannot
        // replay stale snapshots over newer edits.
        let accountIDs = accountsToRefresh.map(\.id)
        let previous = activeRefresh
        let task = Task { @MainActor in
            await previous?.value
            await performRefresh(accountIDs: accountIDs)
        }
        activeRefresh = task
        await task.value
        if activeRefresh == task {
            activeRefresh = nil
        }
    }

    @MainActor
    private func performRefresh(accountIDs: [QuotaAccount.ID]) async {
        let accountsToRefresh = accounts.filter { accountIDs.contains($0.id) && $0.connectionKind != .manual }
        let now = Date()

        for var account in accountsToRefresh {
            account.lastRefreshAttemptAt = now
            account.refreshStatus = .waitingForQuotaSource
            account.refreshMessage = nil
            state.updateAccount(account)
        }
        persist(reloadWidget: false)

        for var account in accountsToRefresh {
            let result = await refreshService.refresh(account)
            account.lastRefreshAttemptAt = now
            account.refreshStatus = result.status
            account.refreshMessage = result.message

            if let accountEmail = result.accountEmail {
                account.accountEmail = accountEmail
            }
            if let providerAccountID = result.providerAccountID {
                account.providerAccountID = providerAccountID
            }

            if result.status == .ready, !result.preservesExistingQuota {
                account.lastSuccessfulRefreshAt = Date()
            }

            if let quota = result.quota {
                account.weeklyLimitMinutes = quota.weeklyLimitMinutes ?? account.weeklyLimitMinutes
                account.usedMinutes = quota.usedMinutes ?? account.usedMinutes
                account.sessionLimitMinutes = quota.sessionLimitMinutes ?? account.sessionLimitMinutes
                account.sessionUsedMinutes = quota.sessionUsedMinutes ?? account.sessionUsedMinutes
                account.weeklyUsedPercent = quota.weeklyUsedPercent
                account.sessionUsedPercent = quota.sessionUsedPercent
                account.sessionResetAt = quota.sessionResetAt
                account.weeklyResetAt = quota.weeklyResetAt
                account.resetWeekday = quota.resetWeekday ?? account.resetWeekday
                account.resetHour = quota.resetHour ?? account.resetHour
                account.resetMinute = quota.resetMinute ?? account.resetMinute
                account.hasUsageSnapshot = true
            } else if account.connectionKind != .manual, !result.preservesExistingQuota {
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

public struct QuotaAccountsTransferPayload: Codable {
    public static let supportedVersion = 1

    public var version: Int
    public var exportedAt: Date
    public var accounts: [QuotaAccount]
    public var selectedAccountID: QuotaAccount.ID?
    public var isAccountTextHidden: Bool
    public var widgetPageIndex: Int

    public init(
        version: Int = Self.supportedVersion,
        exportedAt: Date = Date(),
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID?,
        isAccountTextHidden: Bool,
        widgetPageIndex: Int
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.accounts = accounts.map(Self.accountForExport)
        self.selectedAccountID = selectedAccountID
        self.isAccountTextHidden = isAccountTextHidden
        self.widgetPageIndex = widgetPageIndex
    }

    public init(state: QuotaState) {
        self.init(
            accounts: state.accounts,
            selectedAccountID: state.selectedAccountID,
            isAccountTextHidden: state.isAccountTextHidden,
            widgetPageIndex: state.widgetPageIndex
        )
    }

    public func stateForImport() -> QuotaState {
        Self.stateForImport(
            accounts: accounts,
            selectedAccountID: selectedAccountID,
            isAccountTextHidden: isAccountTextHidden,
            widgetPageIndex: widgetPageIndex
        )
    }

    public static func importPreview(from data: Data) throws -> QuotaAccountsImportPreview {
        let state = try importedState(from: data)
        return QuotaAccountsImportPreview(accountCount: state.accounts.count)
    }

    public static func importedState(from data: Data) throws -> QuotaState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let payload = try decoder.decode(QuotaAccountsTransferPayload.self, from: data)
            guard payload.version == supportedVersion else {
                throw QuotaAccountsTransferError.unsupportedVersion(payload.version)
            }
            return payload.stateForImport()
        } catch {
            if error is QuotaAccountsTransferError {
                throw error
            }
            let accounts = try decoder.decode([QuotaAccount].self, from: data)
            return stateForImport(
                accounts: accounts,
                selectedAccountID: accounts.first?.id,
                isAccountTextHidden: false,
                widgetPageIndex: 0
            )
        }
    }

    public static func stateForImport(
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID?,
        isAccountTextHidden: Bool,
        widgetPageIndex: Int
    ) -> QuotaState {
        QuotaState(
            accounts: accounts.map(accountForImport),
            selectedAccountID: selectedAccountID,
            isAccountTextHidden: isAccountTextHidden,
            widgetPageIndex: widgetPageIndex
        )
    }

    private static func accountForExport(_ account: QuotaAccount) -> QuotaAccount {
        account.portableExportAccount()
    }

    private static func accountForImport(_ account: QuotaAccount) -> QuotaAccount {
        account.portableImportAccount()
    }
}

public enum QuotaAccountsTransferError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This Brim export uses version \(version), which this app cannot import."
        }
    }
}

public struct QuotaAccountsImportPreview: Hashable {
    public var accountCount: Int

    public init(accountCount: Int) {
        self.accountCount = accountCount
    }
}

public enum QuotaWidgetCommands {
    public static func snapshot() -> QuotaState {
        let result = QuotaWidgetSnapshotStore().load()
        if result.status == .unavailable {
            return QuotaRepository().load().state.widgetSnapshotState()
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
        let loadResult = snapshotStore.load()
        guard loadResult.status != .unavailable else {
            return
        }

        var state = loadResult.state
        mutate(&state)
        _ = snapshotStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

public struct QuotaRefreshService {
    /// Minimum spacing between billable API-key probes; UI refreshes inside this
    /// window reuse the existing snapshot.
    public static let apiProbeMinimumInterval: TimeInterval = 25 * 60

    public var apiTokenIsAvailable: (String) -> Bool
    public var apiTokenProvider: (String) -> String?
    public var usageFetcher: (QuotaAccount) async -> CodexUsageFetchOutcome
    public var apiLimitsFetcher: (QuotaAccount, String) async -> APIRateLimitOutcome

    public init(
        apiTokenIsAvailable: @escaping (String) -> Bool = { _ in false },
        apiTokenProvider: @escaping (String) -> String? = { _ in nil },
        usageFetcher: @escaping (QuotaAccount) async -> CodexUsageFetchOutcome = { account in
            await CodexUsageClient().fetchUsage(for: account)
        },
        apiLimitsFetcher: @escaping (QuotaAccount, String) async -> APIRateLimitOutcome = { account, apiKey in
            switch account.provider {
            case .claude:
                return await AnthropicAPIRateLimitClient().fetchRateLimits(apiKey: apiKey)
            case .codex, .chatgpt:
                return await OpenAIAPIRateLimitClient().fetchRateLimits(
                    apiKey: apiKey,
                    includeEmail: account.normalizedAccountEmail == nil
                )
            case .gemini:
                return await GeminiAPIKeyClient().checkKey(apiKey: apiKey)
            }
        }
    ) {
        self.apiTokenIsAvailable = apiTokenIsAvailable
        self.apiTokenProvider = apiTokenProvider
        self.usageFetcher = usageFetcher
        self.apiLimitsFetcher = apiLimitsFetcher
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

            if let apiKey = apiTokenProvider(credentialID) {
                // Live probes can be billable (1-token completions); with fresh data
                // in hand, skip the network and keep the current snapshot.
                if account.hasUsageSnapshot,
                   let lastSuccess = account.lastSuccessfulRefreshAt,
                   Date().timeIntervalSince(lastSuccess) < Self.apiProbeMinimumInterval {
                    return QuotaRefreshResult(
                        status: .ready,
                        message: account.refreshMessage,
                        quota: nil,
                        preservesExistingQuota: true
                    )
                }

                let outcome = await apiLimitsFetcher(account, apiKey)
                if outcome.unauthorized {
                    return QuotaRefreshResult(
                        status: .notConnected,
                        message: outcome.failureMessage ?? "The saved API key was rejected. Save a new key.",
                        quota: nil,
                        providerAccountID: outcome.organizationID
                    )
                }

                if let quota = outcome.quota {
                    return QuotaRefreshResult(
                        status: .ready,
                        message: "Loaded \(account.provider.displayName) API rate limits (per-minute windows).",
                        quota: quota,
                        accountEmail: outcome.accountEmail,
                        providerAccountID: outcome.organizationID
                    )
                }

                let localQuota = readLocalQuotaSnapshot(for: account)
                return QuotaRefreshResult(
                    status: .ready,
                    message: outcome.failureMessage ?? "\(account.provider.displayName) API rate limits are unavailable right now.",
                    quota: localQuota,
                    providerAccountID: outcome.organizationID,
                    // A transient probe failure must not blank rings that were live.
                    preservesExistingQuota: localQuota == nil
                )
            }

            let quota = readLocalQuotaSnapshot(for: account)
            return QuotaRefreshResult(
                status: .ready,
                message: quota == nil
                    ? "\(account.provider.displayName) token is saved. Exact usage opens in \(account.provider.displayName)."
                    : "Loaded quota snapshot from local profile.",
                quota: quota
            )
        case .login:
            switch account.provider {
            case .codex, .chatgpt:
                // ChatGPT shares the Codex OAuth backend; the usage endpoint reports
                // the same ChatGPT-plan rate-limit windows.
                return await refreshCodexLogin(account)
            case .claude:
                return QuotaRefreshResult(
                    status: .notConnected,
                    message: "Claude sign-in isn't supported yet. Connect with an Anthropic API key instead.",
                    quota: nil
                )
            case .gemini:
                return QuotaRefreshResult(
                    status: .notConnected,
                    message: "Gemini sign-in isn't supported. Connect with a Google AI API key instead.",
                    quota: nil
                )
            }
        }
    }

    private func refreshCodexLogin(_ account: QuotaAccount) async -> QuotaRefreshResult {
        let profilePath = QuotaFormatting.expandedHomePath(account.resolvedProviderProfilePath)
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

        guard CodexProfileAuthStore.hasUsableTokens(profilePath: profilePath) else {
            return QuotaRefreshResult(
                status: .notConnected,
                message: "Sign in with Codex to connect this account.",
                quota: nil
            )
        }

        let usageOutcome = await usageFetcher(account)
        if usageOutcome.isUnauthorized {
            return QuotaRefreshResult(
                status: .notConnected,
                message: usageOutcome.message,
                quota: nil,
                accountEmail: usageOutcome.accountEmail,
                providerAccountID: usageOutcome.accountID
            )
        }

        let usage = usageOutcome.result
        let quota = usage?.quota ?? readLocalQuotaSnapshot(for: account)
        return QuotaRefreshResult(
            status: .ready,
            message: quota == nil
                ? usageOutcome.message
                : (usage == nil ? "Loaded quota snapshot from local profile." : "Loaded live Codex usage."),
            quota: quota,
            accountEmail: usageOutcome.accountEmail,
            providerAccountID: usageOutcome.accountID
        )
    }

    private func readLocalQuotaSnapshot(for account: QuotaAccount) -> QuotaUsageSnapshot? {
        let profilePath = QuotaFormatting.expandedHomePath(account.resolvedProviderProfilePath)
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

public struct APIRateLimitOutcome {
    public var quota: QuotaUsageSnapshot?
    public var organizationID: String?
    public var accountEmail: String?
    public var failureMessage: String?
    public var unauthorized: Bool

    public init(
        quota: QuotaUsageSnapshot? = nil,
        organizationID: String? = nil,
        accountEmail: String? = nil,
        failureMessage: String? = nil,
        unauthorized: Bool = false
    ) {
        self.quota = quota
        self.organizationID = organizationID
        self.accountEmail = accountEmail
        self.failureMessage = failureMessage
        self.unauthorized = unauthorized
    }
}

/// Reads live OpenAI API rate limits from the documented `x-ratelimit-*` response
/// headers. API keys have per-minute request/token windows, not the ChatGPT plan's
/// 5h/weekly Codex windows, and they expose no user email — only an organization ID.
public struct OpenAIAPIRateLimitClient {
    private let modelsURL: URL
    private let completionsURL: URL
    private let session: URLSession
    private let now: () -> Date

    public init(
        modelsURL: URL = URL(string: "https://api.openai.com/v1/models")!,
        completionsURL: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.modelsURL = modelsURL
        self.completionsURL = completionsURL
        self.session = session
        self.now = now
    }

    public func fetchRateLimits(apiKey: String, includeEmail: Bool = true) async -> APIRateLimitOutcome {
        // 1) List the key's own models: validates auth and tells us which model the
        //    probe may use (project keys often lack access to specific models).
        var request = URLRequest(url: modelsURL)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var organizationID: String?
        var availableModels: [String] = []
        if let (data, response) = await httpResult(for: request) {
            organizationID = response.value(forHTTPHeaderField: "openai-organization")

            if response.statusCode == 401 || response.statusCode == 403 {
                return APIRateLimitOutcome(
                    organizationID: organizationID,
                    failureMessage: "OpenAI rejected the API token (HTTP \(response.statusCode)).",
                    unauthorized: true
                )
            }

            if 200..<300 ~= response.statusCode, let quota = quotaSnapshot(from: response) {
                return APIRateLimitOutcome(quota: quota, organizationID: organizationID)
            }

            availableModels = Self.modelIDs(from: data)
        }

        // 2) One-token completion on a model this key can actually use — the
        //    documented carrier of the x-ratelimit headers (present even on 429).
        let probeModel = Self.probeModel(from: availableModels)
        var lastErrorMessage: String?
        var lastErrorCode: String?
        var lastStatus = 0

        for tokenParameter in ["max_completion_tokens", "max_tokens"] {
            var probe = URLRequest(url: completionsURL)
            probe.httpMethod = "POST"
            probe.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            probe.setValue("application/json", forHTTPHeaderField: "Content-Type")
            probe.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": probeModel,
                "messages": [["role": "user", "content": "."]],
                tokenParameter: 1
            ])

            guard let (data, response) = await httpResult(for: probe) else {
                return APIRateLimitOutcome(
                    organizationID: organizationID,
                    failureMessage: "OpenAI API request failed. Check your connection."
                )
            }

            organizationID = response.value(forHTTPHeaderField: "openai-organization") ?? organizationID

            // Headers on other error statuses (400 model rejected, 404) describe
            // the failed call, not usable capacity.
            if response.statusCode < 300 || response.statusCode == 429, let quota = quotaSnapshot(from: response) {
                var outcome = APIRateLimitOutcome(quota: quota, organizationID: organizationID)
                if includeEmail {
                    outcome.accountEmail = await fetchEmail(apiKey: apiKey)
                }
                return outcome
            }

            lastStatus = response.statusCode
            lastErrorMessage = Self.errorField(from: data, key: "message")
            lastErrorCode = Self.errorField(from: data, key: "code")

            // Only retry with the legacy parameter when that's what was rejected.
            guard lastErrorMessage?.contains(tokenParameter) == true else {
                break
            }
        }

        if lastErrorCode == "insufficient_quota" {
            return APIRateLimitOutcome(
                organizationID: organizationID,
                failureMessage: "This OpenAI key has no billing credit left, so OpenAI reports no rate limits for it. Add credit at platform.openai.com, or use Login instead."
            )
        }

        let detail = lastErrorMessage.map { " OpenAI said: \($0)" } ?? ""
        return APIRateLimitOutcome(
            organizationID: organizationID,
            failureMessage: "No rate-limit data for this token (HTTP \(lastStatus), model \(probeModel)).\(detail)"
        )
    }

    /// Best-effort identity lookup; API keys usually expose no email, but /v1/me
    /// returns one for user-scoped keys.
    private func fetchEmail(apiKey: String) async -> String? {
        guard let url = URL(string: "https://api.openai.com/v1/me") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard
            let (data, response) = await httpResult(for: request),
            200..<300 ~= response.statusCode,
            let object = Self.jsonDictionary(from: data)
        else {
            return nil
        }

        return object["email"] as? String
    }

    private static func modelIDs(from data: Data) -> [String] {
        guard let entries = jsonDictionary(from: data)?["data"] as? [[String: Any]] else {
            return []
        }

        return entries.compactMap { $0["id"] as? String }
    }

    private static func probeModel(from availableModels: [String]) -> String {
        let preferred = ["gpt-4o-mini", "gpt-4.1-nano", "gpt-4.1-mini", "gpt-5-nano", "gpt-5-mini", "gpt-4o", "gpt-4.1"]
        for candidate in preferred where availableModels.contains(candidate) {
            return candidate
        }

        // Any chat-family model the key can reach; avoid non-chat endpoints.
        if let anyGPT = availableModels.first(where: { $0.hasPrefix("gpt-") && !$0.contains("instruct") }) {
            return anyGPT
        }

        return "gpt-4o-mini"
    }

    private static func jsonDictionary(from data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func errorField(from data: Data, key: String) -> String? {
        guard let error = jsonDictionary(from: data)?["error"] as? [String: Any] else {
            return nil
        }

        return error[key] as? String
    }

    private func httpResult(for request: URLRequest) async -> (Data, HTTPURLResponse)? {
        guard
            let (data, response) = try? await session.data(for: request),
            let httpResponse = response as? HTTPURLResponse
        else {
            return nil
        }

        return (data, httpResponse)
    }

    private func quotaSnapshot(from response: HTTPURLResponse) -> QuotaUsageSnapshot? {
        func headerDouble(_ name: String) -> Double? {
            response.value(forHTTPHeaderField: name).flatMap(Double.init)
        }

        guard
            let requestLimit = headerDouble("x-ratelimit-limit-requests"), requestLimit > 0,
            let requestsRemaining = headerDouble("x-ratelimit-remaining-requests")
        else {
            return nil
        }

        let requestsUsedPercent = min(100, max(0, (1 - requestsRemaining / requestLimit) * 100))

        var tokensUsedPercent: Double?
        if
            let tokenLimit = headerDouble("x-ratelimit-limit-tokens"), tokenLimit > 0,
            let tokensRemaining = headerDouble("x-ratelimit-remaining-tokens") {
            tokensUsedPercent = min(100, max(0, (1 - tokensRemaining / tokenLimit) * 100))
        }

        let reference = now()
        let requestsReset = Self.resetInterval(response.value(forHTTPHeaderField: "x-ratelimit-reset-requests"))
        let tokensReset = Self.resetInterval(response.value(forHTTPHeaderField: "x-ratelimit-reset-tokens"))

        // Requests-per-minute maps to the session ring, tokens-per-minute to the
        // weekly ring. Limit-minute fields stay nil so the account's stored plan
        // limits are never clobbered by per-minute API windows.
        return QuotaUsageSnapshot(
            weeklyUsedPercent: tokensUsedPercent ?? requestsUsedPercent,
            sessionUsedPercent: requestsUsedPercent,
            sessionResetAt: requestsReset.map { reference.addingTimeInterval($0) },
            weeklyResetAt: tokensReset.map { reference.addingTimeInterval($0) }
        )
    }

    private static let resetRegex = try! NSRegularExpression(pattern: "([0-9]*\\.?[0-9]+)(ms|h|m|s)")

    /// Parses OpenAI reset durations like "12ms", "7.66s", "1m30s", "1h2m3s".
    static func resetInterval(_ raw: String?) -> TimeInterval? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else {
            return nil
        }

        let matches = Self.resetRegex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
        guard !matches.isEmpty else {
            return nil
        }

        var total: TimeInterval = 0
        for match in matches {
            guard
                let valueRange = Range(match.range(at: 1), in: raw),
                let unitRange = Range(match.range(at: 2), in: raw),
                let value = Double(raw[valueRange])
            else {
                continue
            }

            switch raw[unitRange] {
            case "ms": total += value / 1000
            case "s": total += value
            case "m": total += value * 60
            case "h": total += value * 3600
            default: break
            }
        }

        return total
    }
}

/// Reads live Anthropic API rate limits from the documented `anthropic-ratelimit-*`
/// response headers (requests + input/output tokens per minute; RFC 3339 resets).
/// Probes the free token-count endpoint first, then a 1-token Haiku message.
public struct AnthropicAPIRateLimitClient {
    private static let resetDateFormatter = ISO8601DateFormatter()

    private let countTokensURL: URL
    private let messagesURL: URL
    private let session: URLSession
    private let now: () -> Date

    public init(
        countTokensURL: URL = URL(string: "https://api.anthropic.com/v1/messages/count_tokens")!,
        messagesURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        self.countTokensURL = countTokensURL
        self.messagesURL = messagesURL
        self.session = session
        self.now = now
    }

    public func fetchRateLimits(apiKey: String) async -> APIRateLimitOutcome {
        // Free probe first: count_tokens costs nothing.
        if let response = await httpResponse(for: request(url: countTokensURL, apiKey: apiKey, maxTokens: nil)) {
            if response.statusCode == 401 || response.statusCode == 403 {
                return APIRateLimitOutcome(
                    failureMessage: "Anthropic rejected the API key (HTTP \(response.statusCode)).",
                    unauthorized: true
                )
            }

            if 200..<300 ~= response.statusCode, let quota = quotaSnapshot(from: response) {
                return APIRateLimitOutcome(quota: quota)
            }
        }

        // Fall back to a 1-token message on the cheapest model; rate-limit
        // headers are documented on Messages API responses (even 429s).
        guard let response = await httpResponse(for: request(url: messagesURL, apiKey: apiKey, maxTokens: 1)) else {
            return APIRateLimitOutcome(
                failureMessage: "Anthropic API request failed. Check your connection."
            )
        }

        guard
            response.statusCode < 300 || response.statusCode == 429,
            let quota = quotaSnapshot(from: response)
        else {
            return APIRateLimitOutcome(
                failureMessage: "Anthropic did not report rate limits for this key (HTTP \(response.statusCode))."
            )
        }

        return APIRateLimitOutcome(quota: quota)
    }

    private func request(url: URL, apiKey: String, maxTokens: Int?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "messages": [["role": "user", "content": "."]]
        ]
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func httpResponse(for request: URLRequest) async -> HTTPURLResponse? {
        guard let (_, response) = try? await session.data(for: request) else {
            return nil
        }

        return response as? HTTPURLResponse
    }

    private func quotaSnapshot(from response: HTTPURLResponse) -> QuotaUsageSnapshot? {
        func headerDouble(_ name: String) -> Double? {
            response.value(forHTTPHeaderField: name).flatMap(Double.init)
        }
        func headerDate(_ name: String) -> Date? {
            response.value(forHTTPHeaderField: name).flatMap {
                Self.resetDateFormatter.date(from: $0)
            }
        }

        guard
            let requestLimit = headerDouble("anthropic-ratelimit-requests-limit"), requestLimit > 0,
            let requestsRemaining = headerDouble("anthropic-ratelimit-requests-remaining")
        else {
            return nil
        }

        let requestsUsedPercent = min(100, max(0, (1 - requestsRemaining / requestLimit) * 100))

        // Prefer the input-token window for the second ring; fall back to the
        // combined tokens window.
        var tokensUsedPercent: Double?
        var tokensReset: Date?
        for prefix in ["anthropic-ratelimit-input-tokens", "anthropic-ratelimit-tokens"] {
            if
                let limit = headerDouble("\(prefix)-limit"), limit > 0,
                let remaining = headerDouble("\(prefix)-remaining") {
                tokensUsedPercent = min(100, max(0, (1 - remaining / limit) * 100))
                tokensReset = headerDate("\(prefix)-reset")
                break
            }
        }

        return QuotaUsageSnapshot(
            weeklyUsedPercent: tokensUsedPercent ?? requestsUsedPercent,
            sessionUsedPercent: requestsUsedPercent,
            sessionResetAt: headerDate("anthropic-ratelimit-requests-reset"),
            weeklyResetAt: tokensReset
        )
    }
}

/// Gemini API keys can be verified, but Google exposes no usage or rate-limit
/// data for them - the outcome carries a clear message instead of quota.
public struct GeminiAPIKeyClient {
    private let modelsURL: URL
    private let session: URLSession

    public init(
        modelsURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
        session: URLSession = .shared
    ) {
        self.modelsURL = modelsURL
        self.session = session
    }

    public func checkKey(apiKey: String) async -> APIRateLimitOutcome {
        var request = URLRequest(url: modelsURL)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        guard
            let (_, response) = try? await session.data(for: request),
            let httpResponse = response as? HTTPURLResponse
        else {
            return APIRateLimitOutcome(
                failureMessage: "Gemini API request failed. Check your connection."
            )
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            return APIRateLimitOutcome(
                failureMessage: "Google rejected the API key (HTTP \(httpResponse.statusCode)).",
                unauthorized: httpResponse.statusCode == 401 || httpResponse.statusCode == 403
            )
        }

        return APIRateLimitOutcome(
            failureMessage: "Gemini key is valid. Google does not expose live rate-limit usage for API keys yet."
        )
    }
}

public struct QuotaRefreshResult {
    public var status: QuotaRefreshStatus
    public var message: String?
    public var quota: QuotaUsageSnapshot?
    public var accountEmail: String?
    public var providerAccountID: String?
    /// When true and `quota` is nil, the account keeps its current snapshot
    /// instead of clearing it (used when a probe is intentionally skipped).
    public var preservesExistingQuota: Bool

    public init(
        status: QuotaRefreshStatus,
        message: String?,
        quota: QuotaUsageSnapshot?,
        accountEmail: String? = nil,
        providerAccountID: String? = nil,
        preservesExistingQuota: Bool = false
    ) {
        self.status = status
        self.message = message
        self.quota = quota
        self.accountEmail = accountEmail
        self.providerAccountID = providerAccountID
        self.preservesExistingQuota = preservesExistingQuota
    }
}

public struct QuotaUsageSnapshot: Codable, Hashable {
    public var weeklyLimitMinutes: Int?
    public var usedMinutes: Int?
    public var sessionLimitMinutes: Int?
    public var sessionUsedMinutes: Int?
    public var weeklyUsedPercent: Double?
    public var sessionUsedPercent: Double?
    public var sessionResetAt: Date?
    public var weeklyResetAt: Date?
    public var resetWeekday: Int?
    public var resetHour: Int?
    public var resetMinute: Int?

    public init(
        weeklyLimitMinutes: Int? = nil,
        usedMinutes: Int? = nil,
        sessionLimitMinutes: Int? = nil,
        sessionUsedMinutes: Int? = nil,
        weeklyUsedPercent: Double? = nil,
        sessionUsedPercent: Double? = nil,
        sessionResetAt: Date? = nil,
        weeklyResetAt: Date? = nil,
        resetWeekday: Int? = nil,
        resetHour: Int? = nil,
        resetMinute: Int? = nil
    ) {
        self.weeklyLimitMinutes = weeklyLimitMinutes
        self.usedMinutes = usedMinutes
        self.sessionLimitMinutes = sessionLimitMinutes
        self.sessionUsedMinutes = sessionUsedMinutes
        self.weeklyUsedPercent = weeklyUsedPercent
        self.sessionUsedPercent = sessionUsedPercent
        self.sessionResetAt = sessionResetAt
        self.weeklyResetAt = weeklyResetAt
        self.resetWeekday = resetWeekday
        self.resetHour = resetHour
        self.resetMinute = resetMinute
    }
}

public struct CodexUsageFetchResult: Hashable {
    public var quota: QuotaUsageSnapshot
    public var email: String?
    public var accountID: String?

    public init(quota: QuotaUsageSnapshot, email: String? = nil, accountID: String? = nil) {
        self.quota = quota
        self.email = email
        self.accountID = accountID
    }
}

public enum CodexUsageFetchOutcome: Hashable {
    case success(CodexUsageFetchResult)
    case unavailable(String, accountEmail: String?, accountID: String? = nil, unauthorized: Bool = false)

    public var isUnauthorized: Bool {
        if case .unavailable(_, _, _, let unauthorized) = self {
            return unauthorized
        }

        return false
    }

    public var result: CodexUsageFetchResult? {
        switch self {
        case .success(let result):
            return result
        case .unavailable:
            return nil
        }
    }

    public var accountEmail: String? {
        switch self {
        case .success(let result):
            return result.email
        case .unavailable(_, let accountEmail, _, _):
            return accountEmail
        }
    }

    public var accountID: String? {
        switch self {
        case .success(let result):
            return result.accountID
        case .unavailable(_, _, let accountID, _):
            return accountID
        }
    }

    public var message: String {
        switch self {
        case .success:
            return "Loaded live Codex usage."
        case .unavailable(let message, _, _, _):
            return message
        }
    }
}

private enum CodexUsageFailureReason {
    case unauthorized
    case other
}

private enum CodexUsageRequestOutcome {
    case success(CodexUsageFetchResult)
    case unavailable(String, accountEmail: String?, accountID: String?, failureReason: CodexUsageFailureReason)

    var failureReason: CodexUsageFailureReason? {
        switch self {
        case .success:
            return nil
        case .unavailable(_, _, _, let failureReason):
            return failureReason
        }
    }

    var publicOutcome: CodexUsageFetchOutcome {
        switch self {
        case .success(let result):
            return .success(result)
        case .unavailable(let message, let accountEmail, let accountID, let failureReason):
            return .unavailable(
                message,
                accountEmail: accountEmail,
                accountID: accountID,
                unauthorized: failureReason == .unauthorized
            )
        }
    }

    static func failure(
        _ message: String,
        accountEmail: String?,
        accountID: String?,
        failureReason: CodexUsageFailureReason = .other
    ) -> CodexUsageRequestOutcome {
        .unavailable(message, accountEmail: accountEmail, accountID: accountID, failureReason: failureReason)
    }
}

public struct CodexUsageClient {
    private let session: URLSession
    private let usageURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar

    public init(
        session: URLSession = .shared,
        usageURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.session = session
        self.usageURL = usageURL
        self.fileManager = fileManager
        self.calendar = calendar
    }

    public func fetchUsage(for account: QuotaAccount) async -> CodexUsageFetchOutcome {
        let profilePath = QuotaFormatting.expandedHomePath(account.resolvedProviderProfilePath)
        let auth = CodexProfileAuthStore.tokens(profilePath: profilePath, fileManager: fileManager)
        guard let token = auth?.accessToken, !token.isEmpty else {
            guard let refreshedAuth = await refreshAuthIfPossible(auth, profilePath: profilePath) else {
                return CodexUsageRequestOutcome.failure(
                    "Codex is connected, but Brim could not find this profile's auth token.",
                    accountEmail: nil,
                    accountID: auth?.accountID
                ).publicOutcome
            }

            return await fetchUsage(for: account, auth: refreshedAuth, didRefreshToken: true).publicOutcome
        }

        let outcome = await fetchUsage(for: account, auth: auth, didRefreshToken: false)
        if case .unauthorized = outcome.failureReason {
            if let refreshedAuth = await refreshAuthIfPossible(auth, profilePath: profilePath) {
                return await fetchUsage(for: account, auth: refreshedAuth, didRefreshToken: true).publicOutcome
            }

            return CodexUsageRequestOutcome.failure(
                "Codex session expired. Sign in with Codex again.",
                accountEmail: nil,
                accountID: auth?.accountID,
                failureReason: .unauthorized
            ).publicOutcome
        }

        return outcome.publicOutcome
    }

    private func fetchUsage(
        for account: QuotaAccount,
        auth: CodexAuthTokens?,
        didRefreshToken: Bool
    ) async -> CodexUsageRequestOutcome {
        guard let token = auth?.accessToken, !token.isEmpty else {
            return .failure(
                "Codex is connected, but Brim could not find this profile's auth token.",
                accountEmail: nil,
                accountID: auth?.accountID
            )
        }

        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
            else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let message = didRefreshToken && statusCode == 401
                    ? "Codex session expired. Sign in with Codex again."
                    : "Codex usage request failed with HTTP \(statusCode)."
                return .failure(
                    message,
                    accountEmail: nil,
                    accountID: auth?.accountID,
                    failureReason: statusCode == 401 ? .unauthorized : .other
                )
            }

            let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            guard let quota = quotaSnapshot(from: usage) else {
                return .failure(
                    "Codex usage response did not include rate-limit data Brim understands.",
                    accountEmail: usage.email,
                    accountID: auth?.accountID
                )
            }

            return .success(CodexUsageFetchResult(quota: quota, email: usage.email, accountID: auth?.accountID))
        } catch {
            return .failure("Codex usage request failed: \(error.localizedDescription)", accountEmail: nil, accountID: auth?.accountID)
        }
    }

    private func refreshAuthIfPossible(_ auth: CodexAuthTokens?, profilePath: String) async -> CodexAuthTokens? {
        guard let auth, let refreshToken = auth.refreshToken, !refreshToken.isEmpty else {
            return nil
        }

        var request = URLRequest(url: CodexOAuthContract.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = CodexOAuthContract.formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": CodexOAuthContract.clientID
        ])

        do {
            let (data, response) = try await session.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode
            else {
                return nil
            }

            guard let refreshed = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
                .codexTokens?
                .mergingMissingValues(from: auth)
            else {
                return nil
            }

            try CodexProfileAuthStore.save(tokens: refreshed, profilePath: profilePath, fileManager: fileManager)
            return refreshed
        } catch {
            return nil
        }
    }

    private func quotaSnapshot(from usage: CodexUsageResponse) -> QuotaUsageSnapshot? {
        guard
            let rateLimit = usage.rateLimit,
            let primary = rateLimit.primaryWindow,
            let secondary = rateLimit.secondaryWindow,
            primary.normalizedUsedPercent != nil,
            secondary.normalizedUsedPercent != nil
        else {
            return nil
        }

        let sessionLimitMinutes = primary.limitMinutes
        let weeklyLimitMinutes = secondary.limitMinutes

        guard sessionLimitMinutes > 0, weeklyLimitMinutes > 0 else {
            return nil
        }

        let reference = Date()
        let sessionReset = primary.resetDate(from: reference)
        let weeklyReset = secondary.resetDate(from: reference)
        let resetComponents = resetComponents(from: weeklyReset)

        return QuotaUsageSnapshot(
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: secondary.usedMinutes(limitMinutes: weeklyLimitMinutes),
            sessionLimitMinutes: sessionLimitMinutes,
            sessionUsedMinutes: primary.usedMinutes(limitMinutes: sessionLimitMinutes),
            weeklyUsedPercent: secondary.normalizedUsedPercent,
            sessionUsedPercent: primary.normalizedUsedPercent,
            sessionResetAt: sessionReset,
            weeklyResetAt: weeklyReset,
            resetWeekday: resetComponents.weekday,
            resetHour: resetComponents.hour,
            resetMinute: resetComponents.minute
        )
    }

    private func resetComponents(from date: Date?) -> DateComponents {
        guard let date else {
            return DateComponents()
        }

        return calendar.dateComponents([.weekday, .hour, .minute], from: date)
    }
}

enum CodexOAuthContract {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authBaseURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    /// The only loopback port registered for this client's redirect URI; any other port is
    /// rejected by the authorization server with `authorize_hydra_invalid_request`.
    static let redirectPort: UInt16 = 1455
    static let scope = "openid profile email offline_access api.connectors.read api.connectors.invoke"

    static func authorizationURL(
        redirectURI: String,
        codeChallenge: String,
        state: String
    ) -> URL? {
        let queryFields = [
            ("response_type", "code"),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("scope", scope),
            ("code_challenge", codeChallenge),
            ("code_challenge_method", "S256"),
            ("id_token_add_organizations", "true"),
            ("codex_cli_simplified_flow", "true"),
            ("state", state),
            ("originator", "Codex Desktop")
        ]
        var components = URLComponents(url: authBaseURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedQuery = percentEncodedQuery(queryFields)
        return components?.url
    }

    static func formBody(_ fields: [String: String]) -> Data {
        Data(percentEncodedQuery(fields.map { ($0.key, $0.value) }).utf8)
    }

    static func percentEncodedQuery(_ fields: [(String, String)]) -> String {
        fields
            .map { "\(percentEncode($0.0))=\(percentEncode($0.1))" }
            .joined(separator: "&")
    }

    private static func percentEncode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}

struct CodexTokenResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var accountID: String?
    var tokens: CodexAuthTokens?

    var codexTokens: CodexAuthTokens? {
        if let tokens {
            return tokens.hasUsableToken ? tokens : nil
        }

        let directTokens = CodexAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountID: accountID
        )
        return directTokens.hasUsableToken ? directTokens : nil
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
        case tokens
    }
}

enum CodexProfileAuthStore {
    static func hasAccessToken(profilePath: String, fileManager: FileManager = .default) -> Bool {
        guard let accessToken = tokens(profilePath: profilePath, fileManager: fileManager)?.accessToken else {
            return false
        }

        return !accessToken.isEmpty
    }

    static func hasUsableTokens(profilePath: String, fileManager: FileManager = .default) -> Bool {
        tokens(profilePath: profilePath, fileManager: fileManager)?.hasUsableToken == true
    }

    static func tokens(profilePath: String, fileManager: FileManager = .default) -> CodexAuthTokens? {
        let authURL = authURL(profilePath: profilePath)
        guard
            fileManager.fileExists(atPath: authURL.path),
            let data = try? Data(contentsOf: authURL),
            let auth = try? JSONDecoder().decode(CodexAuthFile.self, from: data)
        else {
            return nil
        }

        return auth.tokens
    }

    static func removeAuth(profilePath: String, fileManager: FileManager = .default) throws {
        let authURL = authURL(profilePath: profilePath)
        guard fileManager.fileExists(atPath: authURL.path) else {
            return
        }

        try fileManager.removeItem(at: authURL)
    }

    static func save(tokens: CodexAuthTokens, profilePath: String, fileManager: FileManager = .default) throws {
        let authURL = authURL(profilePath: profilePath)
        try fileManager.createDirectory(at: authURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let auth = CodexAuthFile(
            openAIAPIKey: nil,
            authMode: "chatgpt",
            lastRefresh: ISO8601DateFormatter.brimCodex.string(from: Date()),
            tokens: tokens
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        try data.write(to: authURL, options: [.atomic])
    }

    private static func authURL(profilePath: String) -> URL {
        URL(fileURLWithPath: profilePath, isDirectory: true).appendingPathComponent("auth.json")
    }
}

struct CodexAuthFile: Codable {
    var openAIAPIKey: String?
    var authMode: String?
    var lastRefresh: String?
    var tokens: CodexAuthTokens?

    init(
        openAIAPIKey: String? = nil,
        authMode: String? = nil,
        lastRefresh: String? = nil,
        tokens: CodexAuthTokens? = nil
    ) {
        self.openAIAPIKey = openAIAPIKey
        self.authMode = authMode
        self.lastRefresh = lastRefresh
        self.tokens = tokens
    }

    private enum CodingKeys: String, CodingKey {
        case openAIAPIKey = "OPENAI_API_KEY"
        case authMode = "auth_mode"
        case lastRefresh = "last_refresh"
        case tokens
    }
}

struct CodexAuthTokens: Codable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var accountID: String?

    var hasAccessToken: Bool {
        guard let accessToken else {
            return false
        }

        return !accessToken.isEmpty
    }

    var hasRefreshToken: Bool {
        guard let refreshToken else {
            return false
        }

        return !refreshToken.isEmpty
    }

    var hasUsableToken: Bool {
        hasAccessToken || hasRefreshToken
    }

    func mergingMissingValues(from olderTokens: CodexAuthTokens) -> CodexAuthTokens {
        CodexAuthTokens(
            accessToken: accessToken ?? olderTokens.accessToken,
            refreshToken: refreshToken ?? olderTokens.refreshToken,
            idToken: idToken ?? olderTokens.idToken,
            accountID: accountID ?? olderTokens.accountID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

private extension ISO8601DateFormatter {
    static let brimCodex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private struct CodexUsageResponse: Decodable {
    var email: String?
    var rateLimit: CodexRateLimit?

    private enum CodingKeys: String, CodingKey {
        case email
        case accountEmail = "account_email"
        case rateLimit = "rate_limit"
        case rateLimitCamel = "rateLimit"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        email = try container.decodeIfPresent(String.self, forKey: .email)
            ?? container.decodeIfPresent(String.self, forKey: .accountEmail)
        rateLimit = try container.decodeIfPresent(CodexRateLimit.self, forKey: .rateLimit)
            ?? container.decodeIfPresent(CodexRateLimit.self, forKey: .rateLimitCamel)
    }
}

private struct CodexRateLimit: Decodable {
    var primaryWindow: CodexRateLimitWindow?
    var secondaryWindow: CodexRateLimitWindow?

    private enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case primaryWindowCamel = "primaryWindow"
        case session
        case sessionWindow = "session_window"
        case fiveHourWindow = "five_hour_window"
        case secondaryWindow = "secondary_window"
        case secondaryWindowCamel = "secondaryWindow"
        case weekly
        case weeklyWindow = "weekly_window"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryWindow = try container.decodeIfPresent(CodexUsageWindow.self, forKey: .primaryWindow)?.rateLimitWindow
            ?? container.decodeIfPresent(CodexUsageWindow.self, forKey: .primaryWindowCamel)?.rateLimitWindow
            ?? container.decodeIfPresent(CodexUsageWindow.self, forKey: .session)?.rateLimitWindow
            ?? container.decodeIfPresent(CodexUsageWindow.self, forKey: .sessionWindow)?.rateLimitWindow
            ?? container.decodeIfPresent(CodexUsageWindow.self, forKey: .fiveHourWindow)?.rateLimitWindow
        secondaryWindow = try container.decodeIfPresent(CodexUsageWindow.self, forKey: .secondaryWindow)?.rateLimitWindow
            ?? container.decodeIfPresent(CodexUsageWindow.self, forKey: .secondaryWindowCamel)?.rateLimitWindow
            ?? container.decodeIfPresent(CodexUsageWindow.self, forKey: .weekly)?.rateLimitWindow
            ?? container.decodeIfPresent(CodexUsageWindow.self, forKey: .weeklyWindow)?.rateLimitWindow
    }
}

private struct CodexRateLimitWindow: Decodable {
    var usedPercent: Double?
    var limitWindowSeconds: Double?
    var resetAt: TimeInterval?
    var resetsInSeconds: Double?

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(usedPercent: Double?, limitWindowSeconds: Double?, resetAt: TimeInterval?, resetsInSeconds: Double? = nil) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAt = resetAt
        self.resetsInSeconds = resetsInSeconds
    }

    init(from decoder: Decoder) throws {
        self = try CodexUsageWindow(from: decoder).rateLimitWindow
    }

    var limitMinutes: Int {
        guard let limitWindowSeconds else {
            return 0
        }

        return max(1, Int(round(limitWindowSeconds / 60)))
    }

    func usedMinutes(limitMinutes: Int) -> Int {
        let usedFraction = (normalizedUsedPercent ?? 0) / 100
        return min(limitMinutes, max(0, Int(round(Double(limitMinutes) * usedFraction))))
    }

    var normalizedUsedPercent: Double? {
        usedPercent.map { max(0, min(100, $0)) }
    }

    /// Absolute reset time, anchored to the moment the response was fetched.
    /// The API usually reports a relative `resets_in_seconds`; converting it once
    /// here keeps the displayed time stable across refreshes.
    func resetDate(from reference: Date) -> Date? {
        if let resetAt {
            return Date(timeIntervalSince1970: resetAt)
        }

        return resetsInSeconds.map { reference.addingTimeInterval($0) }
    }
}

private struct CodexUsageWindow: Decodable {
    var rateLimitWindow: CodexRateLimitWindow

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case usedPercentCamel = "usedPercent"
        case remainingPercent = "remaining_percent"
        case remainingPercentCamel = "remainingPercent"
        case limitWindowSeconds = "limit_window_seconds"
        case limitWindowSecondsCamel = "limitWindowSeconds"
        case windowSeconds = "window_seconds"
        case windowSecondsCamel = "windowSeconds"
        case limitSeconds = "limit_seconds"
        case limitSecondsCamel = "limitSeconds"
        case resetAt = "reset_at"
        case resetAtCamel = "resetAt"
        case resetsAt = "resets_at"
        case resetsAtCamel = "resetsAt"
        case resetsInSeconds = "resets_in_seconds"
        case resetsInSecondsCamel = "resetsInSeconds"
        case resetInSeconds = "reset_in_seconds"
        case resetInSecondsCamel = "resetInSeconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUsedPercent = try Self.decodeDouble(
            from: container,
            keys: [.usedPercent, .usedPercentCamel]
        ).map(Self.percentValue)
        let decodedRemainingPercent = try Self.decodeDouble(
            from: container,
            keys: [.remainingPercent, .remainingPercentCamel]
        ).map(Self.percentValue)
        let limitWindowSeconds = try Self.decodeDouble(
            from: container,
            keys: [.limitWindowSeconds, .limitWindowSecondsCamel, .windowSeconds, .windowSecondsCamel, .limitSeconds, .limitSecondsCamel]
        )
        let resetAt = try Self.decodeDouble(
            from: container,
            keys: [.resetAt, .resetAtCamel, .resetsAt, .resetsAtCamel]
        ).map(Self.timestampSeconds)
        let resetsInSeconds = try Self.decodeDouble(
            from: container,
            keys: [.resetsInSeconds, .resetsInSecondsCamel, .resetInSeconds, .resetInSecondsCamel]
        )

        rateLimitWindow = CodexRateLimitWindow(
            usedPercent: decodedUsedPercent ?? decodedRemainingPercent.map { 100 - $0 },
            limitWindowSeconds: limitWindowSeconds,
            resetAt: resetAt,
            resetsInSeconds: resetsInSeconds
        )
    }

    private static func decodeDouble(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) throws -> Double? {
        for key in keys {
            if let double = try? container.decodeIfPresent(Double.self, forKey: key) {
                return double
            }
            if let int = try? container.decodeIfPresent(Int.self, forKey: key) {
                return Double(int)
            }
            if let string = try? container.decodeIfPresent(String.self, forKey: key),
               let double = Double(string) {
                return double
            }
        }
        return nil
    }

    private static func percentValue(_ value: Double) -> Double {
        let percent = value <= 1 ? value * 100 : value
        return max(0, min(100, percent))
    }

    private static func timestampSeconds(_ value: Double) -> TimeInterval {
        value > 100_000_000_000 ? value / 1_000 : value
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
