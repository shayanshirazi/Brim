import AppKit
import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @State private var selectedAccountID: QuotaAccount.ID?

    private var selectedAccount: Binding<QuotaAccount>? {
        guard
            let selectedAccountID,
            let index = store.accounts.firstIndex(where: { $0.id == selectedAccountID })
        else {
            return nil
        }

        return Binding(
            get: { store.accounts[index] },
            set: { store.updateAccount($0) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            AccountSidebar(
                accounts: store.accounts,
                selectedAccountID: $selectedAccountID,
                addAccount: addAccount,
                removeSelectedAccount: removeSelectedAccount
            )
            .frame(width: 218)

            Divider()

            Group {
                if let selectedAccount {
                    AccountEditor(account: selectedAccount)
                } else {
                    EmptyAccountsView(addAccount: addAccount)
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
            selectedAccountID = selectedAccountID ?? store.accounts.first?.id
        }
    }

    private func addAccount() {
        store.addAccount()
        selectedAccountID = store.accounts.last?.id
    }

    private func removeSelectedAccount() {
        guard
            let currentSelectedAccountID = selectedAccountID,
            let index = store.accounts.firstIndex(where: { $0.id == currentSelectedAccountID })
        else {
            return
        }

        store.removeAccounts(at: IndexSet(integer: index))
        selectedAccountID = store.accounts[safe: min(index, store.accounts.count - 1)]?.id
    }
}

private struct AccountSidebar: View {
    var accounts: [QuotaAccount]
    @Binding var selectedAccountID: QuotaAccount.ID?
    var addAccount: () -> Void
    var removeSelectedAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Halo")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Spacer()

                Button(action: addAccount) {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Add account")

                Button(action: removeSelectedAccount) {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Remove selected account")
                .disabled(selectedAccountID == nil)
                .opacity(selectedAccountID == nil ? 0.3 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(accounts) { account in
                        AccountSidebarRow(
                            account: account,
                            isSelected: selectedAccountID == account.id
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .onTapGesture {
                            selectedAccountID = account.id
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(.ultraThinMaterial)
    }
}

private struct AccountSidebarRow: View {
    var account: QuotaAccount
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 11) {
            QuotaRingView(account: account, diameter: 32, lineWidth: 4, showPercent: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text("\(account.remainingPercentText) remaining")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            isSelected ? Color.primary.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

private struct AccountEditor: View {
    @Binding var account: QuotaAccount
    @State private var copiedCommand: CopiedCommand?

    private var codexProfilePath: Binding<String> {
        Binding(
            get: { account.resolvedCodexProfilePath },
            set: { account.codexProfilePath = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HeaderPanel(account: account)

                HStack(alignment: .top, spacing: 18) {
                    UsagePanel(account: $account)
                        .frame(maxWidth: .infinity)

                    CodexProfilePanel(
                        account: $account,
                        codexProfilePath: codexProfilePath,
                        copiedCommand: $copiedCommand
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(26)
        }
    }
}

private struct HeaderPanel: View {
    var account: QuotaAccount

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            QuotaWidgetCard(accounts: [account], family: .small)
                .frame(width: 126, height: 116)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                Text(account.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text("5h \(formatMinutes(account.sessionRemainingMinutes)) left / weekly \(formatMinutes(account.weeklyRemainingMinutes)) left")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                ProgressView(value: account.weeklyRemainingFraction)
                    .tint(Color(hex: account.colorHex))
                    .frame(maxWidth: 280)
            }

            Spacer()
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct UsagePanel: View {
    @Binding var account: QuotaAccount

    private var color: Binding<Color> {
        Binding(
            get: { Color(hex: account.colorHex) },
            set: { account.colorHex = $0.quotaHexString }
        )
    }

    private var sessionLimit: Binding<Int> {
        Binding(
            get: { account.sessionLimit },
            set: { newValue in
                account.sessionLimitMinutes = newValue
                if account.sessionUsed > newValue {
                    account.sessionUsedMinutes = newValue
                }
            }
        )
    }

    private var sessionUsed: Binding<Double> {
        Binding(
            get: { Double(account.sessionUsed) },
            set: { account.sessionUsedMinutes = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelTitle(icon: "slider.horizontal.3", title: "Usage")

            TextField("Name", text: $account.name)
                .textFieldStyle(.roundedBorder)

            ColorPicker("Ring color", selection: color)

            Stepper(
                "Outer weekly limit: \(account.weeklyLimitMinutes) minutes",
                value: $account.weeklyLimitMinutes,
                in: 1...3000,
                step: 15
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Outer weekly used")
                    Spacer()
                    Text("\(account.usedMinutes)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: { Double(account.usedMinutes) },
                        set: { account.usedMinutes = Int($0.rounded()) }
                    ),
                    in: 0...Double(max(1, account.weeklyLimitMinutes))
                )
            }

            Stepper(
                "Inner 5h limit: \(account.sessionLimit) minutes",
                value: sessionLimit,
                in: 1...1200,
                step: 15
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Inner 5h used")
                    Spacer()
                    Text("\(account.sessionUsed)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: sessionUsed,
                    in: 0...Double(max(1, account.sessionLimit))
                )
            }

            Picker("Reset day", selection: $account.resetWeekday) {
                Text("Sun").tag(1)
                Text("Mon").tag(2)
                Text("Tue").tag(3)
                Text("Wed").tag(4)
                Text("Thu").tag(5)
                Text("Fri").tag(6)
                Text("Sat").tag(7)
            }

            HStack {
                Stepper("Hour: \(account.resetHour)", value: $account.resetHour, in: 0...23)
                Stepper("Minute: \(account.resetMinute)", value: $account.resetMinute, in: 0...59)
            }
        }
        .panelStyle()
    }
}

private struct CodexProfilePanel: View {
    @Binding var account: QuotaAccount
    @Binding var codexProfilePath: String
    @Binding var copiedCommand: CopiedCommand?

    private var loginCommand: String {
        #"CODEX_HOME="\#(codexProfilePath)" codex login"#
    }

    private var launchCommand: String {
        #"CODEX_HOME="\#(codexProfilePath)" codex"#
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PanelTitle(icon: "person.crop.circle.badge.key", title: "Codex Profile")

            TextField("Profile path", text: $codexProfilePath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .medium, design: .monospaced))

            VStack(alignment: .leading, spacing: 8) {
                CommandRow(
                    title: "Login",
                    command: loginCommand,
                    isCopied: copiedCommand == .login,
                    copy: { copy(loginCommand, command: .login) }
                )

                CommandRow(
                    title: "Launch",
                    command: launchCommand,
                    isCopied: copiedCommand == .launch,
                    copy: { copy(launchCommand, command: .launch) }
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color(hex: account.colorHex))
                Text("Profiles stay separate from your default Codex login.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private func copy(_ command: String, command copied: CopiedCommand) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        copiedCommand = copied
    }
}

private struct CommandRow: View {
    var title: String
    var command: String
    var isCopied: Bool
    var copy: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(command)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(action: copy) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Copy command")
        }
        .padding(10)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PanelTitle: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
    }
}

private struct EmptyAccountsView: View {
    var addAccount: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            QuotaWidgetCard(accounts: [], family: .small)
                .frame(width: 132, height: 132)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

            Button(action: addAccount) {
                Label("Add account", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum CopiedCommand {
    case login
    case launch
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
