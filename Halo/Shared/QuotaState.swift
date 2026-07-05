import Foundation

public struct QuotaState: Equatable {
    public var accounts: [QuotaAccount]
    public var selectedAccountID: QuotaAccount.ID?
    public var isAccountTextHidden: Bool
    public var widgetPageIndex: Int

    public init(
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID? = nil,
        isAccountTextHidden: Bool = false,
        widgetPageIndex: Int = 0
    ) {
        self.accounts = accounts
        self.selectedAccountID = selectedAccountID
        self.isAccountTextHidden = isAccountTextHidden
        self.widgetPageIndex = widgetPageIndex
        normalize()
    }

    public var selectedAccount: QuotaAccount? {
        accounts.first(where: { $0.id == selectedAccountID }) ?? accounts.first
    }

    public mutating func addAccount(connectionKind: QuotaConnectionKind = .codexLogin) {
        let account = QuotaAccountDefaults.newAccount(index: accounts.count + 1, connectionKind: connectionKind)
        accounts.append(account)
        selectedAccountID = account.id
        normalize()
    }

    public mutating func removeAccounts(at offsets: IndexSet, pageSize: Int = QuotaAccountDefaults.mediumWidgetSlotCount) {
        for index in offsets.sorted(by: >) where accounts.indices.contains(index) {
            accounts.remove(at: index)
        }
        normalize(pageSize: pageSize)
    }

    public mutating func updateAccount(_ account: QuotaAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }
        accounts[index] = account.normalizedForStorage()
        normalize()
    }

    public mutating func selectAccount(id: QuotaAccount.ID?) {
        selectedAccountID = id
        normalize()
    }

    public mutating func setWidgetPageIndex(_ pageIndex: Int, pageSize: Int) {
        widgetPageIndex = pageIndex
        normalize(pageSize: pageSize)
    }

    public mutating func moveWidgetPage(by offset: Int, pageSize: Int) {
        setWidgetPageIndex(widgetPageIndex + offset, pageSize: pageSize)
    }

    public mutating func setAccountTextHidden(_ isHidden: Bool) {
        isAccountTextHidden = isHidden
    }

    public mutating func toggleAccountTextHidden() {
        isAccountTextHidden.toggle()
    }

    public mutating func resetSeedData() {
        accounts = QuotaAccountDefaults.examples
        selectedAccountID = accounts.first?.id
        isAccountTextHidden = false
        widgetPageIndex = 0
        normalize()
    }

    public mutating func normalize(pageSize: Int = QuotaAccountDefaults.mediumWidgetSlotCount) {
        accounts = accounts.map { $0.normalizedForStorage() }

        if let selectedAccountID, accounts.contains(where: { $0.id == selectedAccountID }) {
            self.selectedAccountID = selectedAccountID
        } else {
            selectedAccountID = accounts.first?.id
        }

        let safePageSize = max(1, pageSize)
        let maxPageIndex = max(0, Int(ceil(Double(accounts.count) / Double(safePageSize))) - 1)
        widgetPageIndex = min(max(0, widgetPageIndex), maxPageIndex)
    }
}

public extension QuotaAccount {
    func normalizedForStorage() -> QuotaAccount {
        var account = self
        account.colorHex = QuotaColor.normalizedHex(colorHex) ?? QuotaColor.fallbackHex
        account.weeklyLimitMinutes = max(QuotaAccountDefaults.minimumLimitMinutes, weeklyLimitMinutes)
        account.usedMinutes = min(max(0, usedMinutes), account.weeklyLimitMinutes)
        account.sessionLimitMinutes = max(QuotaAccountDefaults.minimumLimitMinutes, sessionLimit)
        account.sessionUsedMinutes = min(max(0, sessionUsed), account.sessionLimit)
        account.resetWeekday = min(max(1, resetWeekday), 7)
        account.resetHour = min(max(0, resetHour), 23)
        account.resetMinute = min(max(0, resetMinute), 59)
        return account
    }
}
