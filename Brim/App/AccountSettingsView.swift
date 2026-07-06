import AppKit
import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @State private var selectedAccountID: QuotaAccount.ID?
    @State private var showsAddAccountSheet = false

    var route: AppRoute?
    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    private var selectedAccount: Binding<QuotaAccount>? {
        guard
            let selectedAccountID,
            store.accounts.contains(where: { $0.id == selectedAccountID })
        else {
            return nil
        }

        return Binding(
            get: {
                store.accounts.first(where: { $0.id == selectedAccountID })
                    ?? store.accounts.first
                    ?? QuotaAccountDefaults.newAccount(index: 1)
            },
            set: { store.updateAccount($0) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            AccountSidebar(
                accounts: store.accounts,
                selectedAccountID: $selectedAccountID,
                addAccount: addAccount,
                removeAccount: removeAccount,
                moveAccounts: moveAccounts,
                renameAccount: renameAccount,
                selectAccount: selectAccount
            )
            .frame(width: 218)

            Divider()

            Group {
                VStack(spacing: 0) {
                    StorageStatusBanner(status: store.storageStatus)

                    if let selectedAccount {
                        AccountEditor(account: selectedAccount)
                    } else {
                        EmptyAccountsView(addAccount: addAccount)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(hex: "#EAF8F2").opacity(0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            selectedAccountID = selectedAccountID ?? store.selectedAccountID ?? store.accounts.first?.id
            handle(route)
            Task {
                await store.refreshConnectedAccounts()
            }
        }
        .onChange(of: route) { _, nextRoute in
            handle(nextRoute)
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await store.refreshConnectedAccounts()
            }
        }
        .sheet(isPresented: $showsAddAccountSheet) {
            AddAccountSheet { connectionKind in
                createAccount(connectionKind: connectionKind)
                showsAddAccountSheet = false
            }
        }
    }

    private func addAccount() {
        showsAddAccountSheet = true
    }

    private func createAccount(connectionKind: QuotaConnectionKind) {
        store.addAccount(connectionKind: connectionKind)
        selectedAccountID = store.accounts.last?.id
        store.selectAccount(id: selectedAccountID)
    }

    private func removeAccount(_ accountID: QuotaAccount.ID) {
        guard
            let index = store.accounts.firstIndex(where: { $0.id == accountID })
        else {
            return
        }

        CredentialStore.shared.deleteAPIToken(credentialID: store.accounts[safe: index]?.credentialID)
        let previousSelectedAccountID = selectedAccountID
        store.removeAccounts(at: IndexSet(integer: index))

        if
            previousSelectedAccountID != accountID,
            let previousSelectedAccountID,
            store.accounts.contains(where: { $0.id == previousSelectedAccountID })
        {
            selectedAccountID = previousSelectedAccountID
        } else {
            selectedAccountID = store.accounts[safe: min(index, store.accounts.count - 1)]?.id
        }

        store.selectAccount(id: selectedAccountID)
    }

    private func moveAccounts(fromOffsets source: IndexSet, toOffset destination: Int) {
        store.moveAccounts(fromOffsets: source, toOffset: destination)
    }

    private func selectAccount(_ accountID: QuotaAccount.ID) {
        selectedAccountID = accountID
        store.selectAccount(id: accountID)
    }

    private func renameAccount(_ accountID: QuotaAccount.ID, name: String) {
        guard var account = store.accounts.first(where: { $0.id == accountID }) else {
            return
        }

        account.name = name
        store.updateAccount(account)
    }

    private func handle(_ route: AppRoute?) {
        switch route {
        case .accounts:
            selectedAccountID = store.selectedAccountID ?? store.accounts.first?.id
        case nil:
            break
        }
    }
}

private struct StorageStatusBanner: View {
    var status: QuotaStorageStatus

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(message)
                    .lineLimit(2)
                Spacer()
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(.thinMaterial)
        }
    }

    private var icon: String {
        switch status {
        case .corrupted, .saveFailed, .unavailable:
            return "exclamationmark.triangle"
        case .firstRun:
            return "sparkles"
        case .ready:
            return ""
        }
    }

    private var message: String? {
        switch status {
        case .ready:
            return nil
        case .firstRun:
            return "Started with local example accounts. Connect Codex or add an API-token account."
        case .corrupted:
            return "Saved account data could not be read, so Brim preserved the broken payload and loaded examples."
        case .saveFailed:
            return "Brim could not save the latest account changes."
        case .unavailable:
            return "Shared widget storage is unavailable."
        }
    }
}

private struct AddAccountSheet: View {
    var createAccount: (QuotaConnectionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                BrimLogoMark(size: 42)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Add account")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Choose the connection method. Tokens stay in Keychain; the widget only receives a quota snapshot.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                AddAccountOptionButton(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Login with Codex",
                    detail: "Use the local Codex login for this account.",
                    accent: Color(hex: "#32D873"),
                    action: { createAccount(.codexLogin) }
                )

                AddAccountOptionButton(
                    icon: "key.horizontal",
                    title: "Use API token",
                    detail: "Store a token in Keychain for refresh.",
                    accent: Color(hex: "#54C7EC"),
                    action: { createAccount(.apiToken) }
                )
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AddAccountOptionButton: View {
    var icon: String
    var title: String
    var detail: String
    var accent: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [accent.opacity(0.12), Color.primary.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
