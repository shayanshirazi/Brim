import Foundation

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

    public var successfulUsageResult: CodexUsageFetchResult? {
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
