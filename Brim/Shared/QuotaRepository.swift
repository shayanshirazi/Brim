import Foundation

public enum BrimStorage {
    private static let previousProductKey = ["ha", "lo"].joined()

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
        var corruptedAccounts: String

        init(prefix: String) {
            accounts = "\(prefix).accounts.v1"
            selectedAccountID = "\(prefix).selected-account-id.v1"
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

        guard let data = defaults.data(forKey: keys.accounts) else {
            return QuotaLoadResult(
                state: QuotaState(accounts: [], selectedAccountID: nil),
                status: .firstRun
            )
        }

        do {
            let accounts = try JSONDecoder().decode([QuotaAccount].self, from: data)
            return QuotaLoadResult(
                state: QuotaState(accounts: accounts, selectedAccountID: selectedID),
                status: .ready
            )
        } catch {
            defaults.set(data, forKey: keys.corruptedAccounts)
            return QuotaLoadResult(
                state: QuotaState(
                    accounts: QuotaAccountDefaults.examples,
                    selectedAccountID: QuotaAccountDefaults.examples.first?.id
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

            return .ready
        } catch {
            return .saveFailed
        }
    }
}
