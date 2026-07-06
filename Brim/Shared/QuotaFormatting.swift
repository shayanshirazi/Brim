import Foundation

public enum QuotaFormatting {
    public static func percentText(_ fraction: Double) -> String {
        "\(Int(round(fraction * 100)))%"
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

    public static func sessionWindowLabel(for account: QuotaAccount) -> String {
        minutes(account.sessionLimit)
    }

    public static func remainingLine(for account: QuotaAccount) -> String {
        "\(sessionWindowLabel(for: account)) \(minutes(account.sessionRemainingMinutes)) left / weekly \(minutes(account.weeklyRemainingMinutes)) left"
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

    public static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    public static func expandedHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

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

    public static func codexCommand(path: String, subcommand: String? = nil) -> String {
        let suffix = subcommand.map { " \($0)" } ?? ""
        return "CODEX_HOME=\(shellQuoted(expandedHomePath(path))) codex\(suffix)"
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
        QuotaFormatting.percentText(weeklyRemainingFraction)
    }

    var sessionPercentText: String {
        QuotaFormatting.percentText(sessionRemainingFraction)
    }

    var resetText: String {
        QuotaFormatting.resetText(for: self)
    }

    func weeklyResetRelativeText(from now: Date = Date(), calendar: Calendar = .current) -> String {
        QuotaFormatting.weeklyResetRelativeText(for: self, from: now, calendar: calendar)
    }

    func weeklyResetDateText(from now: Date = Date(), calendar: Calendar = .current) -> String {
        QuotaFormatting.weeklyResetDateText(for: self, from: now, calendar: calendar)
    }
}

public func formatMinutes(_ minutes: Int) -> String {
    QuotaFormatting.minutes(minutes)
}
