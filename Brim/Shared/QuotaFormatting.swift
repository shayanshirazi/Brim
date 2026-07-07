import Darwin
import Foundation

public enum QuotaFormatting {
    public static var userHomeDirectoryPath: String {
        if let home = NSHomeDirectoryForUser(NSUserName()), !home.isEmpty {
            return home
        }

        if
            let passwd = getpwuid(getuid()),
            let home = passwd.pointee.pw_dir
        {
            return String(cString: home)
        }

        let sandboxHome = FileManager.default.homeDirectoryForCurrentUser.path
        if let containerRange = sandboxHome.range(of: "/Library/Containers/") {
            return String(sandboxHome[..<containerRange.lowerBound])
        }

        return sandboxHome
    }

    public static var applicationSupportDirectoryPath: String {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return directory.appendingPathComponent("Brim", isDirectory: true).path
    }

    public static func percentText(_ fraction: Double) -> String {
        return "\(Int(round(fraction * 100)))%"
    }

    public static func minutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60

        if hours == 0 {
            return "\(remainder)m"
        }

        if remainder == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(remainder)m"
    }

    public static func windowDuration(_ minutes: Int) -> String {
        let days = minutes / (24 * 60)
        let dayRemainder = minutes % (24 * 60)

        if days > 0, dayRemainder == 0 {
            return "\(days)d"
        }

        if days > 0 {
            return "\(days)d \(Self.minutes(dayRemainder))"
        }

        return Self.minutes(minutes)
    }

    public static func usageLimitTitle(minutes: Int) -> String {
        if minutes % (24 * 60) == 0 {
            let days = max(1, minutes / (24 * 60))
            return "\(days) day usage limit"
        }

        if minutes % 60 == 0 {
            let hours = max(1, minutes / 60)
            return "\(hours) hour usage limit"
        }

        return "\(windowDuration(minutes)) usage limit"
    }

    public static func sessionWindowLabel(for account: QuotaAccount) -> String {
        return windowDuration(account.sessionWindowMinutes)
    }

    public static func remainingLine(for account: QuotaAccount) -> String {
        guard account.hasUsageSnapshot else {
            return "\(account.provider.displayName) connected"
        }

        if account.usesRateLimitPercentages {
            return "Session \(account.sessionPercentText) left / weekly \(account.remainingPercentText) left"
        }

        return "\(sessionWindowLabel(for: account)) \(minutes(account.sessionRemainingMinutes)) left / weekly \(minutes(account.weeklyRemainingMinutes)) left"
    }

    public static func resetText(for account: QuotaAccount) -> String {
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekday = weekdays[max(0, min(6, account.resetWeekday - 1))]
        let hour12 = account.resetHour % 12 == 0 ? 12 : account.resetHour % 12
        let minute = String(format: "%02d", account.resetMinute)
        let period = account.resetHour < 12 ? "AM" : "PM"
        return "\(weekday) \(hour12):\(minute) \(period)"
    }

    public static func nextWeeklyResetDate(
        for account: QuotaAccount,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        var components = DateComponents()
        components.weekday = max(1, min(7, account.resetWeekday))
        components.hour = account.resetHour
        components.minute = account.resetMinute
        components.second = 0

        return calendar.nextDate(
            after: now,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? now
    }

    public static func weeklyResetRelativeText(
        for account: QuotaAccount,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let resetDate = nextWeeklyResetDate(for: account, from: now, calendar: calendar)
        let interval = max(0, resetDate.timeIntervalSince(now))

        guard interval >= 60 else {
            return "now"
        }

        let formatter = DateComponentsFormatter()
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated

        if interval < 60 * 60 {
            formatter.allowedUnits = [.minute]
        } else if interval < 24 * 60 * 60 {
            formatter.allowedUnits = [.hour, .minute]
        } else {
            formatter.allowedUnits = [.day, .hour]
        }

        return formatter.string(from: interval) ?? resetText(for: account)
    }

    public static func weeklyResetDateText(
        for account: QuotaAccount,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let resetDate = nextWeeklyResetDate(for: account, from: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "EEE MMM d, h:mm a"
        return formatter.string(from: resetDate)
    }

    public static func resetDateLine(
        resetAt: Date?,
        fallback: Date? = nil,
        unavailableText: String,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let resetDate = resetAt ?? fallback else {
            return unavailableText
        }

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = .current
        timeFormatter.dateFormat = "h:mm a"

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = calendar
        dateFormatter.locale = .current
        dateFormatter.dateFormat = "EEE, h:mm a"

        if calendar.isDate(resetDate, inSameDayAs: now) {
            return "Resets today \(timeFormatter.string(from: resetDate))"
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(resetDate, inSameDayAs: tomorrow) {
            return "Resets tomorrow \(timeFormatter.string(from: resetDate))"
        }

        return "Resets \(dateFormatter.string(from: resetDate))"
    }

    public static func expandedHomePath(_ path: String) -> String {
        let home = userHomeDirectoryPath
        let applicationSupport = applicationSupportDirectoryPath

        if path == "$APP_SUPPORT" {
            return applicationSupport
        }

        if path.hasPrefix("$APP_SUPPORT/") {
            return applicationSupport + String(path.dropFirst("$APP_SUPPORT".count))
        }

        if path == "$HOME" {
            return home
        }

        if path.hasPrefix("$HOME/") {
            return home + String(path.dropFirst("$HOME".count))
        }

        if path == "~" {
            return home
        }

        if path.hasPrefix("~/") {
            return home + String(path.dropFirst(1))
        }

        return path
    }

    public static func emailAddress(in text: String) -> String? {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        return String(text[range])
    }
}

public extension QuotaAccount {
    var remainingPercentText: String {
        guard hasUsageSnapshot, !refreshStatus.hidesQuotaDetails else {
            return "?"
        }

        return QuotaFormatting.percentText(weeklyRemainingFraction)
    }

    var sessionPercentText: String {
        guard hasUsageSnapshot, !refreshStatus.hidesQuotaDetails else {
            return "?"
        }

        return QuotaFormatting.percentText(sessionRemainingFraction)
    }

    var usageSummaryText: String {
        guard !refreshStatus.hidesQuotaDetails else {
            return refreshStatus.title.lowercased()
        }

        return hasUsageSnapshot ? "\(sessionPercentText) · \(remainingPercentText)" : "unavailable"
    }

    var resetText: String {
        return QuotaFormatting.resetText(for: self)
    }

    func weeklyResetRelativeText(from now: Date = Date(), calendar: Calendar = .current) -> String {
        return QuotaFormatting.weeklyResetRelativeText(for: self, from: now, calendar: calendar)
    }

    func weeklyResetDateText(from now: Date = Date(), calendar: Calendar = .current) -> String {
        return QuotaFormatting.weeklyResetDateText(for: self, from: now, calendar: calendar)
    }

    func sessionResetLine(from now: Date = Date(), calendar: Calendar = .current) -> String {
        return QuotaFormatting.resetDateLine(
            resetAt: sessionResetAt,
            unavailableText: "Rolling \(QuotaFormatting.windowDuration(sessionWindowMinutes)) window",
            from: now,
            calendar: calendar
        )
    }

    func weeklyResetLine(from now: Date = Date(), calendar: Calendar = .current) -> String {
        return QuotaFormatting.resetDateLine(
            resetAt: weeklyResetAt,
            fallback: QuotaFormatting.nextWeeklyResetDate(for: self, from: now, calendar: calendar),
            unavailableText: "Reset date unavailable",
            from: now,
            calendar: calendar
        )
    }
}

public func formatMinutes(_ minutes: Int) -> String {
    return QuotaFormatting.minutes(minutes)
}
