import Foundation

public enum HaloStorage {
    public static let widgetSnapshotAppGroup = "group.dev.halo"
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
    private static let accountsKey = "halo.accounts.v1"
    private static let selectedAccountIDKey = "halo.selected-account-id.v1"
    private static let isAccountTextHiddenKey = "halo.account-text-hidden.v1"
    private static let widgetPageIndexKey = "halo.widget-page-index.v1"
    private static let corruptedAccountsKey = "halo.accounts.corrupted.v1"

    public let defaults: UserDefaults

    public init() {
        defaults = .standard
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func load() -> QuotaLoadResult {
        let selectedID = defaults.string(forKey: Self.selectedAccountIDKey).flatMap(UUID.init(uuidString:))
        let isTextHidden = defaults.bool(forKey: Self.isAccountTextHiddenKey)
        let pageIndex = max(0, defaults.integer(forKey: Self.widgetPageIndexKey))

        guard let data = defaults.data(forKey: Self.accountsKey) else {
            return QuotaLoadResult(
                state: QuotaState(
                    accounts: QuotaAccountDefaults.examples,
                    selectedAccountID: QuotaAccountDefaults.examples.first?.id,
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
            defaults.set(data, forKey: Self.corruptedAccountsKey)
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
            defaults.set(data, forKey: Self.accountsKey)

            if let selectedAccountID = normalizedState.selectedAccountID {
                defaults.set(selectedAccountID.uuidString, forKey: Self.selectedAccountIDKey)
            } else {
                defaults.removeObject(forKey: Self.selectedAccountIDKey)
            }

            defaults.set(normalizedState.isAccountTextHidden, forKey: Self.isAccountTextHiddenKey)
            defaults.set(normalizedState.widgetPageIndex, forKey: Self.widgetPageIndexKey)
            return .ready
        } catch {
            return .saveFailed
        }
    }
}

public struct QuotaWidgetSnapshotStore {
    private let repository: QuotaRepository?

    public init() {
        guard let defaults = UserDefaults(suiteName: HaloStorage.widgetSnapshotAppGroup) else {
            repository = nil
            return
        }

        repository = QuotaRepository(defaults: defaults)
    }

    public func load() -> QuotaLoadResult {
        guard let repository else {
            return QuotaLoadResult(
                state: QuotaState(
                    accounts: QuotaAccountDefaults.examples,
                    selectedAccountID: QuotaAccountDefaults.examples.first?.id
                ),
                status: .unavailable
            )
        }

        return repository.load()
    }

    @discardableResult
    public func save(_ state: QuotaState) -> QuotaStorageStatus {
        guard let repository else {
            return .unavailable
        }

        var snapshot = state
        snapshot.accounts = snapshot.accounts.map { account in
            var account = account
            account.codexProfilePath = nil
            account.credentialID = nil
            return account
        }
        snapshot.normalize()

        return repository.save(snapshot)
    }
}
