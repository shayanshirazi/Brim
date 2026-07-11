import Foundation

public struct QuotaRefreshResult {
    public var status: QuotaRefreshStatus
    public var message: String?
    public var quota: QuotaUsageSnapshot?
    public var accountEmail: String?
    public var providerAccountID: String?
    /// When true and `quota` is nil, a transient refresh failure keeps the last
    /// known snapshot instead of replacing it with an empty state.
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
    case unavailable(
        String,
        accountEmail: String?,
        accountID: String? = nil,
        failureKind: CodexUsageFailureKind = .unavailable
    )

    public var isUnauthorized: Bool {
        if case .unavailable(_, _, _, let failureKind) = self {
            return failureKind == .unauthorized
        }

        return false
    }

    public var isTransientFailure: Bool {
        if case .unavailable(_, _, _, let failureKind) = self {
            return failureKind == .transient
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

public enum CodexUsageFailureKind: Hashable {
    case unavailable
    case transient
    case unauthorized
}
