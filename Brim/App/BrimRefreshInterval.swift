import Foundation

enum BrimRefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    static let storageKey = "brim.refresh-interval-seconds.v1"
    static let modeStorageKey = "brim.refresh-mode.v1"
    static let defaultSeconds = BrimRefreshInterval.fiveMinutes.rawValue
    static let minimumSeconds = 60
    static let maximumSeconds = 86_400

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        }
    }

    var detail: String {
        switch self {
        case .oneMinute: return "Most current"
        case .fiveMinutes: return "Balanced"
        case .fifteenMinutes: return "Quieter"
        case .thirtyMinutes: return "Lightest touch"
        }
    }

    static func normalizedSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minimumSeconds), maximumSeconds)
    }

    static func displayTitle(for seconds: Int) -> String {
        let normalizedSeconds = normalizedSeconds(seconds)
        if let preset = BrimRefreshInterval(rawValue: normalizedSeconds) {
            return preset.title
        }

        let minutes = max(1, normalizedSeconds / 60)
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) hr"
        }

        return "\(minutes) min"
    }
}
