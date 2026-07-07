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
    public static let presetColorHexes = [
        "#22C55E", "#06B6D4", "#3B82F6", "#8B5CF6",
        "#EC4899", "#EF4444", "#F59E0B", "#14B8A6",
        "#6366F1", "#F97316", "#0EA5E9"
    ]
    public static let palette = presetColorHexes

    public static func defaultProfilePath(for name: String, provider: QuotaProviderKind) -> String {
        let slug = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return "$APP_SUPPORT/Profiles/\(provider.rawValue)/\(slug.isEmpty ? "account" : slug)"
    }

    public static func newAccount(
        index: Int,
        provider: QuotaProviderKind = .codex,
        connectionKind: QuotaConnectionKind = .login,
        existingColorHexes: [String] = []
    ) -> QuotaAccount {
        let displayIndex = max(1, index)
        let name = "Account \(displayIndex)"
        return QuotaAccount(
            provider: provider,
            name: name,
            colorHex: colorHexForNewAccount(existingColorHexes: existingColorHexes),
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: 0,
            sessionLimitMinutes: sessionLimitMinutes,
            sessionUsedMinutes: 0,
            resetWeekday: resetWeekday,
            resetHour: resetHour,
            resetMinute: resetMinute,
            providerProfilePath: "$APP_SUPPORT/Profiles/\(provider.rawValue)/account-\(displayIndex)",
            connectionKind: connectionKind,
            hasUsageSnapshot: false,
            refreshStatus: .notConnected
        )
    }

    public static func colorHexForNewAccount(existingColorHexes: [String]) -> String {
        let usedColors = Set(existingColorHexes.compactMap(QuotaColor.normalizedHex))
        if let presetColor = presetColorHexes.first(where: { preset in
            guard let normalizedPreset = QuotaColor.normalizedHex(preset) else {
                return false
            }

            return !usedColors.contains(normalizedPreset)
        }) {
            return QuotaColor.normalizedHex(presetColor) ?? QuotaColor.fallbackHex
        }

        return QuotaColor.randomCustomHex(excluding: usedColors)
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
            providerProfilePath: "$APP_SUPPORT/Profiles/codex/main"
        ),
        QuotaAccount(
            name: "Backup",
            colorHex: "#65D6FF",
            weeklyLimitMinutes: weeklyLimitMinutes,
            usedMinutes: 42,
            resetWeekday: resetWeekday,
            resetHour: resetHour,
            resetMinute: resetMinute,
            providerProfilePath: "$APP_SUPPORT/Profiles/codex/backup"
        )
    ]
}
