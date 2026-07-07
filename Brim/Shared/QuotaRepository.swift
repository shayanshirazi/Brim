import Foundation

public enum BrimStorage {
    private static let previousProductKey = ["ha", "lo"].joined()
    public static let previousApplicationSupportDirectoryName = previousProductKey.capitalized

    /// Shared container for app <-> widget state. Both targets are sandboxed with separate
    /// containers, so this group is the only storage they can both reach.
    public static let appGroupIdentifier = "7SBNT5ZG4M.dev.brim.app"

    public static func previousKey(_ suffix: String) -> String {
        "\(previousProductKey).\(suffix)"
    }
}

public enum QuotaStorageStatus: Equatable {
    case ready
    case unavailable
    case firstRun
    case corrupted
    case saveFailed
}

public struct QuotaLoadResult {
    public var state: QuotaState
    public var status: QuotaStorageStatus
}

public struct QuotaRepository {
    private struct StorageKeys {
        var accounts: String
        var selectedAccountID: String
        var isAccountTextHidden: String
        var widgetPageIndex: String
        var corruptedAccounts: String

        init(prefix: String) {
            accounts = "\(prefix).accounts.v1"
            selectedAccountID = "\(prefix).selected-account-id.v1"
            isAccountTextHidden = "\(prefix).account-text-hidden.v1"
            widgetPageIndex = "\(prefix).widget-page-index.v1"
            corruptedAccounts = "\(prefix).accounts.corrupted.v1"
        }
    }

    private static let keys = StorageKeys(prefix: "brim")
    private static let previousKeys = StorageKeys(prefix: BrimStorage.previousKey("").dropLast().description)

    public let defaults: UserDefaults
    private let previousDefaults: UserDefaults?

    public init() {
        defaults = .standard
        previousDefaults = .standard
    }

    public init(defaults: UserDefaults, previousDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        self.previousDefaults = previousDefaults
    }

    public func load() -> QuotaLoadResult {
        let result = load(from: defaults, keys: Self.keys)
        if result.status != .firstRun {
            return result
        }

        guard let previousDefaults else {
            return result
        }

        let previousResult = load(from: previousDefaults, keys: Self.previousKeys)
        if previousResult.status == .ready {
            _ = save(previousResult.state)
        }

        return previousResult.status == .firstRun ? result : previousResult
    }

    private func load(from defaults: UserDefaults, keys: StorageKeys) -> QuotaLoadResult {
        let selectedID = defaults.string(forKey: keys.selectedAccountID).flatMap(UUID.init(uuidString:))
        let isTextHidden = defaults.bool(forKey: keys.isAccountTextHidden)
        let pageIndex = max(0, defaults.integer(forKey: keys.widgetPageIndex))

        guard let data = defaults.data(forKey: keys.accounts) else {
            return QuotaLoadResult(
                state: QuotaState(
                    accounts: [],
                    selectedAccountID: nil,
                    isAccountTextHidden: isTextHidden,
                    widgetPageIndex: pageIndex
                ),
                status: .firstRun
            )
        }

        do {
            let accounts = try JSONDecoder().decode([QuotaAccount].self, from: data)
            return QuotaLoadResult(
                state: QuotaState(
                    accounts: accounts,
                    selectedAccountID: selectedID,
                    isAccountTextHidden: isTextHidden,
                    widgetPageIndex: pageIndex
                ),
                status: .ready
            )
        } catch {
            defaults.set(data, forKey: keys.corruptedAccounts)
            return QuotaLoadResult(
                state: QuotaState(
                    accounts: QuotaAccountDefaults.examples,
                    selectedAccountID: QuotaAccountDefaults.examples.first?.id,
                    isAccountTextHidden: isTextHidden,
                    widgetPageIndex: pageIndex
                ),
                status: .corrupted
            )
        }
    }

    @discardableResult
    public func save(_ state: QuotaState) -> QuotaStorageStatus {
        var normalizedState = state
        normalizedState.normalize()

        do {
            let data = try JSONEncoder().encode(normalizedState.accounts)
            defaults.set(data, forKey: Self.keys.accounts)

            if let selectedAccountID = normalizedState.selectedAccountID {
                defaults.set(selectedAccountID.uuidString, forKey: Self.keys.selectedAccountID)
            } else {
                defaults.removeObject(forKey: Self.keys.selectedAccountID)
            }

            defaults.set(normalizedState.isAccountTextHidden, forKey: Self.keys.isAccountTextHidden)
            defaults.set(normalizedState.widgetPageIndex, forKey: Self.keys.widgetPageIndex)
            return .ready
        } catch {
            return .saveFailed
        }
    }
}

public struct QuotaWidgetSnapshotStore {
    private let repository: QuotaRepository?
    private let fallbackURL: URL
    private let legacyFallbackURLs: [URL]

    public init() {
        let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let sandboxLocalURL = applicationSupportURL
            .appendingPathComponent("Brim", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
        let previousProductURL = applicationSupportURL
            .appendingPathComponent(BrimStorage.previousApplicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")

        if let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BrimStorage.appGroupIdentifier)?
            .appendingPathComponent("widget-snapshot.json") {
            fallbackURL = groupURL
            legacyFallbackURLs = [sandboxLocalURL, previousProductURL]
        } else {
            fallbackURL = sandboxLocalURL
            legacyFallbackURLs = [previousProductURL]
        }

        repository = nil
    }

    init(repository: QuotaRepository?, fallbackURL: URL, previousFallbackURL: URL? = nil) {
        self.repository = repository
        self.fallbackURL = fallbackURL
        self.legacyFallbackURLs = [
            previousFallbackURL ?? fallbackURL
                .deletingLastPathComponent()
                .appendingPathComponent("previous-widget-snapshot.json")
        ]
    }

    public func load() -> QuotaLoadResult {
        guard let repository else {
            if let fallbackResult = loadFallbackSnapshot() {
                return fallbackResult
            }

            // No shared snapshot yet (the app hasn't run). Show the real empty state
            // instead of pretending example accounts exist.
            return QuotaLoadResult(
                state: QuotaState(accounts: [], selectedAccountID: nil),
                status: .unavailable
            )
        }

        let repositoryResult = repository.load()
        guard repositoryResult.status == .firstRun else {
            return repositoryResult
        }

        guard let fallbackResult = loadFallbackSnapshot() else {
            return repositoryResult
        }

        _ = repository.save(fallbackResult.state)
        return fallbackResult
    }

    @discardableResult
    public func save(_ state: QuotaState) -> QuotaStorageStatus {
        let snapshot = state.widgetSnapshotState()

        let fallbackStatus = saveFallbackSnapshot(snapshot)

        guard let repository else {
            return fallbackStatus
        }

        let repositoryStatus = repository.save(snapshot)
        return repositoryStatus == .ready ? .ready : fallbackStatus
    }

    private func loadFallbackSnapshot() -> QuotaLoadResult? {
        if let result = loadFallbackSnapshot(from: fallbackURL) {
            return result
        }

        for legacyURL in legacyFallbackURLs {
            if let result = loadFallbackSnapshot(from: legacyURL) {
                return result
            }
        }

        return nil
    }

    private func loadFallbackSnapshot(from url: URL) -> QuotaLoadResult? {
        guard
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data)
        else {
            return nil
        }

        return QuotaLoadResult(
            state: QuotaState(
                accounts: payload.accounts,
                selectedAccountID: payload.selectedAccountID,
                isAccountTextHidden: payload.isAccountTextHidden,
                widgetPageIndex: payload.widgetPageIndex
            ),
            status: .ready
        )
    }

    private func saveFallbackSnapshot(_ state: QuotaState) -> QuotaStorageStatus {
        do {
            try FileManager.default.createDirectory(
                at: fallbackURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let payload = WidgetSnapshotPayload(
                accounts: state.accounts,
                selectedAccountID: state.selectedAccountID,
                isAccountTextHidden: state.isAccountTextHidden,
                widgetPageIndex: state.widgetPageIndex
            )
            let data = try JSONEncoder().encode(payload)

            // Skip the write (and downstream churn) when nothing changed.
            if let existing = try? Data(contentsOf: fallbackURL), existing == data {
                return .ready
            }

            try data.write(to: fallbackURL, options: [.atomic])

            // The group file is now authoritative; drop stale per-container copies
            // so they can never shadow it through the legacy read fallback.
            for legacyURL in legacyFallbackURLs where legacyURL != fallbackURL {
                try? FileManager.default.removeItem(at: legacyURL)
            }

            return .ready
        } catch {
            return .unavailable
        }
    }
}

private struct WidgetSnapshotPayload: Codable {
    var accounts: [QuotaAccount]
    var selectedAccountID: QuotaAccount.ID?
    var isAccountTextHidden: Bool
    var widgetPageIndex: Int
}
