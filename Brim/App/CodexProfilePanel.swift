import AppKit
import SwiftUI

struct CodexProfilePanel: View {
    @Binding var account: QuotaAccount
    @Binding var codexProfilePath: String
    @Binding var copiedCommand: CopiedCommand?
    @State private var apiToken = ""
    @State private var selectedConnectionKind: QuotaConnectionKind
    @State private var loginFlowState: CodexLoginFlowState = .idle

    init(
        account: Binding<QuotaAccount>,
        codexProfilePath: Binding<String>,
        copiedCommand: Binding<CopiedCommand?>
    ) {
        _account = account
        _codexProfilePath = codexProfilePath
        _copiedCommand = copiedCommand
        _selectedConnectionKind = State(initialValue: account.wrappedValue.connectionKind)
    }

    private var loginCommand: String {
        QuotaFormatting.codexCommand(path: codexProfilePath, subcommand: "login")
    }

    private var statusCommand: String {
        QuotaFormatting.codexCommand(path: codexProfilePath, subcommand: "login status")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelTitle(icon: "bolt.horizontal.circle", title: "Setup")
                Spacer()
            }

            HStack(spacing: 10) {
                ConnectionMethodButton(
                    title: "Login with Codex",
                    icon: "person.crop.circle.badge.checkmark",
                    isSelected: selectedConnectionKind == .codexLogin,
                    color: Color(hex: account.colorHex),
                    action: { selectConnectionTab(.codexLogin) }
                )

                ConnectionMethodButton(
                    title: "API token",
                    icon: "key.horizontal",
                    isSelected: selectedConnectionKind == .apiToken,
                    color: Color(hex: "#54C7EC"),
                    action: { selectConnectionTab(.apiToken) }
                )
            }

            if selectedConnectionKind == .apiToken {
                HStack(spacing: 10) {
                    SecureField("API token", text: $apiToken)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 11)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    APITokenButton(
                        title: "Use token",
                        icon: "checkmark.circle.fill",
                        isEnabled: !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        action: saveAPIToken
                    )
                    .disabled(apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    CodexBrowserLoginCard(
                        state: resolvedLoginFlowState,
                        accountColor: Color(hex: account.colorHex),
                        action: resolvedLoginFlowState == .connected ? checkCodexLogin : startCodexLogin
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)

                        TextField("Profile path", text: $codexProfilePath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    HStack(spacing: 8) {
                        SecondaryConnectionButton(
                            title: "Check",
                            icon: "checkmark.seal",
                            action: checkCodexLogin
                        )

                        SecondaryConnectionButton(
                            title: copiedCommand == .login ? "Copied" : "Copy login",
                            icon: copiedCommand == .login ? "checkmark" : "doc.on.doc",
                            action: { copy(loginCommand, command: .login) }
                        )

                        SecondaryConnectionButton(
                            title: copiedCommand == .status ? "Copied" : "Copy check",
                            icon: copiedCommand == .status ? "checkmark" : "doc.on.doc",
                            action: { copy(statusCommand, command: .status) }
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color(hex: account.colorHex))
                Text("Refreshes every 5 min. Tokens stay in Keychain.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
        .onChange(of: account.id) { _, _ in
            selectedConnectionKind = account.connectionKind
            loginFlowState = .idle
        }
        .onChange(of: account.connectionKind) { _, kind in
            selectedConnectionKind = kind
        }
    }

    private var resolvedLoginFlowState: CodexLoginFlowState {
        if loginFlowState.isWorking {
            return loginFlowState
        }

        guard account.connectionKind == .codexLogin else {
            return .idle
        }

        switch account.refreshStatus {
        case .ready:
            return .connected
        case .waitingForQuotaSource:
            return .checking
        case .refreshFailed:
            return .failed(account.refreshMessage ?? "Brim could not check the Codex session.")
        case .notConnected, .manual:
            return .idle
        }
    }

    private func selectConnectionTab(_ kind: QuotaConnectionKind) {
        selectedConnectionKind = kind
        copiedCommand = nil
    }

    private func startCodexLogin() {
        selectedConnectionKind = .codexLogin
        account.connectionKind = .codexLogin
        loginFlowState = .openingBrowser
        account.refreshStatus = .waitingForQuotaSource
        account.lastRefreshAttemptAt = Date()
        account.refreshMessage = "Opening Codex login in your browser."

        Task {
            let profilePath = QuotaFormatting.expandedHomePath(codexProfilePath)
            let loginResult = await CodexCommandRunner.run(profilePath: profilePath, subcommand: "login")

            guard loginResult.exitCode == 0 else {
                markLoginFailure(loginResult)
                return
            }

            loginFlowState = .checking
            let statusResult = await CodexCommandRunner.run(profilePath: profilePath, subcommand: "login status")
            applyLoginStatus(statusResult)
        }
    }

    private func checkCodexLogin() {
        selectedConnectionKind = .codexLogin
        account.connectionKind = .codexLogin
        loginFlowState = .checking
        account.refreshStatus = .waitingForQuotaSource
        account.lastRefreshAttemptAt = Date()

        Task {
            let profilePath = QuotaFormatting.expandedHomePath(codexProfilePath)
            let statusResult = await CodexCommandRunner.run(profilePath: profilePath, subcommand: "login status")
            applyPingStatus(statusResult)
        }
    }

    private func saveAPIToken() {
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return
        }

        do {
            let credentialID = try CredentialStore.shared.saveAPIToken(token, accountID: account.id)
            selectedConnectionKind = .apiToken
            account.connectionKind = .apiToken
            account.credentialID = credentialID
            account.refreshStatus = .ready
            account.refreshMessage = "API token saved in Keychain."
            account.lastRefreshAttemptAt = Date()
            account.lastSuccessfulRefreshAt = Date()
            apiToken = ""
        } catch {
            selectedConnectionKind = .apiToken
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

    private func applyLoginStatus(_ result: CommandResult) {
        if isLoggedIn(result) {
            account.connectionKind = .codexLogin
            if let email = emailAddress(from: result) {
                account.accountEmail = email
            }
            account.refreshStatus = .ready
            account.refreshMessage = "Codex login is connected."
            account.lastSuccessfulRefreshAt = Date()
            loginFlowState = .connected
        } else if isNotLoggedIn(result) {
            account.connectionKind = .codexLogin
            account.refreshStatus = .notConnected
            account.refreshMessage = "Sign in with Codex to connect this account."
            loginFlowState = .idle
        } else {
            markLoginFailure(result)
        }
    }

    private func applyPingStatus(_ result: CommandResult) {
        account.connectionKind = .codexLogin

        if isLoggedIn(result) {
            if let email = emailAddress(from: result) {
                account.accountEmail = email
            }
            account.refreshStatus = .ready
            account.refreshMessage = "Codex login is connected."
            account.lastSuccessfulRefreshAt = Date()
            loginFlowState = .connected
        } else {
            account.refreshStatus = .notConnected
            account.refreshMessage = "Sign in with Codex to connect this account."
            loginFlowState = .idle
        }
    }

    private func markLoginFailure(_ result: CommandResult) {
        let message = commandMessage(from: result)
        account.refreshStatus = .refreshFailed
        account.refreshMessage = message
        loginFlowState = .failed(message)
    }

    private func isLoggedIn(_ result: CommandResult) -> Bool {
        let output = (result.standardOutput + "\n" + result.standardError).lowercased()
        return result.exitCode == 0 && output.contains("logged in")
    }

    private func emailAddress(from result: CommandResult) -> String? {
        QuotaFormatting.emailAddress(in: result.standardOutput + "\n" + result.standardError)
    }

    private func isNotLoggedIn(_ result: CommandResult) -> Bool {
        let output = (result.standardOutput + "\n" + result.standardError).lowercased()
        return output.contains("not logged in")
    }

    private func commandMessage(from result: CommandResult) -> String {
        let message = result.standardOutput.isEmpty ? result.standardError : result.standardOutput
        let lines = message
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && !line.localizedCaseInsensitiveContains("WARNING: proceeding")
                    && !line.localizedCaseInsensitiveContains("PATH aliases")
                    && !line.localizedCaseInsensitiveContains("Error loading configuration")
                    && !line.localizedCaseInsensitiveContains("CODEX_HOME points")
            }

        let trimmed = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Codex login did not complete." : trimmed
    }
}

private enum CodexLoginFlowState: Equatable {
    case idle
    case openingBrowser
    case checking
    case connected
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .openingBrowser, .checking:
            return true
        case .idle, .connected, .failed:
            return false
        }
    }

    var statusLine: String {
        switch self {
        case .idle:
            return "Browser sign-in saved to this profile."
        case .openingBrowser:
            return "Waiting for browser sign-in."
        case .checking:
            return "Verifying the saved session."
        case .connected:
            return "Codex session is ready."
        case .failed(let message):
            return message
        }
    }

    var buttonTitle: String {
        switch self {
        case .openingBrowser:
            return "Opening"
        case .checking:
            return "Checking"
        case .connected:
            return "Ping"
        case .idle, .failed:
            return "Sign in"
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "safari"
        case .openingBrowser:
            return "arrow.up.forward.app"
        case .checking:
            return "waveform.path.ecg"
        case .connected:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    func accent(accountColor: Color) -> Color {
        switch self {
        case .idle, .openingBrowser, .checking, .connected:
            return accountColor
        case .failed:
            return Color(hex: "#FF4D57")
        }
    }
}

private struct CodexBrowserLoginCard: View {
    var state: CodexLoginFlowState
    var accountColor: Color
    var action: () -> Void

    private var accent: Color {
        state.accent(accountColor: accountColor)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.13))
                    .frame(width: 48, height: 48)

                Image(systemName: state.icon)
                    .font(.system(size: 18, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Codex login")
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                Text(state.statusLine)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailingControl
        }
        .padding(12)
        .frame(minHeight: 74)
        .background(
            LinearGradient(
                colors: [
                    accent.opacity(0.10),
                    Color(nsColor: .controlBackgroundColor).opacity(0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent)
                .frame(width: 3, height: 46)
                .padding(.leading, 7)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if state.isWorking {
            HStack(spacing: 7) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)

                Text(state.buttonTitle)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(accent)
            .frame(width: 104, height: 34)
            .background(accent.opacity(0.13), in: Capsule())
        } else {
            Button(action: action) {
                HStack(spacing: 7) {
                    Image(systemName: state == .connected ? "dot.radiowaves.left.and.right" : "safari")
                        .font(.system(size: 12, weight: .bold))

                    Text(state.buttonTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(width: 104, height: 34)
                .background(accent, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
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

private struct APITokenButton: View {
    var title: String
    var icon: String
    var isEnabled: Bool
    var action: () -> Void

    private let color = Color(hex: "#54C7EC")

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isEnabled ? .white : color.opacity(0.54))
            .frame(width: 112, height: 34)
            .background(
                isEnabled ? color : color.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isEnabled ? Color.white.opacity(0.16) : color.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SecondaryConnectionButton: View {
    var title: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(.secondary)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
