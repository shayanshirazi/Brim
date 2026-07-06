import Foundation

public enum QuotaProviderKind: String, Codable, Hashable, CaseIterable {
    case codex

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        }
    }

    public var usageURL: URL? {
        switch self {
        case .codex:
            return URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage")
        }
    }

    public var logoAssetName: String? {
        switch self {
        case .codex: return "CodexLogo"
        }
    }

    public var brandColorHex: String {
        switch self {
        case .codex: return "#6675FF"
        }
    }

    public var loginTitle: String {
        switch self {
        case .codex: return "Codex sign-in"
        }
    }

    public var profileFolderName: String {
        switch self {
        case .codex: return ".codex-accounts"
        }
    }
}

public enum QuotaConnectionKind: Hashable {
    case login
    case apiToken
    case manual

    public var title: String {
        switch self {
        case .login: return "Login"
        case .apiToken: return "API token"
        case .manual: return "Manual"
        }
    }
}

extension QuotaConnectionKind: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "codexLogin", "login":
            self = .login
        case "apiToken":
            self = .apiToken
        case "manual":
            self = .manual
        default:
            let context = DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown quota connection kind '\(value)'."
            )
            throw DecodingError.dataCorrupted(context)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .login:
            try container.encode("login")
        case .apiToken:
            try container.encode("apiToken")
        case .manual:
            try container.encode("manual")
        }
    }
}

public enum QuotaRefreshStatus: String, Codable, Hashable {
    case notConnected
    case ready
    case waitingForQuotaSource
    case refreshFailed
    case manual

    public var title: String {
        switch self {
        case .notConnected: return "Not connected"
        case .ready: return "Connected"
        case .waitingForQuotaSource: return "Checking"
        case .refreshFailed: return "Refresh failed"
        case .manual: return "Manual values"
        }
    }

    public var hidesQuotaDetails: Bool {
        switch self {
        case .notConnected, .refreshFailed:
            return true
        case .ready, .waitingForQuotaSource, .manual:
            return false
        }
    }
}

public enum QuotaSignalState: Hashable {
    case notConnected
    case ready
    case waitingForQuotaSource
    case refreshFailed
    case manual
    case exhausted

    public var title: String {
        switch self {
        case .notConnected: return "Not connected"
        case .ready: return "Connected"
        case .waitingForQuotaSource: return "Checking"
        case .refreshFailed: return "Refresh failed"
        case .manual: return "Manual values"
        case .exhausted: return "Exhausted"
        }
    }
}

public struct QuotaAccount: Codable, Hashable, Identifiable {
    public var id: UUID
    public var provider: QuotaProviderKind
    public var providerAccountID: String?
    public var name: String
    public var accountEmail: String?
    public var colorHex: String
    public var weeklyLimitMinutes: Int
    public var usedMinutes: Int
    public var sessionLimitMinutes: Int?
    public var sessionUsedMinutes: Int?
    public var weeklyUsedPercent: Double?
    public var sessionUsedPercent: Double?
    public var sessionResetAt: Date?
    public var weeklyResetAt: Date?
    public var resetWeekday: Int
    public var resetHour: Int
    public var resetMinute: Int
    public var providerProfilePath: String?
    public var connectionKind: QuotaConnectionKind
    public var hasUsageSnapshot: Bool
    public var refreshStatus: QuotaRefreshStatus
    public var lastRefreshAttemptAt: Date?
    public var lastSuccessfulRefreshAt: Date?
    public var refreshMessage: String?
    public var credentialID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case providerAccountID
        case name
        case accountEmail
        case colorHex
        case weeklyLimitMinutes
        case usedMinutes
        case sessionLimitMinutes
        case sessionUsedMinutes
        case weeklyUsedPercent
        case sessionUsedPercent
        case sessionResetAt
        case weeklyResetAt
        case resetWeekday
        case resetHour
        case resetMinute
        case providerProfilePath
        case codexProfilePath
        case connectionKind
        case hasUsageSnapshot
        case refreshStatus
        case lastRefreshAttemptAt
        case lastSuccessfulRefreshAt
        case refreshMessage
        case credentialID
    }

    public init(
        id: UUID = UUID(),
        provider: QuotaProviderKind = .codex,
        providerAccountID: String? = nil,
        name: String,
        accountEmail: String? = nil,
        colorHex: String,
        weeklyLimitMinutes: Int,
        usedMinutes: Int,
        sessionLimitMinutes: Int? = QuotaAccountDefaults.sessionLimitMinutes,
        sessionUsedMinutes: Int? = nil,
        weeklyUsedPercent: Double? = nil,
        sessionUsedPercent: Double? = nil,
        sessionResetAt: Date? = nil,
        weeklyResetAt: Date? = nil,
        resetWeekday: Int,
        resetHour: Int,
        resetMinute: Int,
        providerProfilePath: String? = nil,
        connectionKind: QuotaConnectionKind = .login,
        hasUsageSnapshot: Bool = true,
        refreshStatus: QuotaRefreshStatus = .waitingForQuotaSource,
        lastRefreshAttemptAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        refreshMessage: String? = nil,
        credentialID: String? = nil
    ) {
        self.id = id
        self.provider = provider
        self.providerAccountID = providerAccountID
        self.name = name
        self.accountEmail = accountEmail
        self.colorHex = colorHex
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
        self.providerProfilePath = providerProfilePath
        self.connectionKind = connectionKind
        self.hasUsageSnapshot = hasUsageSnapshot
        self.refreshStatus = refreshStatus
        self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.refreshMessage = refreshMessage
        self.credentialID = credentialID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decodeIfPresent(QuotaProviderKind.self, forKey: .provider) ?? .codex
        providerAccountID = try container.decodeIfPresent(String.self, forKey: .providerAccountID)
        name = try container.decode(String.self, forKey: .name)
        accountEmail = try container.decodeIfPresent(String.self, forKey: .accountEmail)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        weeklyLimitMinutes = try container.decode(Int.self, forKey: .weeklyLimitMinutes)
        usedMinutes = try container.decode(Int.self, forKey: .usedMinutes)
        sessionLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionLimitMinutes)
        sessionUsedMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionUsedMinutes)
        weeklyUsedPercent = try container.decodeIfPresent(Double.self, forKey: .weeklyUsedPercent)
        sessionUsedPercent = try container.decodeIfPresent(Double.self, forKey: .sessionUsedPercent)
        sessionResetAt = try container.decodeIfPresent(Date.self, forKey: .sessionResetAt)
        weeklyResetAt = try container.decodeIfPresent(Date.self, forKey: .weeklyResetAt)
        resetWeekday = try container.decode(Int.self, forKey: .resetWeekday)
        resetHour = try container.decode(Int.self, forKey: .resetHour)
        resetMinute = try container.decode(Int.self, forKey: .resetMinute)
        providerProfilePath = try container.decodeIfPresent(String.self, forKey: .providerProfilePath)
            ?? container.decodeIfPresent(String.self, forKey: .codexProfilePath)
        connectionKind = try container.decodeIfPresent(QuotaConnectionKind.self, forKey: .connectionKind) ?? .login
        hasUsageSnapshot = try container.decodeIfPresent(Bool.self, forKey: .hasUsageSnapshot) ?? (connectionKind == .manual)
        refreshStatus = try container.decodeIfPresent(QuotaRefreshStatus.self, forKey: .refreshStatus) ?? .waitingForQuotaSource
        lastRefreshAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshAttemptAt)
        lastSuccessfulRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulRefreshAt)
        refreshMessage = try container.decodeIfPresent(String.self, forKey: .refreshMessage)
        credentialID = try container.decodeIfPresent(String.self, forKey: .credentialID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(providerAccountID, forKey: .providerAccountID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(accountEmail, forKey: .accountEmail)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(weeklyLimitMinutes, forKey: .weeklyLimitMinutes)
        try container.encode(usedMinutes, forKey: .usedMinutes)
        try container.encodeIfPresent(sessionLimitMinutes, forKey: .sessionLimitMinutes)
        try container.encodeIfPresent(sessionUsedMinutes, forKey: .sessionUsedMinutes)
        try container.encodeIfPresent(weeklyUsedPercent, forKey: .weeklyUsedPercent)
        try container.encodeIfPresent(sessionUsedPercent, forKey: .sessionUsedPercent)
        try container.encodeIfPresent(sessionResetAt, forKey: .sessionResetAt)
        try container.encodeIfPresent(weeklyResetAt, forKey: .weeklyResetAt)
        try container.encode(resetWeekday, forKey: .resetWeekday)
        try container.encode(resetHour, forKey: .resetHour)
        try container.encode(resetMinute, forKey: .resetMinute)
        try container.encodeIfPresent(providerProfilePath, forKey: .providerProfilePath)
        try container.encode(connectionKind, forKey: .connectionKind)
        try container.encode(hasUsageSnapshot, forKey: .hasUsageSnapshot)
        try container.encode(refreshStatus, forKey: .refreshStatus)
        try container.encodeIfPresent(lastRefreshAttemptAt, forKey: .lastRefreshAttemptAt)
        try container.encodeIfPresent(lastSuccessfulRefreshAt, forKey: .lastSuccessfulRefreshAt)
        try container.encodeIfPresent(refreshMessage, forKey: .refreshMessage)
        try container.encodeIfPresent(credentialID, forKey: .credentialID)
    }

    public var weeklyRemainingMinutes: Int {
        max(0, weeklyLimitMinutes - usedMinutes)
    }

    public var remainingMinutes: Int {
        weeklyRemainingMinutes
    }

    public var weeklyRemainingFraction: Double {
        if let weeklyUsedPercent {
            return max(0, min(1, (100 - weeklyUsedPercent) / 100))
        }

        guard weeklyLimitMinutes > 0 else { return 0 }
        return min(1, Double(weeklyRemainingMinutes) / Double(weeklyLimitMinutes))
    }

    public var remainingFraction: Double {
        weeklyRemainingFraction
    }

    public var sessionLimit: Int {
        max(1, sessionLimitMinutes ?? QuotaAccountDefaults.sessionLimitMinutes)
    }

    public var sessionUsed: Int {
        max(0, sessionUsedMinutes ?? usedMinutes)
    }

    public var sessionRemainingMinutes: Int {
        max(0, sessionLimit - sessionUsed)
    }

    public var sessionRemainingFraction: Double {
        if let sessionUsedPercent {
            return max(0, min(1, (100 - sessionUsedPercent) / 100))
        }

        return min(1, Double(sessionRemainingMinutes) / Double(sessionLimit))
    }

    public var usesRateLimitPercentages: Bool {
        weeklyUsedPercent != nil || sessionUsedPercent != nil
    }

    public var hasExhaustedQuota: Bool {
        guard hasUsageSnapshot, !refreshStatus.hidesQuotaDetails else {
            return false
        }

        return roundedPercent(weeklyRemainingFraction) <= 0 || roundedPercent(sessionRemainingFraction) <= 0
    }

    public var signalState: QuotaSignalState {
        if hasExhaustedQuota {
            return .exhausted
        }

        switch refreshStatus {
        case .notConnected:
            return .notConnected
        case .ready:
            return .ready
        case .waitingForQuotaSource:
            return .waitingForQuotaSource
        case .refreshFailed:
            return .refreshFailed
        case .manual:
            return .manual
        }
    }

    public var weeklyWindowMinutes: Int {
        weeklyLimitMinutes
    }

    public var sessionWindowMinutes: Int {
        sessionLimit
    }

    private func roundedPercent(_ fraction: Double) -> Int {
        Int(round(fraction * 100))
    }

    public var resolvedProviderProfilePath: String {
        providerProfilePath ?? QuotaAccountDefaults.defaultProfilePath(for: name, provider: provider)
    }

    public var copyableAccountIdentifier: String {
        let trimmedProviderID = providerAccountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedProviderID
    }

    public var shortAccountIdentifier: String {
        let identifier = copyableAccountIdentifier
        guard !identifier.isEmpty else {
            return "Unavailable"
        }
        guard identifier.count > 14 else {
            return identifier
        }

        return "\(identifier.prefix(6))...\(identifier.suffix(6))"
    }

    public var normalizedAccountEmail: String? {
        let trimmedEmail = accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedEmail.isEmpty ? nil : trimmedEmail
    }

    public var headerDisplayName: String {
        name
    }

    public func widgetSnapshotAccount() -> QuotaAccount {
        var account = clearingPrivateProviderFields(keepProfilePath: false)
        account.lastRefreshAttemptAt = nil
        account.lastSuccessfulRefreshAt = nil
        account.refreshMessage = nil
        return account.normalizedForStorage()
    }

    public func portableExportAccount() -> QuotaAccount {
        var account = clearingPortableFields()
        account.refreshMessage = nil
        return account.normalizedForStorage()
    }

    public func portableImportAccount() -> QuotaAccount {
        var account = clearingPortableFields()

        switch account.connectionKind {
        case .apiToken:
            account.refreshStatus = .notConnected
            account.refreshMessage = "Add this device's API token to reconnect."
            account.lastSuccessfulRefreshAt = nil
        case .login:
            account.refreshStatus = .notConnected
            account.refreshMessage = "Sign in with \(account.provider.displayName) on this device to reconnect."
            account.lastSuccessfulRefreshAt = nil
        case .manual:
            account.refreshStatus = .manual
            account.refreshMessage = "Manual values are used."
        }

        return account.normalizedForStorage()
    }

    public func disconnectedProviderAccount(message: String) -> QuotaAccount {
        var account = clearingPrivateProviderFields(keepProfilePath: true)
        account.usedMinutes = 0
        account.sessionUsedMinutes = 0
        account.weeklyUsedPercent = nil
        account.sessionUsedPercent = nil
        account.sessionResetAt = nil
        account.weeklyResetAt = nil
        account.hasUsageSnapshot = false
        account.refreshStatus = .notConnected
        account.refreshMessage = message
        account.lastRefreshAttemptAt = Date()
        account.lastSuccessfulRefreshAt = nil
        return account.normalizedForStorage()
    }

    private func clearingPortableFields() -> QuotaAccount {
        var account = clearingPrivateProviderFields(keepProfilePath: false)
        account.lastRefreshAttemptAt = nil
        account.lastSuccessfulRefreshAt = nil

        guard account.connectionKind != .manual else {
            account.refreshStatus = .manual
            account.refreshMessage = "Manual values are used."
            return account
        }

        account.usedMinutes = 0
        account.sessionUsedMinutes = 0
        account.weeklyUsedPercent = nil
        account.sessionUsedPercent = nil
        account.sessionResetAt = nil
        account.weeklyResetAt = nil
        account.hasUsageSnapshot = false
        account.refreshStatus = .notConnected
        return account
    }

    private func clearingPrivateProviderFields(keepProfilePath: Bool) -> QuotaAccount {
        var account = self
        account.providerAccountID = nil
        account.accountEmail = nil
        if !keepProfilePath {
            account.providerProfilePath = nil
        }
        account.credentialID = nil
        return account
    }
}
