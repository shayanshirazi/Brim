import AppKit
import SwiftUI

struct ProviderProfilePanel: View {
    @EnvironmentObject private var store: QuotaStore
    @Binding var account: QuotaAccount
    @Binding var profilePath: String
    @State private var apiToken = ""
    @State private var selectedConnectionKind: QuotaConnectionKind
    @State private var loginFlowState: ProviderLoginFlowState = .idle
    @State private var didCopyAPIToken = false
    @State private var apiTokenIsSaving = false
    @State private var savedAPITokenPreview: String?
    @State private var showsProfileLocation = false
    @AppStorage(BrimRefreshInterval.storageKey) private var refreshIntervalSeconds = BrimRefreshInterval.defaultSeconds
    var openPersonalizationSettings: () -> Void

    init(
        account: Binding<QuotaAccount>,
        profilePath: Binding<String>,
        openPersonalizationSettings: @escaping () -> Void = {}
    ) {
        _account = account
        _profilePath = profilePath
        _selectedConnectionKind = State(initialValue: account.wrappedValue.connectionKind)
        self.openPersonalizationSettings = openPersonalizationSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PanelTitle(icon: "key.fill", title: "Setup")
                Spacer()
            }

            HStack(spacing: 8) {
                ConnectionMethodButton(
                    title: "Login",
                    icon: "person.crop.circle.badge.checkmark",
                    isSelected: selectedConnectionKind == .login,
                    action: { selectConnectionTab(.login) }
                )

                ConnectionMethodButton(
                    title: "API token",
                    icon: "key.horizontal",
                    isSelected: selectedConnectionKind == .apiToken,
                    action: { selectConnectionTab(.apiToken) }
                )
            }
            .padding(4)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if selectedConnectionKind == .apiToken {
                APITokenConnectionCard(
                    token: $apiToken,
                    savedTokenPreview: savedAPITokenPreview,
                    validationMessage: apiTokenValidationMessage,
                    statusMessage: apiTokenStatusMessage,
                    statusKind: apiTokenStatusKind,
                    isWorking: apiTokenIsWorking,
                    didCopyToken: didCopyAPIToken,
                    saveAction: saveAPIToken,
                    refreshAction: refreshAPITokenAccount,
                    revokeAction: confirmRevokeAPIToken,
                    copyAction: copySavedAPIToken
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ProviderConnectionCard(
                        state: resolvedLoginFlowState,
                        provider: account.provider,
                        primaryAction: resolvedLoginFlowState == .connected ? checkProviderLogin : startProviderLogin,
                        logoutAction: confirmProviderLogout
                    )

                    profileLocationDisclosure
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 36)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            setupFooter
        }
        .onAppear {
            selectedConnectionKind = account.connectionKind
            refreshSavedAPITokenPreview()
        }
        .onChange(of: account.id) { _, _ in
            selectedConnectionKind = account.connectionKind
            loginFlowState = .idle
            apiToken = ""
            didCopyAPIToken = false
            apiTokenIsSaving = false
            showsProfileLocation = false
            refreshSavedAPITokenPreview()
        }
        .onChange(of: account.connectionKind) { _, kind in
            selectedConnectionKind = kind
            refreshSavedAPITokenPreview()
        }
    }

    private var setupFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)

            Text("Every")
                .foregroundStyle(.secondary)

            Button(action: openPersonalizationSettings) {
                Text(BrimRefreshInterval.displayTitle(for: refreshIntervalSeconds))
                    .underline(true, color: .secondary)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Change refresh frequency")

            Spacer(minLength: 8)

            Label("Keychain", systemImage: "lock.fill")
                .foregroundStyle(.secondary)
                .help("Tokens stay in Keychain.")
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.88)
        .frame(maxWidth: .infinity)
        .frame(height: 28, alignment: .center)
    }

    private var profileLocationDisclosure: some View {
        DisclosureGroup(isExpanded: $showsProfileLocation) {
            TextField("Profile path", text: $profilePath)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.top, 8)
        } label: {
            Text("Profile location")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .tint(.secondary)
    }

    private var resolvedLoginFlowState: ProviderLoginFlowState {
        if loginFlowState.isWorking {
            return loginFlowState
        }

        guard account.connectionKind == .login else {
            return .idle
        }

        switch account.refreshStatus {
        case .ready:
            return .connected
        case .waitingForQuotaSource:
            return account.hasUsageSnapshot ? .checking : .connected
        case .refreshFailed:
            return .failed(account.refreshMessage ?? "Brim could not check the \(account.provider.displayName) session.")
        case .notConnected, .manual:
            return .idle
        }
    }

    private var trimmedAPIToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var apiTokenValidation: APITokenValidation {
        APITokenValidator.validate(trimmedAPIToken)
    }

    private var apiTokenValidationMessage: String? {
        guard !trimmedAPIToken.isEmpty, case .invalid(let message) = apiTokenValidation else {
            return nil
        }

        return message
    }

    private var hasSavedAPIToken: Bool {
        savedAPITokenPreview != nil
    }

    private var apiTokenStatusKind: ConnectionStatusKind {
        if apiTokenIsSaving {
            return .working
        }

        guard account.connectionKind == .apiToken, hasSavedAPIToken else {
            return .idle
        }

        switch account.refreshStatus {
        case .waitingForQuotaSource:
            return .working
        case .refreshFailed:
            return .needsAttention
        case .notConnected:
            return .idle
        case .ready, .manual:
            return .ready
        }
    }

    private var apiTokenIsWorking: Bool {
        apiTokenIsSaving
            || account.connectionKind == .apiToken
            && hasSavedAPIToken
            && account.refreshStatus == .waitingForQuotaSource
    }

    private var apiTokenStatusMessage: String {
        if apiTokenIsSaving {
            return "Validating the API token with OpenAI."
        }

        if account.connectionKind == .apiToken, hasSavedAPIToken {
            if account.refreshStatus == .waitingForQuotaSource {
                return "Checking the saved token."
            }
            if account.refreshStatus == .refreshFailed, let message = account.refreshMessage {
                return message
            }

            return "Saved in Keychain for this account."
        }

        return "Save a valid OpenAI API key in Keychain for this account."
    }

    private func selectConnectionTab(_ kind: QuotaConnectionKind) {
        selectedConnectionKind = kind
    }

    private func startProviderLogin() {
        selectedConnectionKind = .login
        account.connectionKind = .login
        loginFlowState = .openingBrowser
        account.refreshStatus = .waitingForQuotaSource
        account.lastRefreshAttemptAt = Date()
        account.refreshMessage = "Opening Codex sign-in in your browser."

        Task {
            let expandedProfilePath = QuotaFormatting.expandedHomePath(profilePath)
            let loginResult = await CodexCommandRunner.startBrowserLogin(profilePath: expandedProfilePath)
            if loginResult.exitCode == 0 {
                account.connectionKind = .login
                account.refreshStatus = .ready
                account.refreshMessage = "\(account.provider.displayName) login is connected. Exact usage opens in \(account.provider.displayName)."
                account.lastSuccessfulRefreshAt = Date()
                await store.refreshAccount(id: account.id)
                loginFlowState = .connected
                return
            }

            markLoginFailure(loginResult)
        }
    }

    private func checkProviderLogin() {
        selectedConnectionKind = .login
        account.connectionKind = .login
        loginFlowState = .checking
        account.refreshStatus = .waitingForQuotaSource
        account.lastRefreshAttemptAt = Date()

        Task {
            let expandedProfilePath = QuotaFormatting.expandedHomePath(profilePath)
            if CodexProfileAuthStore.hasUsableTokens(profilePath: expandedProfilePath) {
                await store.refreshAccount(id: account.id)
                loginFlowState = .connected
            } else {
                account.hasUsageSnapshot = false
                account.refreshStatus = .notConnected
                account.refreshMessage = "Sign in with \(account.provider.displayName) to connect this account."
                loginFlowState = .idle
            }
        }
    }

    private func confirmProviderLogout() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Log out of \(account.provider.displayName)?"
        alert.informativeText = "This disconnects \(account.name) from Brim on this Mac. You can sign in again anytime."
        alert.addButton(withTitle: "Log out")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        logoutProvider()
    }

    private func logoutProvider() {
        selectedConnectionKind = .login
        account.connectionKind = .login
        loginFlowState = .loggingOut
        account.refreshStatus = .waitingForQuotaSource
        account.refreshMessage = "Signing out of \(account.provider.displayName)."
        account.lastRefreshAttemptAt = Date()

        Task {
            let expandedProfilePath = QuotaFormatting.expandedHomePath(profilePath)
            do {
                try CodexProfileAuthStore.removeAuth(profilePath: expandedProfilePath)
            } catch {
                markLoginFailure(
                    CommandResult(
                        exitCode: -1,
                        standardOutput: "",
                        standardError: "Brim could not remove this Codex profile's auth file."
                    )
                )
                return
            }

            account = account.disconnectedProviderAccount(
                message: "Sign in with \(account.provider.displayName) to connect this account."
            )
            loginFlowState = .idle
        }
    }

    private func saveAPIToken() {
        guard !apiTokenIsSaving else {
            return
        }

        let token = trimmedAPIToken
        guard case .valid = APITokenValidator.validate(token) else {
            return
        }

        selectedConnectionKind = .apiToken
        account.connectionKind = .apiToken
        account.refreshStatus = .waitingForQuotaSource
        account.refreshMessage = "Validating API token."
        account.lastRefreshAttemptAt = Date()
        apiTokenIsSaving = true

        Task { @MainActor in
            do {
                try await APITokenValidationClient().validate(token)
                let credentialID = try CredentialStore.shared.saveAPIToken(token, accountID: account.id)

                account.connectionKind = .apiToken
                account.credentialID = credentialID
                account.hasUsageSnapshot = false
                account.refreshStatus = .ready
                account.refreshMessage = "API token saved. Exact usage opens in \(account.provider.displayName)."
                account.lastSuccessfulRefreshAt = Date()
                apiToken = ""
                didCopyAPIToken = false
                savedAPITokenPreview = APITokenPreview.mask(token)
            } catch {
                account.connectionKind = .apiToken
                account.refreshStatus = .refreshFailed
                account.refreshMessage = (error as? APITokenValidationError)?.message ?? "Could not validate API token."
            }

            apiTokenIsSaving = false
        }
    }

    private func refreshAPITokenAccount() {
        selectedConnectionKind = .apiToken
        account.connectionKind = .apiToken
        account.refreshStatus = .waitingForQuotaSource
        account.refreshMessage = nil
        account.lastRefreshAttemptAt = Date()

        Task {
            await store.refreshAccount(id: account.id)
        }
    }

    private func confirmRevokeAPIToken() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Revoke API token?"
        alert.informativeText = "This removes the saved token for \(account.name) from Keychain on this Mac."
        alert.addButton(withTitle: "Revoke")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        revokeAPIToken()
    }

    private func revokeAPIToken() {
        CredentialStore.shared.deleteAPIToken(credentialID: account.credentialID)
        selectedConnectionKind = .apiToken
        account.connectionKind = .apiToken
        account.credentialID = nil
        account.hasUsageSnapshot = false
        account.refreshStatus = .notConnected
        account.refreshMessage = "Add an API token to reconnect this account."
        account.lastRefreshAttemptAt = Date()
        account.lastSuccessfulRefreshAt = nil
        didCopyAPIToken = false
        savedAPITokenPreview = nil
    }

    private func copySavedAPIToken() {
        guard let token = CredentialStore.shared.apiToken(credentialID: account.credentialID) else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        didCopyAPIToken = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            didCopyAPIToken = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            guard NSPasteboard.general.string(forType: .string) == token else {
                return
            }
            NSPasteboard.general.clearContents()
        }
    }

    private func refreshSavedAPITokenPreview() {
        guard account.connectionKind == .apiToken else {
            savedAPITokenPreview = nil
            return
        }

        savedAPITokenPreview = CredentialStore.shared
            .apiToken(credentialID: account.credentialID)
            .map(APITokenPreview.mask)
    }

    private func markLoginFailure(_ result: CommandResult) {
        let message = commandMessage(from: result)
        account.refreshStatus = .refreshFailed
        account.refreshMessage = message
        loginFlowState = .failed(message)
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
        return trimmed.isEmpty ? "\(account.provider.displayName) login did not complete." : trimmed
    }
}

private enum ProviderLoginFlowState: Equatable {
    case idle
    case openingBrowser
    case checking
    case loggingOut
    case connected
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .openingBrowser, .checking, .loggingOut:
            return true
        case .idle, .connected, .failed:
            return false
        }
    }

    func statusLine(provider: QuotaProviderKind) -> String {
        switch self {
        case .idle:
            return "Use your local \(provider.displayName) session for this account."
        case .openingBrowser:
            return "Complete sign-in in the browser window."
        case .checking:
            return "Checking the saved session."
        case .loggingOut:
            return "Signing out of \(provider.displayName)."
        case .connected:
            return "\(provider.displayName) session is ready."
        case .failed(let message):
            return message
        }
    }

    func buttonTitle(provider: QuotaProviderKind) -> String {
        switch self {
        case .openingBrowser:
            return "Opening"
        case .checking:
            return "Checking"
        case .loggingOut:
            return "Logging out"
        case .connected:
            return "Refresh"
        case .idle, .failed:
            return "Sign in with \(provider.displayName)"
        }
    }

    var statusKind: ConnectionStatusKind {
        switch self {
        case .idle:
            return .idle
        case .openingBrowser:
            return .working
        case .checking:
            return .working
        case .loggingOut:
            return .working
        case .connected:
            return .ready
        case .failed:
            return .needsAttention
        }
    }
}

private struct ProviderConnectionCard: View {
    var state: ProviderLoginFlowState
    var provider: QuotaProviderKind
    var primaryAction: () -> Void
    var logoutAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConnectionStatusRow(
                icon: "person.crop.circle.badge.checkmark",
                title: "Use \(provider.displayName) sign-in",
                message: state.statusLine(provider: provider),
                state: state.statusKind
            )

            if state == .connected {
                HStack(spacing: 8) {
                    ConnectionActionButton(
                        title: "Refresh",
                        icon: "arrow.clockwise",
                        isEnabled: true,
                        role: .primary,
                        action: primaryAction
                    )

                    ConnectionActionButton(
                        title: "Log out",
                        icon: "rectangle.portrait.and.arrow.right",
                        isEnabled: true,
                        role: .destructive,
                        action: logoutAction
                    )
                }
            } else {
                PrimaryConnectionButton(
                    title: state.buttonTitle(provider: provider),
                    isWorking: state.isWorking,
                    action: primaryAction
                )
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.022), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private enum APITokenValidation: Equatable {
    case empty
    case valid
    case invalid(String)
}

private enum APITokenValidator {
    static func validate(_ token: String) -> APITokenValidation {
        guard !token.isEmpty else {
            return .empty
        }

        guard token == token.trimmingCharacters(in: .whitespacesAndNewlines),
              token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return .invalid("Paste the token without spaces or line breaks.")
        }

        guard token.hasPrefix("sk-") else {
            return .invalid("OpenAI API keys begin with sk-.")
        }

        guard token.count >= 24 else {
            return .invalid("That key looks too short.")
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard token.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return .invalid("That key contains an unexpected character.")
        }

        return .valid
    }
}

private enum APITokenValidationError: Error {
    case rejected
    case server(Int)
    case network(String)

    var message: String {
        switch self {
        case .rejected:
            return "OpenAI rejected this API token."
        case .server(let statusCode):
            return "Could not validate API token. OpenAI returned HTTP \(statusCode)."
        case .network(let message):
            return "Could not validate API token: \(message)"
        }
    }
}

private struct APITokenValidationClient {
    private let session: URLSession
    private let validationURL: URL

    init(
        session: URLSession = .shared,
        validationURL: URL = URL(string: "https://api.openai.com/v1/models")!
    ) {
        self.session = session
        self.validationURL = validationURL
    }

    func validate(_ token: String) async throws {
        var request = URLRequest(url: validationURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APITokenValidationError.network("No HTTP response.")
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return
            case 401, 403:
                throw APITokenValidationError.rejected
            default:
                throw APITokenValidationError.server(httpResponse.statusCode)
            }
        } catch let error as APITokenValidationError {
            throw error
        } catch {
            throw APITokenValidationError.network(error.localizedDescription)
        }
    }
}

private enum APITokenPreview {
    static func mask(_ token: String) -> String {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count > 14 else {
            return token
        }

        return "\(token.prefix(8))...\(token.suffix(6))"
    }
}

private struct APITokenConnectionCard: View {
    @Binding var token: String
    var savedTokenPreview: String?
    var validationMessage: String?
    var statusMessage: String
    var statusKind: ConnectionStatusKind
    var isWorking: Bool
    var didCopyToken: Bool
    var saveAction: () -> Void
    var refreshAction: () -> Void
    var revokeAction: () -> Void
    var copyAction: () -> Void

    private var hasSavedToken: Bool {
        savedTokenPreview != nil
    }

    private var saveValidation: APITokenValidation {
        APITokenValidator.validate(token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSave: Bool {
        saveValidation == .valid && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConnectionStatusRow(
                icon: "key.horizontal",
                title: hasSavedToken ? "API token saved" : "Use an API token",
                message: statusMessage,
                state: statusKind
            )

            if let savedTokenPreview {
                SavedAPITokenRow(
                    preview: savedTokenPreview,
                    didCopy: didCopyToken,
                    copyAction: copyAction
                )

                HStack(spacing: 8) {
                    ConnectionActionButton(
                        title: isWorking ? "Checking" : "Refresh",
                        icon: "arrow.clockwise",
                        isEnabled: !isWorking,
                        role: .primary,
                        action: refreshAction
                    )

                    ConnectionActionButton(
                        title: "Revoke",
                        icon: "trash",
                        isEnabled: true,
                        role: .destructive,
                        action: revokeAction
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    SecureField("API token", text: $token)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "#B7791F"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                APITokenButton(
                    title: "Save token",
                    icon: "checkmark.circle.fill",
                    isEnabled: canSave,
                    action: saveAction
                )
                .disabled(!canSave)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.022), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct SavedAPITokenRow: View {
    var preview: String
    var didCopy: Bool
    var copyAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(preview)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button(action: copyAction) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(didCopy ? Color(hex: "#2CCB68") : .secondary)
                    .frame(width: 22, height: 22)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("Copy API token")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private enum ConnectionActionRole {
    case primary
    case destructive

    var foregroundColor: Color {
        switch self {
        case .primary:
            return .white
        case .destructive:
            return Color.primary.opacity(0.64)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .primary:
            return Color.primary.opacity(0.76)
        case .destructive:
            return Color.primary.opacity(0.045)
        }
    }

    var strokeColor: Color {
        switch self {
        case .primary:
            return .clear
        case .destructive:
            return Color.primary.opacity(0.075)
        }
    }
}

private struct ConnectionActionButton: View {
    var title: String
    var icon: String
    var isEnabled: Bool
    var role: ConnectionActionRole
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(role.foregroundColor.opacity(isEnabled ? 1 : 0.48))
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(role.backgroundColor.opacity(isEnabled ? 1 : 0.48), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(role.strokeColor, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private enum ConnectionStatusKind {
    case idle
    case working
    case ready
    case needsAttention

    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .working:
            return Color(hex: "#8B949E")
        case .ready:
            return Color(hex: "#2FBF64")
        case .needsAttention:
            return Color(hex: "#B7791F")
        }
    }
}

private struct ConnectionStatusRow: View {
    var icon: String
    var title: String
    var message: String
    var state: ConnectionStatusKind

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(state.color)
                .frame(width: 28, height: 28)
                .background(state.color.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.82))

                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConnectionMethodButton: View {
    var title: String
    var icon: String
    var isSelected: Bool
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
            .foregroundStyle(isSelected ? Color.primary.opacity(0.78) : Color.secondary.opacity(0.82))
            .background(
                isSelected ? Color(nsColor: .textBackgroundColor).opacity(0.98) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.045) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PrimaryConnectionButton: View {
    var title: String
    var isWorking: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking {
                    ProgressView()
                        .scaleEffect(0.58)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(Color.primary.opacity(isWorking ? 0.40 : 0.76), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}

private struct APITokenButton: View {
    var title: String
    var icon: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isEnabled ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(
                isEnabled ? Color.primary.opacity(0.76) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(isEnabled ? 0 : 0.04), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
