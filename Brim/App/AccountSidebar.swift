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

    @State private var draggingAccountID: QuotaAccount.ID?
    @State private var renamingAccountID: QuotaAccount.ID?
    @State private var draftName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                HStack(spacing: 12) {
                    BrimLogoMark(size: 38)

                    Text("Brim")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }

                Spacer()

                Button(action: addAccount) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.76))
                        .frame(width: 36, height: 36)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Add account")
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 2)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(accounts) { account in
                        AccountSidebarRow(
                            account: account,
                            isSelected: selectedAccountID == account.id,
                            isDragging: draggingAccountID == account.id,
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
                                removeAccount(account.id)
                            }
                        )
                        .onDrag {
                            draggingAccountID = account.id
                            return NSItemProvider(object: account.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: AccountSidebarDropDelegate(
                                targetAccount: account,
                                accounts: accounts,
                                draggingAccountID: $draggingAccountID,
                                moveAccounts: moveAccounts
                            )
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
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

private struct AccountSidebarRow: View {
    var account: QuotaAccount
    var isSelected: Bool
    var isDragging: Bool
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
                            Text(account.name)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }

                        Text("\(account.remainingPercentText) remaining")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .blur(radius: account.refreshStatus.hidesQuotaDetails ? 2.6 : 0)
                            .saturation(account.refreshStatus.hidesQuotaDetails ? 0.18 : 1)
                            .opacity(account.refreshStatus.hidesQuotaDetails ? 0.54 : 1)
                            .animation(.snappy(duration: 0.18), value: account.refreshStatus.hidesQuotaDetails)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

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
            isSelected ? Color.primary.opacity(0.075) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .opacity(isDragging ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button(action: beginRename) {
                Label("Edit Name", systemImage: "pencil")
            }

            Button(role: .destructive, action: removeAccount) {
                Label("Delete", systemImage: "trash")
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
}

private struct AccountSidebarDropDelegate: DropDelegate {
    var targetAccount: QuotaAccount
    var accounts: [QuotaAccount]
    @Binding var draggingAccountID: QuotaAccount.ID?
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

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        withAnimation(.snappy(duration: 0.16)) {
            moveAccounts(IndexSet(integer: fromIndex), destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingAccountID = nil
        return true
    }
}
