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
        let now = Date()

        for var account in accountsToRefresh {
            account.lastRefreshAttemptAt = now
            account.refreshStatus = .waitingForQuotaSource
            account.refreshMessage = nil
            state.updateAccount(account)
        }
        persist()

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

            if result.status == .ready {
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
    public var apiTokenIsAvailable: (String) -> Bool
    public var usageFetcher: (QuotaAccount) async -> CodexUsageFetchOutcome

    public init(
        apiTokenIsAvailable: @escaping (String) -> Bool = { _ in false },
        usageFetcher: @escaping (QuotaAccount) async -> CodexUsageFetchOutcome = { account in
            await CodexUsageClient().fetchUsage(for: account)
        }
    ) {
        self.apiTokenIsAvailable = apiTokenIsAvailable
        self.usageFetcher = usageFetcher
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
                    ? "\(account.provider.displayName) token is saved. Exact usage opens in \(account.provider.displayName)."
                    : "Loaded quota snapshot from local profile.",
                quota: quota
            )
        case .login:
            switch account.provider {
            case .codex:
                return await refreshCodexLogin(account)
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

public struct QuotaRefreshResult {
    public var status: QuotaRefreshStatus
    public var message: String?
    public var quota: QuotaUsageSnapshot?
    public var accountEmail: String?
    public var providerAccountID: String?

    public init(
        status: QuotaRefreshStatus,
        message: String?,
        quota: QuotaUsageSnapshot?,
        accountEmail: String? = nil,
        providerAccountID: String? = nil
    ) {
        self.status = status
        self.message = message
        self.quota = quota
        self.accountEmail = accountEmail
        self.providerAccountID = providerAccountID
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
    case unavailable(String, accountEmail: String?, accountID: String? = nil)

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
        case .unavailable(_, let accountEmail, _):
            return accountEmail
        }
    }

    public var accountID: String? {
        switch self {
        case .success(let result):
            return result.accountID
        case .unavailable(_, _, let accountID):
            return accountID
        }
    }

    public var message: String {
        switch self {
        case .success:
            return "Loaded live Codex usage."
        case .unavailable(let message, _, _):
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
        case .unavailable(let message, let accountEmail, let accountID, _):
            return .unavailable(message, accountEmail: accountEmail, accountID: accountID)
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
        if case .unauthorized = outcome.failureReason,
           let refreshedAuth = await refreshAuthIfPossible(auth, profilePath: profilePath) {
            return await fetchUsage(for: account, auth: refreshedAuth, didRefreshToken: true).publicOutcome
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

        let resetComponents = resetComponents(from: secondary.resetAt)

        return QuotaUsageSnapshot(
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: secondary.usedMinutes(limitMinutes: weeklyLimitMinutes),
            sessionLimitMinutes: sessionLimitMinutes,
            sessionUsedMinutes: primary.usedMinutes(limitMinutes: sessionLimitMinutes),
            weeklyUsedPercent: secondary.normalizedUsedPercent,
            sessionUsedPercent: primary.normalizedUsedPercent,
            sessionResetAt: primary.resetDate,
            weeklyResetAt: secondary.resetDate,
            resetWeekday: resetComponents.weekday,
            resetHour: resetComponents.hour,
            resetMinute: resetComponents.minute
        )
    }

    private func resetComponents(from timestamp: TimeInterval?) -> DateComponents {
        guard let timestamp else {
            return DateComponents()
        }

        let date = Date(timeIntervalSince1970: timestamp)
        return calendar.dateComponents([.weekday, .hour, .minute], from: date)
    }
}

enum CodexOAuthContract {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let authBaseURL = URL(string: "https://auth.openai.com/oauth/authorize")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
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

    private enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }

    init(usedPercent: Double?, limitWindowSeconds: Double?, resetAt: TimeInterval?) {
        self.usedPercent = usedPercent
        self.limitWindowSeconds = limitWindowSeconds
        self.resetAt = resetAt
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

    var resetDate: Date? {
        resetAt.map { Date(timeIntervalSince1970: $0) }
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
            keys: [.resetAt, .resetAtCamel]
        ).map(Self.timestampSeconds)

        rateLimitWindow = CodexRateLimitWindow(
            usedPercent: decodedUsedPercent ?? decodedRemainingPercent.map { 100 - $0 },
            limitWindowSeconds: limitWindowSeconds,
            resetAt: resetAt
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
