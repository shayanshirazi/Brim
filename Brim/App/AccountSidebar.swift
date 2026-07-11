import SwiftUI
import UniformTypeIdentifiers

struct AccountSidebar: View {
    var accounts: [QuotaAccount]
    @Binding var selectedAccountID: QuotaAccount.ID?
    var addAccount: () -> Void
    var removeAccount: (QuotaAccount.ID) -> Void
    var moveAccounts: (IndexSet, Int) -> Void
    var renameAccount: (QuotaAccount.ID, String) -> Void
    var selectAccount: (QuotaAccount.ID) -> Void
    var isSettingsSelected: Bool = false
    var openSettings: () -> Void = {}
    var refreshAllAccounts: () -> Void = {}
    var isRefreshingAll: Bool = false

    @State private var draggingAccountID: QuotaAccount.ID?
    @State private var dropTargetAccountID: QuotaAccount.ID?
    @State private var renamingAccountID: QuotaAccount.ID?
    @State private var accountPendingRemoval: QuotaAccount?
    @State private var draftName = ""
    @State private var prioritizesAvailableUsage = false

    private var displayedAccounts: [QuotaAccount] {
        guard prioritizesAvailableUsage else {
            return accounts
        }

        return accounts.enumerated().sorted { lhs, rhs in
            if AccountUsagePriority.areInIncreasingOrder(lhs.element, rhs.element) {
                return true
            }

            if AccountUsagePriority.areInIncreasingOrder(rhs.element, lhs.element) {
                return false
            }

            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: 12) {
                    BrimLogoMark(size: 38)

                    HStack(alignment: .top, spacing: 5) {
                        Text("Brim")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)

                        BrimVersionBadge()
                            .padding(.top, 2)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            prioritizesAvailableUsage.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                prioritizesAvailableUsage
                                    ? Color(hex: "#22C55E")
                                    : .primary.opacity(0.68)
                            )
                            .frame(width: 26, height: 26)
                            .background(
                                prioritizesAvailableUsage
                                    ? Color(hex: "#22C55E").opacity(0.10)
                                    : Color.primary.opacity(0.045),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .help(prioritizesAvailableUsage ? "Use custom account order" : "Prioritize available usage")
                    .accessibilityLabel("Prioritize available usage")
                    .accessibilityValue(prioritizesAvailableUsage ? "On" : "Off")

                    Button(action: refreshAllAccounts) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.68))
                            .rotationEffect(.degrees(isRefreshingAll ? 360 : 0))
                            .animation(
                                isRefreshingAll
                                    ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                                    : .default,
                                value: isRefreshingAll
                            )
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.045), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingAll)
                    .help("Refresh all accounts")

                    Button(action: addAccount) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.68))
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.045), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Add account")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 2)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(displayedAccounts) { account in
                        accountRow(for: account)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: displayedAccounts.map(\.id))
            }

            SidebarSettingsButton(
                isSelected: isSettingsSelected,
                action: openSettings
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.82),
                    Color(hex: "#EEF7F6").opacity(0.54)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .alert(
            "Delete \(accountPendingRemoval?.name ?? "account")?",
            isPresented: removalConfirmationBinding,
            presenting: accountPendingRemoval
        ) { account in
            Button("Delete account", role: .destructive) {
                confirmRemoval(of: account)
            }

            Button("Cancel", role: .cancel) {
                accountPendingRemoval = nil
            }
        } message: { account in
            Text("This removes \(account.name) from Brim, including its private login profile or saved API key on this Mac.")
        }
    }

    private var removalConfirmationBinding: Binding<Bool> {
        Binding(
            get: { accountPendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    accountPendingRemoval = nil
                }
            }
        )
    }

    private func requestRemoval(of account: QuotaAccount) {
        accountPendingRemoval = account
    }

    @ViewBuilder
    private func accountRow(for account: QuotaAccount) -> some View {
        let row = AccountSidebarRow(
            account: account,
            isSelected: selectedAccountID == account.id,
            isDragging: draggingAccountID == account.id,
            isDropTarget: dropTargetAccountID == account.id && draggingAccountID != account.id,
            isRenaming: renamingAccountID == account.id,
            draftName: $draftName,
            selectAccount: {
                selectAccount(account.id)
            },
            beginRename: {
                selectAccount(account.id)
                renamingAccountID = account.id
                draftName = account.name
            },
            commitRename: {
                commitRename(for: account.id)
            },
            removeAccount: {
                requestRemoval(of: account)
            }
        )

        if prioritizesAvailableUsage {
            row
        } else {
            row
                .onDrag {
                    withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.84)) {
                        draggingAccountID = account.id
                        dropTargetAccountID = nil
                    }
                    selectAccount(account.id)
                    return NSItemProvider(object: account.id.uuidString as NSString)
                } preview: {
                    AccountSidebarDragPreview(account: account)
                }
                .onDrop(
                    of: [UTType.text],
                    delegate: AccountSidebarDropDelegate(
                        targetAccount: account,
                        accounts: accounts,
                        draggingAccountID: $draggingAccountID,
                        dropTargetAccountID: $dropTargetAccountID,
                        moveAccounts: moveAccounts
                    )
                )
        }
    }

    private func confirmRemoval(of account: QuotaAccount) {
        removeAccount(account.id)
        accountPendingRemoval = nil
    }

    private func commitRename(for accountID: QuotaAccount.ID) {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            renameAccount(accountID, trimmedName)
        }

        renamingAccountID = nil
        draftName = ""
    }
}

enum AccountUsagePriority {
    static func areInIncreasingOrder(_ lhs: QuotaAccount, _ rhs: QuotaAccount) -> Bool {
        let lhsRank = availabilityRank(for: lhs)
        let rhsRank = availabilityRank(for: rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        if lhsRank == 0 {
            if lhs.sessionRemainingFraction != rhs.sessionRemainingFraction {
                return lhs.sessionRemainingFraction > rhs.sessionRemainingFraction
            }

            if lhs.weeklyRemainingFraction != rhs.weeklyRemainingFraction {
                return lhs.weeklyRemainingFraction > rhs.weeklyRemainingFraction
            }
        }

        return false
    }

    private static func availabilityRank(for account: QuotaAccount) -> Int {
        switch account.signalState {
        case .ready:
            return account.hasUsageSnapshot ? 0 : 2
        case .exhausted:
            return 1
        case .waitingForQuotaSource, .refreshFailed, .manual, .dashboardOnly:
            return 2
        case .notConnected:
            return 3
        }
    }
}

private struct SidebarSettingsButton: View {
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                SettingsGearMark(size: 32, isSelected: isSelected)

                Text("Settings")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                isSelected ? Color.primary.opacity(0.075) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help("Open settings")
    }
}

private struct AccountSidebarRow: View {
    var account: QuotaAccount
    var isSelected: Bool
    var isDragging: Bool
    var isDropTarget: Bool
    var isRenaming: Bool
    @Binding var draftName: String
    var selectAccount: () -> Void
    var beginRename: () -> Void
    var commitRename: () -> Void
    var removeAccount: () -> Void

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 11) {
            Button(action: selectAccount) {
                HStack(spacing: 11) {
                    QuotaRingView(account: account, diameter: 32, lineWidth: 4, showPercent: false)

                    VStack(alignment: .leading, spacing: 2) {
                        if isRenaming {
                            TextField("Account name", text: $draftName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                                .focused($isNameFieldFocused)
                                .onSubmit(commitRename)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Color(nsColor: .textBackgroundColor).opacity(0.86),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                )
                        } else {
                            HStack(spacing: 6) {
                                ProviderLogoMark(provider: account.provider, size: 18)

                                Text(account.name)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                            }
                        }

                        Text(account.usageSummaryText)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .blur(radius: account.refreshStatus.hidesQuotaDetails ? 2.6 : 0)
                            .saturation(account.refreshStatus.hidesQuotaDetails ? 0.18 : 1)
                            .opacity(account.refreshStatus.hidesQuotaDetails ? 0.54 : 1)
                            .animation(.snappy(duration: 0.18), value: account.refreshStatus.hidesQuotaDetails)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select \(account.name)")

            Button(action: removeAccount) {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Remove \(account.name)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rowStroke, lineWidth: isDropTarget ? 1.2 : 0)
        }
        .scaleEffect(isDragging ? 0.985 : 1)
        .opacity(isDragging ? 0.32 : 1)
        .shadow(
            color: isDropTarget ? Color(hex: account.colorHex).opacity(0.14) : Color.clear,
            radius: isDropTarget ? 10 : 0,
            y: isDropTarget ? 4 : 0
        )
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.88), value: isDragging)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.88), value: isDropTarget)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button(action: beginRename) {
                Label("Edit Name", systemImage: "pencil")
            }

            Button(role: .destructive, action: removeAccount) {
                Label("Delete Account", systemImage: "trash")
            }
        }
        .onChange(of: isRenaming) { _, newValue in
            guard newValue else {
                return
            }

            DispatchQueue.main.async {
                isNameFieldFocused = true
            }
        }
        .onChange(of: isNameFieldFocused) { oldValue, newValue in
            if oldValue, !newValue, isRenaming {
                commitRename()
            }
        }
    }

    private var rowBackground: Color {
        if isDropTarget {
            return Color(hex: account.colorHex).opacity(0.085)
        }

        return isSelected ? Color.primary.opacity(0.075) : Color.clear
    }

    private var rowStroke: Color {
        isDropTarget ? Color(hex: account.colorHex).opacity(0.22) : Color.clear
    }
}

private struct AccountSidebarDragPreview: View {
    var account: QuotaAccount

    var body: some View {
        HStack(spacing: 11) {
            QuotaRingView(account: account, diameter: 32, lineWidth: 4, showPercent: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(account.usageSummaryText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 190, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(hex: account.colorHex).opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 16, y: 8)
    }
}

private struct AccountSidebarDropDelegate: DropDelegate {
    var targetAccount: QuotaAccount
    var accounts: [QuotaAccount]
    @Binding var draggingAccountID: QuotaAccount.ID?
    @Binding var dropTargetAccountID: QuotaAccount.ID?
    var moveAccounts: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggingAccountID,
            draggingAccountID != targetAccount.id,
            let fromIndex = accounts.firstIndex(where: { $0.id == draggingAccountID }),
            let toIndex = accounts.firstIndex(where: { $0.id == targetAccount.id })
        else {
            return
        }

        dropTargetAccountID = targetAccount.id
        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            moveAccounts(IndexSet(integer: fromIndex), destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetAccountID == targetAccount.id {
            dropTargetAccountID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.9)) {
            draggingAccountID = nil
            dropTargetAccountID = nil
        }
        return true
    }
}
