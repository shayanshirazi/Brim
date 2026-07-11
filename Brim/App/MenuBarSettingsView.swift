import SwiftUI

enum MenuBarAccountOrder: String, CaseIterable, Identifiable {
    case accountList
    case attention
    case lowestRemaining
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accountList: return "Account list"
        case .attention: return "Needs attention"
        case .lowestRemaining: return "Lowest first"
        case .name: return "Name"
        }
    }
}

enum MenuBarRowDetail: String, CaseIterable, Identifiable {
    case usage
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usage: return "Usage"
        case .status: return "Connection"
        }
    }
}

enum MenuBarIconSource: String, CaseIterable, Identifiable {
    case selectedAccount
    case firstShown
    case lowestRemaining

    var id: String { rawValue }

    var title: String {
        switch self {
        case .selectedAccount: return "Selected account"
        case .firstShown: return "First shown"
        case .lowestRemaining: return "Lowest remaining"
        }
    }
}

struct MenuBarPreferences {
    static let accountOrderKey = "brim.menu-bar.account-order.v1"
    static let rowDetailKey = "brim.menu-bar.row-detail.v1"
    static let iconSourceKey = "brim.menu-bar.icon-source.v1"
    static let hiddenAccountIDsKey = "brim.menu-bar.hidden-account-ids.v1"
    static let includesDisconnectedKey = "brim.menu-bar.includes-disconnected.v1"
    static let maximumRowsKey = "brim.menu-bar.maximum-rows.v1"
    static let defaultMaximumRows = 6

    var accountOrder: MenuBarAccountOrder
    var rowDetail: MenuBarRowDetail
    var iconSource: MenuBarIconSource
    var hiddenAccountIDs: Set<QuotaAccount.ID>
    var includesDisconnected: Bool
    var maximumRows: Int

    init(
        accountOrder: MenuBarAccountOrder = .accountList,
        rowDetail: MenuBarRowDetail = .usage,
        iconSource: MenuBarIconSource = .selectedAccount,
        hiddenAccountIDs: Set<QuotaAccount.ID> = [],
        includesDisconnected: Bool = true,
        maximumRows: Int = Self.defaultMaximumRows
    ) {
        self.accountOrder = accountOrder
        self.rowDetail = rowDetail
        self.iconSource = iconSource
        self.hiddenAccountIDs = hiddenAccountIDs
        self.includesDisconnected = includesDisconnected
        self.maximumRows = min(max(1, maximumRows), 12)
    }

    init(defaults: UserDefaults) {
        accountOrder = MenuBarAccountOrder(
            rawValue: defaults.string(forKey: Self.accountOrderKey) ?? ""
        ) ?? .accountList
        rowDetail = MenuBarRowDetail(
            rawValue: defaults.string(forKey: Self.rowDetailKey) ?? ""
        ) ?? .usage
        iconSource = MenuBarIconSource(
            rawValue: defaults.string(forKey: Self.iconSourceKey) ?? ""
        ) ?? .selectedAccount
        hiddenAccountIDs = Self.accountIDs(
            from: defaults.string(forKey: Self.hiddenAccountIDsKey) ?? ""
        )
        includesDisconnected = defaults.object(forKey: Self.includesDisconnectedKey) as? Bool ?? true
        maximumRows = min(
            max(1, defaults.object(forKey: Self.maximumRowsKey) as? Int ?? Self.defaultMaximumRows),
            12
        )
    }

    func eligibleAccounts(from accounts: [QuotaAccount]) -> [QuotaAccount] {
        accounts.filter { account in
            !hiddenAccountIDs.contains(account.id)
                && (includesDisconnected || account.signalState != .notConnected)
        }
    }

    func visibleAccounts(from accounts: [QuotaAccount]) -> [QuotaAccount] {
        Array(sortedAccounts(eligibleAccounts(from: accounts)).prefix(maximumRows))
    }

    func iconAccount(
        from accounts: [QuotaAccount],
        selectedAccountID: QuotaAccount.ID?
    ) -> QuotaAccount? {
        let visibleAccounts = visibleAccounts(from: accounts)
        switch iconSource {
        case .selectedAccount:
            return visibleAccounts.first(where: { $0.id == selectedAccountID }) ?? visibleAccounts.first
        case .firstShown:
            return visibleAccounts.first
        case .lowestRemaining:
            return visibleAccounts
                .filter(\.hasUsageSnapshot)
                .min(by: { $0.sessionRemainingFraction < $1.sessionRemainingFraction })
                ?? visibleAccounts.first
        }
    }

    func rowTitle(for account: QuotaAccount) -> String {
        let detail: String
        switch rowDetail {
        case .usage:
            detail = account.usageSummaryText
        case .status:
            detail = account.signalState.title.lowercased()
        }
        return "\(account.name): \(detail)"
    }

    static func encodedAccountIDs(_ accountIDs: Set<QuotaAccount.ID>) -> String {
        accountIDs
            .map { $0.uuidString.lowercased() }
            .sorted()
            .joined(separator: ",")
    }

    static func accountIDs(from encodedValue: String) -> Set<QuotaAccount.ID> {
        Set(encodedValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private func sortedAccounts(_ accounts: [QuotaAccount]) -> [QuotaAccount] {
        switch accountOrder {
        case .accountList:
            return accounts
        case .name:
            return accounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lowestRemaining:
            return accounts.enumerated().sorted { left, right in
                let leftValue = remainingSortValue(left.element)
                let rightValue = remainingSortValue(right.element)
                return leftValue == rightValue ? left.offset < right.offset : leftValue < rightValue
            }.map(\.element)
        case .attention:
            return accounts.enumerated().sorted { left, right in
                let leftRank = attentionRank(left.element)
                let rightRank = attentionRank(right.element)
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                let leftRemaining = remainingSortValue(left.element)
                let rightRemaining = remainingSortValue(right.element)
                return leftRemaining == rightRemaining
                    ? left.offset < right.offset
                    : leftRemaining < rightRemaining
            }.map(\.element)
        }
    }

    private func remainingSortValue(_ account: QuotaAccount) -> Double {
        account.hasUsageSnapshot ? account.sessionRemainingFraction : 2
    }

    private func attentionRank(_ account: QuotaAccount) -> Int {
        switch account.signalState {
        case .exhausted: return 0
        case .refreshFailed: return 1
        case .notConnected: return 2
        case .waitingForQuotaSource: return 3
        case .ready: return 4
        case .manual, .dashboardOnly: return 5
        }
    }
}

struct MenuBarSettingsTab: View {
    @EnvironmentObject private var store: QuotaStore
    @AppStorage(MenuBarPreferences.accountOrderKey) private var accountOrderRaw = MenuBarAccountOrder.accountList.rawValue
    @AppStorage(MenuBarPreferences.rowDetailKey) private var rowDetailRaw = MenuBarRowDetail.usage.rawValue
    @AppStorage(MenuBarPreferences.iconSourceKey) private var iconSourceRaw = MenuBarIconSource.selectedAccount.rawValue
    @AppStorage(MenuBarPreferences.hiddenAccountIDsKey) private var hiddenAccountIDsRaw = ""
    @AppStorage(MenuBarPreferences.includesDisconnectedKey) private var includesDisconnected = true
    @AppStorage(MenuBarPreferences.maximumRowsKey) private var maximumRows = MenuBarPreferences.defaultMaximumRows

    private var accountOrder: Binding<MenuBarAccountOrder> {
        Binding(
            get: { MenuBarAccountOrder(rawValue: accountOrderRaw) ?? .accountList },
            set: { accountOrderRaw = $0.rawValue }
        )
    }

    private var rowDetail: Binding<MenuBarRowDetail> {
        Binding(
            get: { MenuBarRowDetail(rawValue: rowDetailRaw) ?? .usage },
            set: { rowDetailRaw = $0.rawValue }
        )
    }

    private var iconSource: Binding<MenuBarIconSource> {
        Binding(
            get: { MenuBarIconSource(rawValue: iconSourceRaw) ?? .selectedAccount },
            set: { iconSourceRaw = $0.rawValue }
        )
    }

    private var preferences: MenuBarPreferences {
        MenuBarPreferences(
            accountOrder: accountOrder.wrappedValue,
            rowDetail: rowDetail.wrappedValue,
            iconSource: iconSource.wrappedValue,
            hiddenAccountIDs: MenuBarPreferences.accountIDs(from: hiddenAccountIDsRaw),
            includesDisconnected: includesDisconnected,
            maximumRows: maximumRows
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsPanelHeader(
                icon: "menubar.rectangle",
                title: "Menu bar",
                subtitle: "Choose what Brim shows at a glance and what rises to the top."
            )

            MenuBarPreview(accounts: preferences.visibleAccounts(from: store.accounts), preferences: preferences)

            HStack(alignment: .top, spacing: 10) {
                MenuBarChoiceCard(
                    icon: "arrow.up.arrow.down",
                    title: "Account order",
                    detail: "Keep your list order or sort the menu automatically."
                ) {
                    Picker("Account order", selection: accountOrder) {
                        ForEach(MenuBarAccountOrder.allCases) { order in
                            Text(order.title).tag(order)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }

                MenuBarChoiceCard(
                    icon: "circle.dotted",
                    title: "Status ring",
                    detail: "Choose which visible account drives the menu-bar ring."
                ) {
                    Picker("Status ring", selection: iconSource) {
                        ForEach(MenuBarIconSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                MenuBarChoiceCard(
                    icon: "text.alignleft",
                    title: "Row detail",
                    detail: "Show quota percentages or connection state."
                ) {
                    Picker("Row detail", selection: rowDetail) {
                        ForEach(MenuBarRowDetail.allCases) { detail in
                            Text(detail.title).tag(detail)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                MenuBarChoiceCard(
                    icon: "list.number",
                    title: "Maximum rows",
                    detail: "Keep the menu compact when you have many accounts."
                ) {
                    Stepper(value: $maximumRows, in: 1...12) {
                        Text("\(maximumRows)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(width: 22)
                    }
                    .labelsHidden()
                }
            }

            MenuBarAccountPicker(
                accounts: store.accounts,
                includesDisconnected: $includesDisconnected,
                isAccountVisible: isAccountVisible,
                setAccountVisible: setAccountVisible
            )

            Spacer(minLength: 0)
        }
        .panelStyle(insets: 14)
    }

    private func isAccountVisible(_ accountID: QuotaAccount.ID) -> Bool {
        !MenuBarPreferences.accountIDs(from: hiddenAccountIDsRaw).contains(accountID)
    }

    private func setAccountVisible(_ accountID: QuotaAccount.ID, isVisible: Bool) {
        var hiddenAccountIDs = MenuBarPreferences.accountIDs(from: hiddenAccountIDsRaw)
        if isVisible {
            hiddenAccountIDs.remove(accountID)
        } else {
            hiddenAccountIDs.insert(accountID)
        }
        hiddenAccountIDsRaw = MenuBarPreferences.encodedAccountIDs(hiddenAccountIDs)
    }
}

private struct MenuBarPreview: View {
    var accounts: [QuotaAccount]
    var preferences: MenuBarPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live menu preview", systemImage: "circle.fill")
                    .labelStyle(MenuBarPreviewLabelStyle())
                Spacer()
                Text("\(accounts.count) SHOWN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                if accounts.isEmpty {
                    Text("No accounts match these settings")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                } else {
                    ForEach(accounts.prefix(3)) { account in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(Color(hex: account.colorHex))
                                .frame(width: 7, height: 7)
                            Text(preferences.rowTitle(for: account))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Spacer()
                            if account.id == accounts.first?.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color(hex: "#2CCB68"))
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 30)

                        if account.id != accounts.prefix(3).last?.id {
                            Divider().padding(.leading, 28)
                        }
                    }
                }
            }
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(12)
        .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(hex: "#2CCB68").opacity(0.16), lineWidth: 1)
        }
    }
}

private struct MenuBarPreviewLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(Color(hex: "#2CCB68"))
            configuration.title
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
    }
}

private struct MenuBarChoiceCard<Control: View>: View {
    var icon: String
    var title: String
    var detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))
                .frame(width: 30, height: 30)
                .background(Color(hex: "#2CCB68").opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 1)
        }
    }
}

private struct MenuBarAccountPicker: View {
    var accounts: [QuotaAccount]
    @Binding var includesDisconnected: Bool
    var isAccountVisible: (QuotaAccount.ID) -> Bool
    var setAccountVisible: (QuotaAccount.ID, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2CCB68"))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: "#2CCB68").opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accounts shown")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text("Hide noise without removing an account from Brim.")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("Include disconnected", isOn: $includesDisconnected)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(11)

            Divider().padding(.horizontal, 10)

            if accounts.isEmpty {
                Text("Add an account to configure the menu.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    ForEach(accounts) { account in
                        Toggle(isOn: Binding(
                            get: { isAccountVisible(account.id) },
                            set: { setAccountVisible(account.id, $0) }
                        )) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Color(hex: account.colorHex))
                                    .frame(width: 7, height: 7)
                                Text(account.name)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 1)
        }
    }
}
