import Foundation

public struct QuotaState: Equatable {
    public var accounts: [QuotaAccount]
    public var selectedAccountID: QuotaAccount.ID?

    public init(
        accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID? = nil
    ) {
        self.accounts = accounts
        self.selectedAccountID = selectedAccountID
        normalize()
    }

    public var selectedAccount: QuotaAccount? {
        accounts.first(where: { $0.id == selectedAccountID }) ?? accounts.first
    }

    public mutating func addAccount(
        provider: QuotaProviderKind = .codex,
        connectionKind: QuotaConnectionKind = .login
    ) {
        let account = QuotaAccountDefaults.newAccount(
            index: accounts.count + 1,
            provider: provider,
            connectionKind: connectionKind,
            existingColorHexes: accounts.map(\.colorHex)
        )
        accounts.append(account)
        selectedAccountID = account.id
        normalize()
    }

    public mutating func removeAccounts(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where accounts.indices.contains(index) {
            accounts.remove(at: index)
        }
        normalize()
    }

    public mutating func moveAccounts(
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) {
        let sourceIndexes = source.sorted().filter { accounts.indices.contains($0) }
        guard !sourceIndexes.isEmpty else {
            return
        }

        let movingAccounts = sourceIndexes.map { accounts[$0] }
        for index in sourceIndexes.reversed() {
            accounts.remove(at: index)
        }

        let removedBeforeDestination = sourceIndexes.filter { $0 < destination }.count
        let insertionIndex = min(max(0, destination - removedBeforeDestination), accounts.count)
        accounts.insert(contentsOf: movingAccounts, at: insertionIndex)
        normalize()
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

    public mutating func resetSeedData() {
        accounts = QuotaAccountDefaults.examples
        selectedAccountID = accounts.first?.id
        normalize()
    }

    public mutating func normalize() {
        accounts = accounts.map { $0.normalizedForStorage() }

        if let selectedAccountID, accounts.contains(where: { $0.id == selectedAccountID }) {
            self.selectedAccountID = selectedAccountID
        } else {
            selectedAccountID = accounts.first?.id
        }
    }
}

public extension QuotaAccount {
    func normalizedForStorage() -> QuotaAccount {
        var account = self
        let trimmedProviderAccountID = account.providerAccountID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        account.providerAccountID = trimmedProviderAccountID.isEmpty ? nil : trimmedProviderAccountID
        let trimmedEmail = account.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        account.accountEmail = trimmedEmail.isEmpty ? nil : trimmedEmail
        account.colorHex = QuotaColor.normalizedHex(colorHex) ?? QuotaColor.fallbackHex
        account.weeklyLimitMinutes = max(QuotaAccountDefaults.minimumLimitMinutes, weeklyLimitMinutes)
        account.usedMinutes = min(max(0, usedMinutes), account.weeklyLimitMinutes)
        account.sessionLimitMinutes = max(QuotaAccountDefaults.minimumLimitMinutes, sessionLimit)
        account.sessionUsedMinutes = min(max(0, sessionUsed), account.sessionLimit)
        account.weeklyUsedPercent = account.weeklyUsedPercent.map { min(100, max(0, $0)) }
        account.sessionUsedPercent = account.sessionUsedPercent.map { min(100, max(0, $0)) }
        account.hasUsageSnapshot = account.connectionKind == .manual ? true : account.hasUsageSnapshot
        if account.provider.usesProviderDashboard, account.connectionKind != .manual {
            account.connectionKind = .login
            account.providerAccountID = nil
            account.accountEmail = nil
            account.credentialID = nil
            account.providerProfilePath = nil
            account.hasUsageSnapshot = false
            account.weeklyUsedPercent = nil
            account.sessionUsedPercent = nil
            account.sessionResetAt = nil
            account.weeklyResetAt = nil
            account.refreshStatus = .dashboardOnly
            account.refreshMessage = "Usage stays in \(account.provider.displayName). Open its dashboard to verify it."
        }
        account.resetWeekday = min(max(1, resetWeekday), 7)
        account.resetHour = min(max(0, resetHour), 23)
        account.resetMinute = min(max(0, resetMinute), 59)
        return account
    }
}
