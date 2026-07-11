import Combine
import Foundation

public final class QuotaStore: ObservableObject {
    private let repository: QuotaRepository
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
        self.repository = repository
        refreshService = QuotaRefreshService()
        let result = repository.load()
        let migration = ProviderProfileStorage.migrateOwnedProfiles(in: result.state.accounts)
        state = QuotaState(
            accounts: migration.accounts,
            selectedAccountID: result.state.selectedAccountID
        )
        storageStatus = result.status

        if result.status == .ready || result.status == .firstRun {
            persist()
        }
    }

    public init(
        repository: QuotaRepository,
        refreshService: QuotaRefreshService = QuotaRefreshService()
    ) {
        self.repository = repository
        self.refreshService = refreshService
        let result = repository.load()
        let migration = ProviderProfileStorage.migrateOwnedProfiles(in: result.state.accounts)
        state = QuotaState(
            accounts: migration.accounts,
            selectedAccountID: result.state.selectedAccountID
        )
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
        let importedState = try QuotaAccountsTransferPayload.importedState(from: data)
        let importStorageStatus = repository.save(importedState)
        storageStatus = importStorageStatus
        guard importStorageStatus == .ready else {
            throw QuotaStoreError.importPersistenceFailed
        }

        state = importedState
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
        let connectedAccounts = accounts.filter {
            $0.connectionKind != .manual && $0.provider.performsAutomaticRefresh
        }
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
        persist()

        for requestedAccount in accountsToRefresh {
            let result = await refreshService.refresh(requestedAccount)
            guard var currentAccount = accounts.first(where: { $0.id == requestedAccount.id }) else {
                continue
            }
            guard
                currentAccount.connectionKind == requestedAccount.connectionKind,
                currentAccount.resolvedProviderProfilePath == requestedAccount.resolvedProviderProfilePath,
                currentAccount.lastRefreshAttemptAt == now
            else {
                // A user action changed this account while the request was in flight.
                // Its newer state owns the account, so this result is obsolete.
                continue
            }

            if
                currentAccount.connectionKind == .login,
                let identityConflict = identityConflictMessage(for: currentAccount, result: result)
            {
                do {
                    try disconnectAccountAfterIdentityConflict(&currentAccount, message: identityConflict)
                } catch {
                    currentAccount.refreshStatus = .refreshFailed
                    currentAccount.refreshMessage = "Brim detected a conflicting login but could not remove its local credentials: \(error.localizedDescription)"
                }
                state.updateAccount(currentAccount)
                continue
            }

            currentAccount.refreshStatus = result.status
            currentAccount.refreshMessage = result.message

            if let accountEmail = result.accountEmail {
                currentAccount.accountEmail = accountEmail
            }
            if let providerAccountID = result.providerAccountID {
                currentAccount.providerAccountID = providerAccountID
            }

            if result.status == .ready, !result.preservesExistingQuota {
                currentAccount.lastSuccessfulRefreshAt = Date()
            }

            if let quota = result.quota {
                currentAccount.weeklyLimitMinutes = quota.weeklyLimitMinutes ?? currentAccount.weeklyLimitMinutes
                currentAccount.usedMinutes = quota.usedMinutes ?? currentAccount.usedMinutes
                currentAccount.sessionLimitMinutes = quota.sessionLimitMinutes ?? currentAccount.sessionLimitMinutes
                currentAccount.sessionUsedMinutes = quota.sessionUsedMinutes ?? currentAccount.sessionUsedMinutes
                currentAccount.weeklyUsedPercent = quota.weeklyUsedPercent
                currentAccount.sessionUsedPercent = quota.sessionUsedPercent
                currentAccount.sessionResetAt = quota.sessionResetAt
                currentAccount.weeklyResetAt = quota.weeklyResetAt
                currentAccount.resetWeekday = quota.resetWeekday ?? currentAccount.resetWeekday
                currentAccount.resetHour = quota.resetHour ?? currentAccount.resetHour
                currentAccount.resetMinute = quota.resetMinute ?? currentAccount.resetMinute
                currentAccount.hasUsageSnapshot = true
            } else if currentAccount.connectionKind != .manual, !result.preservesExistingQuota {
                currentAccount.hasUsageSnapshot = false
                currentAccount.weeklyUsedPercent = nil
                currentAccount.sessionUsedPercent = nil
                currentAccount.sessionResetAt = nil
                currentAccount.weeklyResetAt = nil
            }

            state.updateAccount(currentAccount)
        }
        persist()
    }

    private func identityConflictMessage(
        for account: QuotaAccount,
        result: QuotaRefreshResult
    ) -> String? {
        let currentEmail = account.normalizedAccountEmail?.lowercased()
        let refreshedEmail = normalizedIdentityValue(result.accountEmail)?.lowercased()
        let currentProviderAccountID = normalizedIdentityValue(account.providerAccountID)
        let refreshedProviderAccountID = normalizedIdentityValue(result.providerAccountID)

        if let currentEmail, let refreshedEmail, currentEmail != refreshedEmail {
            return "This login belongs to a different user than the one connected to this Brim account. Log out before switching identities."
        }
        if
            let currentProviderAccountID,
            let refreshedProviderAccountID,
            currentProviderAccountID != refreshedProviderAccountID
        {
            return "This login belongs to a different ChatGPT workspace. Log out before switching workspaces."
        }

        guard refreshedEmail != nil || refreshedProviderAccountID != nil else {
            return nil
        }

        let duplicatesAnotherAccount = accounts.contains { otherAccount in
            guard otherAccount.id != account.id, otherAccount.provider == account.provider else {
                return false
            }
            let otherEmail = otherAccount.normalizedAccountEmail?.lowercased()
            let otherProviderAccountID = normalizedIdentityValue(otherAccount.providerAccountID)

            if let refreshedProviderAccountID, let otherProviderAccountID {
                return otherProviderAccountID == refreshedProviderAccountID
            }
            if let refreshedEmail {
                return otherEmail == refreshedEmail
            }
            return otherProviderAccountID == refreshedProviderAccountID
        }

        return duplicatesAnotherAccount
            ? "This login is already connected to another Brim account. Each account must use a distinct login profile."
            : nil
    }

    private func disconnectAccountAfterIdentityConflict(
        _ account: inout QuotaAccount,
        message: String
    ) throws {
        if account.connectionKind == .login {
            try ProviderProfileStorage.removeOwnedAuthIfPresent(for: account)
        }
        account = account.disconnectedProviderAccount(message: message)
    }

    private func normalizedIdentityValue(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func persist() {
        storageStatus = repository.save(state)
    }
}

public enum QuotaStoreError: LocalizedError {
    case importPersistenceFailed

    public var errorDescription: String? {
        switch self {
        case .importPersistenceFailed:
            return "Brim could not save the imported accounts. Existing accounts and credentials were left unchanged."
        }
    }
}

public enum APITokenCredentialReadResult: Equatable {
    case token(String)
    case missing
    case inaccessible(String)
}

public struct QuotaRefreshService {
    public var apiTokenProvider: (String) -> APITokenCredentialReadResult
    public var usageFetcher: (QuotaAccount) async -> CodexUsageFetchOutcome
    public var apiLimitsFetcher: (QuotaAccount, String) async -> APIRateLimitOutcome

    public init(
        apiTokenProvider: @escaping (String) -> APITokenCredentialReadResult = { _ in .missing },
        usageFetcher: @escaping (QuotaAccount) async -> CodexUsageFetchOutcome = { account in
            await CodexUsageClient().fetchUsage(for: account)
        },
        apiLimitsFetcher: @escaping (QuotaAccount, String) async -> APIRateLimitOutcome = { account, apiKey in
            switch account.provider {
            case .codex, .chatgpt, .claude:
                return APIRateLimitOutcome(
                    failureMessage: "This provider does not use an API key in Brim.",
                    failureKind: .unsupportedConnection
                )
            case .gemini:
                return await GeminiAPIKeyClient().checkKey(apiKey: apiKey)
            }
        }
    ) {
        self.apiTokenProvider = apiTokenProvider
        self.usageFetcher = usageFetcher
        self.apiLimitsFetcher = apiLimitsFetcher
    }

    public func refresh(_ account: QuotaAccount) async -> QuotaRefreshResult {
        switch account.connectionKind {
        case .manual:
            return QuotaRefreshResult(status: .manual, message: "Manual values are used.", quota: nil)
        case .apiToken:
            guard account.provider.supports(.apiToken) else {
                return QuotaRefreshResult(
                    status: .refreshFailed,
                    message: "API keys cannot read \(account.provider.displayName) subscription usage. Switch this account to Login.",
                    quota: nil
                )
            }
            guard let credentialID = account.credentialID else {
                return QuotaRefreshResult(
                    status: .notConnected,
                    message: "Add an API token before automatic quota refresh can run.",
                    quota: nil
                )
            }

            switch apiTokenProvider(credentialID) {
            case .missing:
                return QuotaRefreshResult(
                    status: .notConnected,
                    message: "The saved API token is missing from local credential storage. Save it again.",
                    quota: nil
                )
            case .inaccessible(let message):
                return QuotaRefreshResult(status: .refreshFailed, message: message, quota: nil)
            case .token(let apiKey):
                return await refreshAPITokenAccount(account, apiKey: apiKey)
            }
        case .login:
            switch account.provider {
            case .codex:
                return await refreshCodexLogin(account)
            case .chatgpt:
                return QuotaRefreshResult(
                    status: .dashboardOnly,
                    message: "ChatGPT keeps ordinary chat limits in ChatGPT. Open its dashboard to verify usage.",
                    quota: nil
                )
            case .claude:
                return QuotaRefreshResult(
                    status: .dashboardOnly,
                    message: "Claude keeps subscription limits in Claude. Open its dashboard to verify usage.",
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

    private func refreshAPITokenAccount(_ account: QuotaAccount, apiKey: String) async -> QuotaRefreshResult {
        let outcome = await apiLimitsFetcher(account, apiKey)
        if let quota = outcome.quota {
            return QuotaRefreshResult(
                status: .ready,
                message: "Loaded \(account.provider.displayName) API rate limits (per-minute windows).",
                quota: quota
            )
        }

        let message = outcome.failureMessage ?? "\(account.provider.displayName) API rate limits are unavailable right now."
        switch outcome.failureKind {
        case .unauthorized:
            return QuotaRefreshResult(status: .notConnected, message: message, quota: nil)
        case .validWithoutUsage:
            return QuotaRefreshResult(status: .ready, message: message, quota: nil)
        case .transient, .unsupportedConnection, nil:
            return QuotaRefreshResult(
                status: .refreshFailed,
                message: message,
                quota: nil,
                preservesExistingQuota: account.hasUsageSnapshot
            )
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
        if usageOutcome.isTransientFailure {
            return QuotaRefreshResult(
                status: .refreshFailed,
                message: usageOutcome.message,
                quota: nil,
                accountEmail: usageOutcome.accountEmail,
                providerAccountID: usageOutcome.accountID,
                preservesExistingQuota: true
            )
        }

        let usage = usageOutcome.result
        if let liveQuota = usage?.quota {
            return QuotaRefreshResult(
                status: .ready,
                message: "Loaded live Codex usage.",
                quota: liveQuota,
                accountEmail: usageOutcome.accountEmail,
                providerAccountID: usageOutcome.accountID
            )
        }

        if let localQuota = readLocalQuotaSnapshot(for: account) {
            return QuotaRefreshResult(
                status: .ready,
                message: "Loaded quota snapshot from local profile.",
                quota: localQuota,
                accountEmail: usageOutcome.accountEmail,
                providerAccountID: usageOutcome.accountID
            )
        }

        return QuotaRefreshResult(
            status: .refreshFailed,
            message: usageOutcome.message,
            quota: nil,
            accountEmail: usageOutcome.accountEmail,
            providerAccountID: usageOutcome.accountID,
            preservesExistingQuota: account.hasUsageSnapshot
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

public enum APIRateLimitFailureKind: Equatable {
    case unauthorized
    case transient
    case validWithoutUsage
    case unsupportedConnection
}

public struct APIRateLimitOutcome {
    public var quota: QuotaUsageSnapshot?
    public var failureMessage: String?
    public var failureKind: APIRateLimitFailureKind?

    public init(
        quota: QuotaUsageSnapshot? = nil,
        failureMessage: String? = nil,
        failureKind: APIRateLimitFailureKind? = nil
    ) {
        self.quota = quota
        self.failureMessage = failureMessage
        self.failureKind = failureKind
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
                failureMessage: "Gemini API request failed. Check your connection.",
                failureKind: .transient
            )
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            return APIRateLimitOutcome(
                failureMessage: "Google rejected the API key (HTTP \(httpResponse.statusCode)).",
                failureKind: httpResponse.statusCode == 401 || httpResponse.statusCode == 403
                    ? .unauthorized
                    : .transient
            )
        }

        return APIRateLimitOutcome(
            failureMessage: "Gemini key is valid. Google does not expose live rate-limit usage for API keys yet.",
            failureKind: .validWithoutUsage
        )
    }
}

private enum CodexUsageFailureReason {
    case unauthorized
    case transient
    case other
}

private enum CodexAuthRefreshOutcome {
    case refreshed(CodexAuthTokens)
    case rejected
    case transient(String)
}

private struct CodexTokenRefreshErrorResponse: Decodable {
    var error: String?
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
            let failureKind: CodexUsageFailureKind
            switch failureReason {
            case .unauthorized:
                failureKind = .unauthorized
            case .transient:
                failureKind = .transient
            case .other:
                failureKind = .unavailable
            }
            return .unavailable(
                message,
                accountEmail: accountEmail,
                accountID: accountID,
                failureKind: failureKind
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
    private let tokenURL: URL
    private let fileManager: FileManager
    private let calendar: Calendar

    public init(
        session: URLSession = .shared,
        usageURL: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        tokenURL: URL = URL(string: "https://auth.openai.com/oauth/token")!,
        fileManager: FileManager = .default,
        calendar: Calendar = .current
    ) {
        self.session = session
        self.usageURL = usageURL
        self.tokenURL = tokenURL
        self.fileManager = fileManager
        self.calendar = calendar
    }

    public func fetchUsage(for account: QuotaAccount) async -> CodexUsageFetchOutcome {
        let profilePath = QuotaFormatting.expandedHomePath(account.resolvedProviderProfilePath)
        let auth = CodexProfileAuthStore.tokens(profilePath: profilePath, fileManager: fileManager)
        guard let token = auth?.accessToken, !token.isEmpty else {
            switch await refreshAuth(auth, profilePath: profilePath) {
            case .refreshed(let refreshedAuth):
                return await fetchUsage(for: account, auth: refreshedAuth, didRefreshToken: true).publicOutcome
            case .rejected:
                return CodexUsageRequestOutcome.failure(
                    "Codex session expired. Sign in with Codex again.",
                    accountEmail: nil,
                    accountID: auth?.accountID,
                    failureReason: .unauthorized
                ).publicOutcome
            case .transient(let message):
                return CodexUsageRequestOutcome.failure(
                    message,
                    accountEmail: nil,
                    accountID: auth?.accountID,
                    failureReason: .transient
                ).publicOutcome
            }
        }

        let outcome = await fetchUsage(for: account, auth: auth, didRefreshToken: false)
        if case .unauthorized = outcome.failureReason {
            switch await refreshAuth(auth, profilePath: profilePath) {
            case .refreshed(let refreshedAuth):
                return await fetchUsage(for: account, auth: refreshedAuth, didRefreshToken: true).publicOutcome
            case .rejected:
                return CodexUsageRequestOutcome.failure(
                    "Codex session expired. Sign in with Codex again.",
                    accountEmail: nil,
                    accountID: auth?.accountID,
                    failureReason: .unauthorized
                ).publicOutcome
            case .transient(let message):
                return CodexUsageRequestOutcome.failure(
                    message,
                    accountEmail: nil,
                    accountID: auth?.accountID,
                    failureReason: .transient
                ).publicOutcome
            }
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
        if let accountID = auth?.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }
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
                    failureReason: statusCode == 401 ? .unauthorized : .transient
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
            return .failure(
                "Codex usage request failed: \(error.localizedDescription)",
                accountEmail: nil,
                accountID: auth?.accountID,
                failureReason: .transient
            )
        }
    }

    private func refreshAuth(_ auth: CodexAuthTokens?, profilePath: String) async -> CodexAuthRefreshOutcome {
        guard let auth, let refreshToken = auth.refreshToken, !refreshToken.isEmpty else {
            return .rejected
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = CodexOAuthContract.formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": CodexOAuthContract.clientID
        ])

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .transient("Codex token refresh did not return an HTTP response.")
            }
            guard 200..<300 ~= httpResponse.statusCode else {
                let errorCode = (try? JSONDecoder().decode(CodexTokenRefreshErrorResponse.self, from: data))?.error
                if httpResponse.statusCode == 401 || errorCode == "invalid_grant" || errorCode == "invalid_token" {
                    return .rejected
                }
                return .transient("Codex token refresh failed with HTTP \(httpResponse.statusCode).")
            }

            guard let refreshed = try JSONDecoder().decode(CodexTokenResponse.self, from: data)
                .codexTokens?
                .mergingMissingValues(from: auth)
            else {
                return .transient("Codex returned a token refresh response Brim could not understand.")
            }

            try CodexProfileAuthStore.save(tokens: refreshed, profilePath: profilePath, fileManager: fileManager)
            return .refreshed(refreshed)
        } catch {
            return .transient("Codex token refresh failed: \(error.localizedDescription)")
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
            let resolvedTokens = tokens.resolvingAccountIdentity()
            return resolvedTokens.hasUsableToken ? resolvedTokens : nil
        }

        let directTokens = CodexAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            accountID: accountID
        )
        let resolvedTokens = directTokens.resolvingAccountIdentity()
        return resolvedTokens.hasUsableToken ? resolvedTokens : nil
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

        return auth.tokens?.resolvingAccountIdentity()
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
        try ProviderProfileStorage.secureProfileDirectory(
            at: authURL.deletingLastPathComponent(),
            fileManager: fileManager
        )

        let resolvedTokens = tokens.resolvingAccountIdentity()
        let auth = CodexAuthFile(
            openAIAPIKey: nil,
            authMode: "chatgpt",
            lastRefresh: ISO8601DateFormatter.brimCodex.string(from: Date()),
            tokens: resolvedTokens
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(auth)
        try data.write(to: authURL, options: [.atomic])
        try ProviderProfileStorage.secureCredentialFile(at: authURL, fileManager: fileManager)
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
        ).resolvingAccountIdentity()
    }

    func resolvingAccountIdentity() -> CodexAuthTokens {
        let trimmedAccountID = accountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedAccountID.isEmpty else {
            return self
        }

        var resolvedTokens = self
        resolvedTokens.accountID = CodexJWT.accountID(from: idToken)
            ?? CodexJWT.accountID(from: accessToken)
        return resolvedTokens
    }

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case accountID = "account_id"
    }
}

private enum CodexJWT {
    private struct Payload: Decodable {
        var authentication: AuthenticationClaims?

        private enum CodingKeys: String, CodingKey {
            case authentication = "https://api.openai.com/auth"
        }
    }

    private struct AuthenticationClaims: Decodable {
        var chatGPTAccountID: String?

        private enum CodingKeys: String, CodingKey {
            case chatGPTAccountID = "chatgpt_account_id"
        }
    }

    static func accountID(from token: String?) -> String? {
        guard let token else {
            return nil
        }
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            return nil
        }

        var encodedPayload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encodedPayload.count % 4
        if remainder != 0 {
            encodedPayload.append(String(repeating: "=", count: 4 - remainder))
        }

        guard
            let data = Data(base64Encoded: encodedPayload),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            let accountID = payload.authentication?.chatGPTAccountID?.trimmingCharacters(in: .whitespacesAndNewlines),
            !accountID.isEmpty
        else {
            return nil
        }
        return accountID
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
