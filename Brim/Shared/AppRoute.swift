import Foundation

public enum AppRoute: Equatable {
    case accounts

    public static func parse(_ url: URL) -> AppRoute? {
        guard url.scheme == "brim" else {
            return nil
        }

        if url.host == "accounts" || url.path == "/accounts" {
            return .accounts
        }

        return nil
    }

    public var urlString: String {
        switch self {
        case .accounts:
            return "brim://accounts"
        }
    }
}
