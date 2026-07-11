import Foundation

public enum AppRoute: Equatable {
    case accounts
    case account(UUID)
    case menuBarSettings

    public static func parse(_ url: URL) -> AppRoute? {
        guard url.scheme == "brim" else {
            return nil
        }

        if url.host == "settings", url.path == "/menu-bar" || url.path == "/widget" {
            return .menuBarSettings
        }

        guard url.host == "accounts" || url.path == "/accounts" else {
            return nil
        }

        let identifier = url.pathComponents.first(where: { $0 != "/" && $0 != "accounts" })
        if let identifier, let accountID = UUID(uuidString: identifier) {
            return .account(accountID)
        }

        return .accounts
    }

    public var urlString: String {
        switch self {
        case .accounts:
            return "brim://accounts"
        case .account(let accountID):
            return "brim://accounts/\(accountID.uuidString)"
        case .menuBarSettings:
            return "brim://settings/menu-bar"
        }
    }
}
