import Foundation
import Combine
import WidgetKit

public final class QuotaStore: ObservableObject {
    public static let appGroupID = "group.dev.halo.shared"

    private static let accountsKey = "halo.accounts.v1"
    private static let selectedAccountIDKey = "halo.selected-account-id.v1"
    private static let isAccountTextHiddenKey = "halo.account-text-hidden.v1"
    private static let widgetPageIndexKey = "halo.widget-page-index.v1"
    private let defaults: UserDefaults
    public let isUsingSharedDefaults: Bool

    @Published public private(set) var accounts: [QuotaAccount]

    public init() {
        if let sharedDefaults = UserDefaults(suiteName: Self.appGroupID) {
            defaults = sharedDefaults
            isUsingSharedDefaults = true
        } else {
            defaults = .standard
            isUsingSharedDefaults = false
        }
        accounts = Self.loadAccounts(from: defaults)
    }

    public func addAccount() {
        let palette = ["#40E06B", "#65D6FF", "#F7C948", "#FF7A90", "#B49BFF"]
        let nextIndex = accounts.count + 1
        let account = QuotaAccount(
            name: "Account \(nextIndex)",
            colorHex: palette[nextIndex % palette.count],
            weeklyLimitMinutes: 300,
            usedMinutes: 0,
            sessionLimitMinutes: 300,
            sessionUsedMinutes: 0,
            resetWeekday: 2,
            resetHour: 0,
            resetMinute: 0,
            codexProfilePath: "$HOME/.codex-accounts/account-\(nextIndex)"
        )
        accounts.append(account)
        persist()
    }

    public func removeAccounts(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            accounts.remove(at: index)
        }
        persist()
    }

    public func updateAccount(_ account: QuotaAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }
        accounts[index] = account
        persist()
    }

    public func resetSeedData() {
        accounts = QuotaAccount.examples
        Self.setSelectedAccountID(accounts.first?.id)
        persist()
    }

    public static func widgetSnapshot() -> [QuotaAccount] {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        return loadAccounts(from: defaults)
    }

    public static func selectedAccountID() -> UUID? {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        guard let rawID = defaults.string(forKey: selectedAccountIDKey) else {
            return nil
        }
        return UUID(uuidString: rawID)
    }

    public static func setSelectedAccountID(_ accountID: UUID?) {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        if let accountID {
            defaults.set(accountID.uuidString, forKey: selectedAccountIDKey)
        } else {
            defaults.removeObject(forKey: selectedAccountIDKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    public static func isAccountTextHidden() -> Bool {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        return defaults.bool(forKey: isAccountTextHiddenKey)
    }

    public static func setAccountTextHidden(_ isHidden: Bool) {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.set(isHidden, forKey: isAccountTextHiddenKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    public static func toggleAccountTextHidden() {
        setAccountTextHidden(!isAccountTextHidden())
    }

    public static func widgetPageIndex() -> Int {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        return max(0, defaults.integer(forKey: widgetPageIndexKey))
    }

    public static func setWidgetPageIndex(_ pageIndex: Int) {
        let defaults = UserDefaults(suiteName: appGroupID) ?? .standard
        defaults.set(max(0, pageIndex), forKey: widgetPageIndexKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    public static func moveWidgetPage(by offset: Int, accountCount: Int, pageSize: Int) {
        guard accountCount > pageSize, pageSize > 0 else {
            setWidgetPageIndex(0)
            return
        }

        let maxPageIndex = max(0, Int(ceil(Double(accountCount) / Double(pageSize))) - 1)
        let nextPageIndex = min(max(0, widgetPageIndex() + offset), maxPageIndex)
        setWidgetPageIndex(nextPageIndex)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(accounts) else {
            return
        }
        defaults.set(data, forKey: Self.accountsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private static func loadAccounts(from defaults: UserDefaults) -> [QuotaAccount] {
        guard
            let data = defaults.data(forKey: accountsKey),
            let accounts = try? JSONDecoder().decode([QuotaAccount].self, from: data)
        else {
            return QuotaAccount.examples
        }
        return accounts
    }
}
