import Foundation

public enum QuotaConnectionKind: String, Codable, Hashable {
    case codexLogin
    case apiToken
    case manual

    public var title: String {
        switch self {
        case .codexLogin: return "Codex login"
        case .apiToken: return "API token"
        case .manual: return "Manual"
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
        case .waitingForQuotaSource: return "Waiting for quota source"
        case .refreshFailed: return "Refresh failed"
        case .manual: return "Manual values"
        }
    }
}

public struct QuotaAccount: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var weeklyLimitMinutes: Int
    public var usedMinutes: Int
    public var sessionLimitMinutes: Int?
    public var sessionUsedMinutes: Int?
    public var resetWeekday: Int
    public var resetHour: Int
    public var resetMinute: Int
    public var codexProfilePath: String?
    public var connectionKind: QuotaConnectionKind
    public var refreshStatus: QuotaRefreshStatus
    public var lastRefreshAttemptAt: Date?
    public var lastSuccessfulRefreshAt: Date?
    public var refreshMessage: String?
    public var credentialID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case colorHex
        case weeklyLimitMinutes
        case usedMinutes
        case sessionLimitMinutes
        case sessionUsedMinutes
        case resetWeekday
        case resetHour
        case resetMinute
        case codexProfilePath
        case connectionKind
        case refreshStatus
        case lastRefreshAttemptAt
        case lastSuccessfulRefreshAt
        case refreshMessage
        case credentialID
    }

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        weeklyLimitMinutes: Int,
        usedMinutes: Int,
        sessionLimitMinutes: Int? = QuotaAccountDefaults.sessionLimitMinutes,
        sessionUsedMinutes: Int? = nil,
        resetWeekday: Int,
        resetHour: Int,
        resetMinute: Int,
        codexProfilePath: String? = nil,
        connectionKind: QuotaConnectionKind = .codexLogin,
        refreshStatus: QuotaRefreshStatus = .waitingForQuotaSource,
        lastRefreshAttemptAt: Date? = nil,
        lastSuccessfulRefreshAt: Date? = nil,
        refreshMessage: String? = nil,
        credentialID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.weeklyLimitMinutes = weeklyLimitMinutes
        self.usedMinutes = usedMinutes
        self.sessionLimitMinutes = sessionLimitMinutes
        self.sessionUsedMinutes = sessionUsedMinutes
        self.resetWeekday = resetWeekday
        self.resetHour = resetHour
        self.resetMinute = resetMinute
        self.codexProfilePath = codexProfilePath
        self.connectionKind = connectionKind
        self.refreshStatus = refreshStatus
        self.lastRefreshAttemptAt = lastRefreshAttemptAt
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.refreshMessage = refreshMessage
        self.credentialID = credentialID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        weeklyLimitMinutes = try container.decode(Int.self, forKey: .weeklyLimitMinutes)
        usedMinutes = try container.decode(Int.self, forKey: .usedMinutes)
        sessionLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionLimitMinutes)
        sessionUsedMinutes = try container.decodeIfPresent(Int.self, forKey: .sessionUsedMinutes)
        resetWeekday = try container.decode(Int.self, forKey: .resetWeekday)
        resetHour = try container.decode(Int.self, forKey: .resetHour)
        resetMinute = try container.decode(Int.self, forKey: .resetMinute)
        codexProfilePath = try container.decodeIfPresent(String.self, forKey: .codexProfilePath)
        connectionKind = try container.decodeIfPresent(QuotaConnectionKind.self, forKey: .connectionKind) ?? .codexLogin
        refreshStatus = try container.decodeIfPresent(QuotaRefreshStatus.self, forKey: .refreshStatus) ?? .waitingForQuotaSource
        lastRefreshAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastRefreshAttemptAt)
        lastSuccessfulRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulRefreshAt)
        refreshMessage = try container.decodeIfPresent(String.self, forKey: .refreshMessage)
        credentialID = try container.decodeIfPresent(String.self, forKey: .credentialID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(weeklyLimitMinutes, forKey: .weeklyLimitMinutes)
        try container.encode(usedMinutes, forKey: .usedMinutes)
        try container.encodeIfPresent(sessionLimitMinutes, forKey: .sessionLimitMinutes)
        try container.encodeIfPresent(sessionUsedMinutes, forKey: .sessionUsedMinutes)
        try container.encode(resetWeekday, forKey: .resetWeekday)
        try container.encode(resetHour, forKey: .resetHour)
        try container.encode(resetMinute, forKey: .resetMinute)
        try container.encodeIfPresent(codexProfilePath, forKey: .codexProfilePath)
        try container.encode(connectionKind, forKey: .connectionKind)
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
        min(1, Double(sessionRemainingMinutes) / Double(sessionLimit))
    }

    public var resolvedCodexProfilePath: String {
        codexProfilePath ?? QuotaAccountDefaults.defaultCodexProfilePath(for: name)
    }
}
