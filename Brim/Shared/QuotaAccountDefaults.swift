import Foundation

public enum QuotaAccountDefaults {
    public static let weeklyLimitMinutes = 300
    public static let sessionLimitMinutes = 300
    public static let resetWeekday = 2
    public static let resetHour = 0
    public static let resetMinute = 0
    public static let minimumLimitMinutes = 1
    public static let maximumWeeklyLimitMinutes = 3000
    public static let maximumSessionLimitMinutes = 1200
    public static let limitStepMinutes = 15
    public static let mediumWidgetSlotCount = 4
    public static let palette = ["#40E06B", "#65D6FF", "#F7C948", "#FF7A90", "#B49BFF"]

    public static func defaultCodexProfilePath(for name: String) -> String {
        let slug = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return "$HOME/.codex-accounts/\(slug.isEmpty ? "account" : slug)"
    }

    public static func newAccount(index: Int, connectionKind: QuotaConnectionKind = .codexLogin) -> QuotaAccount {
        let displayIndex = max(1, index)
        let name = "Account \(displayIndex)"
        return QuotaAccount(
            name: name,
            colorHex: palette[(displayIndex - 1) % palette.count],
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: 0,
            sessionLimitMinutes: sessionLimitMinutes,
            sessionUsedMinutes: 0,
            resetWeekday: resetWeekday,
            resetHour: resetHour,
            resetMinute: resetMinute,
            codexProfilePath: "$HOME/.codex-accounts/account-\(displayIndex)",
            connectionKind: connectionKind,
            refreshStatus: .notConnected
        )
    }

    public static let examples: [QuotaAccount] = [
        QuotaAccount(
            name: "Main",
            colorHex: "#40E06B",
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: 0,
            resetWeekday: resetWeekday,
            resetHour: resetHour,
            resetMinute: resetMinute,
            codexProfilePath: "$HOME/.codex-accounts/main"
        ),
        QuotaAccount(
            name: "Backup",
            colorHex: "#65D6FF",
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: 42,
            resetWeekday: resetWeekday,
            resetHour: resetHour,
            resetMinute: resetMinute,
            codexProfilePath: "$HOME/.codex-accounts/backup"
        )
    ]
}
