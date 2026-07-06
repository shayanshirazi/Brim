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
        var state = snapshotStore.load().state
        mutate(&state)
        _ = snapshotStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

public struct QuotaRefreshService {
    public var apiTokenIsAvailable: (String) -> Bool
    public var commandRunner: (String, String) async -> CommandResult
    public var usageFetcher: (QuotaAccount) async -> CodexUsageFetchOutcome

    public init(
        apiTokenIsAvailable: @escaping (String) -> Bool = { _ in false },
        commandRunner: @escaping (String, String) async -> CommandResult = { _, _ in
            CommandResult(
                exitCode: -1,
                standardOutput: "",
                standardError: "Codex status runner is not configured."
            )
        },
        usageFetcher: @escaping (QuotaAccount) async -> CodexUsageFetchOutcome = { account in
            await CodexUsageClient().fetchUsage(for: account)
        }
    ) {
        self.apiTokenIsAvailable = apiTokenIsAvailable
        self.commandRunner = commandRunner
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

            let result = await commandRunner(profilePath, "login status")
            let output = (result.standardOutput + "\n" + result.standardError).lowercased()

            if result.exitCode == 0, output.contains("logged in") {
                let usageOutcome = await usageFetcher(account)
                let usage = usageOutcome.result
                let quota = usage?.quota ?? readLocalQuotaSnapshot(for: account)
                return QuotaRefreshResult(
                    status: .ready,
                    message: quota == nil
                        ? usageOutcome.message
                        : (usage == nil ? "Loaded quota snapshot from local profile." : "Loaded live Codex usage."),
                    quota: quota,
                    accountEmail: usageOutcome.accountEmail ?? QuotaFormatting.emailAddress(in: result.standardOutput + "\n" + result.standardError)
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
                message: commandFailureMessage(from: result),
                quota: nil
            )
    }

    private func commandFailureMessage(from result: CommandResult) -> String {
        let message = result.standardOutput.isEmpty ? result.standardError : result.standardOutput
        let trimmed = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return trimmed.isEmpty ? "Brim could not check the Codex session." : trimmed
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

    public init(quota: QuotaUsageSnapshot, email: String? = nil) {
        self.quota = quota
        self.email = email
    }
}

public enum CodexUsageFetchOutcome: Hashable {
    case success(CodexUsageFetchResult)
    case unavailable(String, accountEmail: String?)

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
        case .unavailable(_, let accountEmail):
            return accountEmail
        }
    }

    public var message: String {
        switch self {
        case .success:
            return "Loaded live Codex usage."
        case .unavailable(let message, _):
            return message
        }
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
        guard let token = accessToken(for: account) else {
            return .unavailable("Codex is connected, but Brim could not find this profile's auth token.", accountEmail: nil)
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
                return .unavailable("Codex usage request failed with HTTP \(statusCode).", accountEmail: nil)
            }

            let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            guard let quota = quotaSnapshot(from: usage) else {
                return .unavailable(
                    "Codex usage response did not include rate-limit data Brim understands.",
                    accountEmail: usage.email
                )
            }

            return .success(CodexUsageFetchResult(quota: quota, email: usage.email))
        } catch {
            return .unavailable("Codex usage request failed: \(error.localizedDescription)", accountEmail: nil)
        }
    }

    private func accessToken(for account: QuotaAccount) -> String? {
        let profilePath = QuotaFormatting.expandedHomePath(account.resolvedProviderProfilePath)
        let authURL = URL(fileURLWithPath: profilePath, isDirectory: true).appendingPathComponent("auth.json")
        guard
            fileManager.fileExists(atPath: authURL.path),
            let data = try? Data(contentsOf: authURL),
            let auth = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
            let token = auth.tokens?.accessToken,
            !token.isEmpty
        else {
            return nil
        }

        return token
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

private struct CodexAuthFile: Decodable {
    var tokens: CodexAuthTokens?
}

private struct CodexAuthTokens: Decodable {
    var accessToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
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
