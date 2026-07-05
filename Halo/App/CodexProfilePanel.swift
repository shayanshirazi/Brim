import AppKit
import SwiftUI

struct CodexProfilePanel: View {
    @Binding var account: QuotaAccount
    @Binding var codexProfilePath: String
    @Binding var copiedCommand: CopiedCommand?
    @State private var apiToken = ""

    private var loginCommand: String {
        QuotaFormatting.codexCommand(path: codexProfilePath, subcommand: "login")
    }

    private var statusCommand: String {
        QuotaFormatting.codexCommand(path: codexProfilePath, subcommand: "login status")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelTitle(icon: "bolt.horizontal.circle", title: "Connection")
                Spacer()
                ConnectionStatusPill(account: account)
            }

            HStack(spacing: 10) {
                ConnectionMethodButton(
                    title: "Login with Codex",
                    icon: "person.crop.circle.badge.checkmark",
                    isSelected: account.connectionKind == .codexLogin,
                    color: Color(hex: "#32D873"),
                    action: { setConnection(.codexLogin) }
                )

                ConnectionMethodButton(
                    title: "API token",
                    icon: "key.horizontal",
                    isSelected: account.connectionKind == .apiToken,
                    color: Color(hex: "#54C7EC"),
                    action: { setConnection(.apiToken) }
                )
            }

            if account.connectionKind == .apiToken {
                VStack(alignment: .leading, spacing: 10) {
                    SecureField("API token", text: $apiToken)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        saveAPIToken()
                    } label: {
                        Label("Use API token", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                TextField("Profile path", text: $codexProfilePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))

                VStack(alignment: .leading, spacing: 8) {
                    CommandRow(
                        title: "Login with Codex",
                        command: loginCommand,
                        isCopied: copiedCommand == .login,
                        copy: { copy(loginCommand, command: .login) }
                    )

                    CommandRow(
                        title: "Check login",
                        command: statusCommand,
                        isCopied: copiedCommand == .status,
                        copy: { copy(statusCommand, command: .status) }
                    )
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color(hex: account.colorHex))
                Text("Halo attempts connected-account refresh every 5 minutes. Tokens stay in Keychain.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private func setConnection(_ kind: QuotaConnectionKind) {
        account.connectionKind = kind
        account.refreshStatus = kind == .manual ? .manual : .waitingForQuotaSource
        account.lastRefreshAttemptAt = Date()
        account.refreshMessage = nil
    }

    private func saveAPIToken() {
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return
        }

        do {
            let credentialID = try CredentialStore.shared.saveAPIToken(token, accountID: account.id)
            account.connectionKind = .apiToken
            account.credentialID = credentialID
            account.refreshStatus = .ready
            account.refreshMessage = "API token saved in Keychain."
            account.lastRefreshAttemptAt = Date()
            account.lastSuccessfulRefreshAt = Date()
            apiToken = ""
        } catch {
            account.connectionKind = .apiToken
            account.refreshStatus = .refreshFailed
            account.refreshMessage = "Could not save API token."
            account.lastRefreshAttemptAt = Date()
        }
    }

    private func copy(_ command: String, command copied: CopiedCommand) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        copiedCommand = copied
    }
}

private struct ConnectionMethodButton: View {
    var title: String
    var icon: String
    var isSelected: Bool
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? color : .secondary)
            .background(
                isSelected ? color.opacity(0.13) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.35) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
