import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

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

    public init(
        id: UUID = UUID(),
        name: String,
        colorHex: String,
        weeklyLimitMinutes: Int,
        usedMinutes: Int,
        sessionLimitMinutes: Int? = 300,
        sessionUsedMinutes: Int? = nil,
        resetWeekday: Int,
        resetHour: Int,
        resetMinute: Int,
        codexProfilePath: String? = nil
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
        max(1, sessionLimitMinutes ?? 300)
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

    public var remainingPercentText: String {
        "\(Int(round(weeklyRemainingFraction * 100)))%"
    }

    public var sessionPercentText: String {
        "\(Int(round(sessionRemainingFraction * 100)))%"
    }

    public var resetText: String {
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let weekday = weekdays[max(0, min(6, resetWeekday - 1))]
        let hour12 = resetHour % 12 == 0 ? 12 : resetHour % 12
        let minute = String(format: "%02d", resetMinute)
        let period = resetHour < 12 ? "AM" : "PM"
        return "\(weekday) \(hour12):\(minute) \(period)"
    }

    public var resolvedCodexProfilePath: String {
        codexProfilePath ?? Self.defaultCodexProfilePath(for: name)
    }

    public static func defaultCodexProfilePath(for name: String) -> String {
        let slug = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        return "$HOME/.codex-accounts/\(slug.isEmpty ? "account" : slug)"
    }

    public static let examples: [QuotaAccount] = [
        QuotaAccount(
            name: "Main",
            colorHex: "#40E06B",
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            resetWeekday: 2,
            resetHour: 0,
            resetMinute: 0,
            codexProfilePath: "$HOME/.codex-accounts/main"
        ),
        QuotaAccount(
            name: "Backup",
            colorHex: "#65D6FF",
            weeklyLimitMinutes: 300,
            usedMinutes: 42,
            resetWeekday: 2,
            resetHour: 0,
            resetMinute: 0,
            codexProfilePath: "$HOME/.codex-accounts/backup"
        )
    ]
}

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    var quotaHexString: String {
        #if os(macOS)
        let nativeColor = NSColor(self)
        guard let color = nativeColor.usingColorSpace(.sRGB) else {
            return "#40E06B"
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
        #else
        return "#40E06B"
        #endif
    }
}
