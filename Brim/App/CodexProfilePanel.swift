import AppKit
import OSLog
import SwiftUI

struct ProviderProfilePanel: View {
    private static let logger = Logger(subsystem: "com.brim.app", category: "credentials")

    @EnvironmentObject private var store: QuotaStore
    @Binding var account: QuotaAccount
    @State private var apiToken = ""
    @State private var selectedConnectionKind: QuotaConnectionKind
    @State private var loginFlowState: ProviderLoginFlowState = .idle
    @State private var didCopyAPIToken = false
    @State private var apiTokenIsSaving = false
    @State private var savedAPITokenPreview: String?
    @State private var credentialAccessMessage: String?
    @State private var showsProfileLocation = false
    @State private var didCopyProfileLocation = false
    @AppStorage(BrimRefreshInterval.storageKey) private var refreshIntervalSeconds = BrimRefreshInterval.defaultSeconds
    var openPersonalizationSettings: () -> Void

    init(
        account: Binding<QuotaAccount>,
        openPersonalizationSettings: @escaping () -> Void = {}
    ) {
        _account = account
        _selectedConnectionKind = State(initialValue: account.wrappedValue.connectionKind)
        self.openPersonalizationSettings = openPersonalizationSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProviderSetupTitle(provider: account.provider)

            if !account.provider.supports(account.connectionKind) {
                UnsupportedConnectionCard(
                    provider: account.provider,
                    switchAction: switchToSupportedConnection
                )
            } else if account.provider == .gemini {
                APITokenConnectionCard(
                    token: $apiToken,
                    provider: account.provider,
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
            } else if account.provider == .codex {
                VStack(alignment: .leading, spacing: 16) {
                    ProviderConnectionCard(
                        state: resolvedLoginFlowState,
                        provider: account.provider,
                        primaryAction: resolvedLoginFlowState == .connected ? checkProviderLogin : startProviderLogin,
                        logoutAction: confirmProviderLogout
                    )

                    profileLocationDisclosure
                }
            } else {
                ProviderDashboardCard(provider: account.provider)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 44)
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
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
            credentialAccessMessage = nil
            showsProfileLocation = false
            didCopyProfileLocation = false
            refreshSavedAPITokenPreview()
        }
        .onChange(of: account.connectionKind) { _, kind in
            selectedConnectionKind = kind
            refreshSavedAPITokenPreview()
        }
    }

    private var setupFooter: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)

            HStack(spacing: 10) {
                if account.provider.performsAutomaticRefresh {
                    Button(action: openPersonalizationSettings) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")

                            Text("Refresh every")
                                .foregroundStyle(.secondary)

                            Text(BrimRefreshInterval.displayTitle(for: refreshIntervalSeconds))
                                .foregroundStyle(.primary)
                                .underline()
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Change refresh frequency")
                } else {
                    Label(
                        account.provider.usesProviderDashboard ? "Usage stays with \(account.provider.displayName)" : "Check on demand",
                        systemImage: account.provider.usesProviderDashboard ? "hand.raised.fill" : "arrow.clockwise"
                    )
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Label(footerPrivacyTitle, systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .help(footerPrivacyHelp)
            }
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.88)
        .frame(maxWidth: .infinity)
        .frame(height: 36, alignment: .bottom)
    }

    private var footerPrivacyTitle: String {
        if account.provider.usesProviderDashboard {
            return "No credentials shared"
        }
        return selectedConnectionKind == .apiToken ? apiCredentialStorageTitle : "Private OAuth profile"
    }

    private var footerPrivacyHelp: String {
        if account.provider.usesProviderDashboard {
            return "Brim opens the provider dashboard and never receives your login."
        }
        return selectedConnectionKind == .apiToken
            ? apiCredentialStorageHelp
            : "Login credentials stay in this account's private Brim profile."
    }

    private var apiCredentialStorageTitle: String {
#if BRIM_CERTIFICATE_FREE_DEBUG
        "Private Debug storage"
#else
        "API key in Keychain"
#endif
    }

    private var apiCredentialStorageHelp: String {
#if BRIM_CERTIFICATE_FREE_DEBUG
        "Certificate-free Debug builds keep API keys in a private sandbox file."
#else
        "API keys stay in Keychain."
#endif
    }

    private var profileLocationDisclosure: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.20)) {
                    showsProfileLocation.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: account.provider.brandColorHex).opacity(0.78))

                    Text("Profile location")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsProfileLocation ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsProfileLocation {
                Rectangle()
                    .fill(Color.primary.opacity(0.065))
                    .frame(height: 1)
                    .padding(.horizontal, 10)

                HStack(spacing: 8) {
                    Text(account.resolvedProviderProfilePath)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer(minLength: 6)

                    Button(action: copyProfileLocation) {
                        Image(systemName: didCopyProfileLocation ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(
                                didCopyProfileLocation
                                    ? Color(hex: account.provider.brandColorHex)
                                    : Color.secondary
                            )
                            .frame(width: 24, height: 24)
                            .background(Color.primary.opacity(0.045), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy profile location")
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .frame(height: 38)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func copyProfileLocation() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(account.resolvedProviderProfilePath, forType: .string)
        didCopyProfileLocation = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            didCopyProfileLocation = false
        }
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
        case .notConnected, .manual, .dashboardOnly:
            return .idle
        }
    }

    private var trimmedAPIToken: String {
        apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var apiTokenValidation: APITokenValidation {
        APITokenValidator.validate(trimmedAPIToken, provider: account.provider)
    }

    private var apiTokenValidationMessage: String? {
        guard !trimmedAPIToken.isEmpty, case .invalid(let message) = apiTokenValidation else {
            return nil
        }

        return message
    }

    private var hasSavedAPIToken: Bool {
        account.credentialID != nil
    }

    private var apiTokenStatusKind: ConnectionStatusKind {
        if apiTokenIsSaving {
            return .working
        }

        if credentialAccessMessage != nil {
            return .needsAttention
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
            return .needsAttention
        case .ready, .manual, .dashboardOnly:
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
            return "Validating the API token with \(account.provider.displayName)."
        }

        if account.connectionKind == .apiToken, hasSavedAPIToken {
            if let credentialAccessMessage {
                return credentialAccessMessage
            }
            if account.refreshStatus == .waitingForQuotaSource {
                return "Checking the saved token."
            }
            if let message = account.refreshMessage {
                return message
            }

            return "Saved in private credential storage for this account."
        }

        return "Save a valid \(account.provider.displayName) API key for this account."
    }

    private func switchToSupportedConnection() {
        let supportedConnectionKind = account.provider.supportedConnectionKind
        if account.connectionKind == .apiToken {
            do {
                try CredentialStore.shared.deleteAPIToken(credentialID: account.credentialID)
            } catch {
                credentialAccessMessage = error.localizedDescription
                return
            }
        }

        var migratedAccount = account.disconnectedProviderAccount(
            message: supportedConnectionKind == .login
                ? "Sign in with \(account.provider.displayName) to connect this account."
                : "Add a \(account.provider.displayName) API key to connect this account."
        )
        migratedAccount.connectionKind = supportedConnectionKind
        store.updateAccount(migratedAccount)
        selectedConnectionKind = supportedConnectionKind
        savedAPITokenPreview = nil
        credentialAccessMessage = nil
    }

    private func startProviderLogin() {
        let initiatingAccountID = account.id
        let initiatingAccountSnapshot = account
        let expandedProfilePath = QuotaFormatting.expandedHomePath(account.resolvedProviderProfilePath)
        selectedConnectionKind = .login
        account.connectionKind = .login
        loginFlowState = .openingBrowser
        account.refreshStatus = .waitingForQuotaSource
        account.lastRefreshAttemptAt = Date()
        account.refreshMessage = "Opening Codex sign-in in your browser."

        Task { @MainActor in
            let loginResult = await CodexCommandRunner.startBrowserLogin(profilePath: expandedProfilePath)
            if loginResult.exitCode == 0 {
                guard var initiatingAccount = store.accounts.first(where: { $0.id == initiatingAccountID }) else {
                    do {
                        try ProviderProfileStorage.removeOwnedProfileIfUnreferenced(
                            for: initiatingAccountSnapshot,
                            remainingAccounts: store.accounts
                        )
                    } catch {
                        Self.logger.error("Could not clean up a login profile after its account disappeared: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                initiatingAccount.connectionKind = .login
                initiatingAccount.refreshStatus = .ready
                initiatingAccount.refreshMessage = "\(initiatingAccount.provider.displayName) login is connected."
                initiatingAccount.lastSuccessfulRefreshAt = Date()
                store.updateAccount(initiatingAccount)
                await store.refreshAccount(id: initiatingAccountID)
                if account.id == initiatingAccountID {
                    loginFlowState = .connected
                }
                return
            }

            markLoginFailure(loginResult, accountID: initiatingAccountID)
        }
    }

    private func checkProviderLogin() {
        let initiatingAccountID = account.id
        let expandedProfilePath = QuotaFormatting.expandedHomePath(account.resolvedProviderProfilePath)
        selectedConnectionKind = .login
        account.connectionKind = .login
        loginFlowState = .checking
        account.refreshStatus = .waitingForQuotaSource
        account.lastRefreshAttemptAt = Date()

        Task { @MainActor in
            if CodexProfileAuthStore.hasUsableTokens(profilePath: expandedProfilePath) {
                await store.refreshAccount(id: initiatingAccountID)
                if account.id == initiatingAccountID {
                    loginFlowState = .connected
                }
            } else {
                guard var initiatingAccount = store.accounts.first(where: { $0.id == initiatingAccountID }) else {
                    return
                }
                initiatingAccount.hasUsageSnapshot = false
                initiatingAccount.refreshStatus = .notConnected
                initiatingAccount.refreshMessage = "Sign in with \(initiatingAccount.provider.displayName) to connect this account."
                store.updateAccount(initiatingAccount)
                if account.id == initiatingAccountID {
                    loginFlowState = .idle
                }
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
        let initiatingAccountID = account.id
        let initiatingAccountSnapshot = account
        selectedConnectionKind = .login
        account.connectionKind = .login
        loginFlowState = .loggingOut
        account.refreshStatus = .waitingForQuotaSource
        account.refreshMessage = "Signing out of \(account.provider.displayName)."
        account.lastRefreshAttemptAt = Date()

        Task { @MainActor in
            do {
                try ProviderProfileStorage.removeOwnedAuthIfPresent(for: initiatingAccountSnapshot)
            } catch {
                markLoginFailure(
                    CommandResult(
                        exitCode: -1,
                        standardOutput: "",
                        standardError: "Brim could not remove this Codex profile's auth file."
                    ),
                    accountID: initiatingAccountID
                )
                return
            }

            guard let initiatingAccount = store.accounts.first(where: { $0.id == initiatingAccountID }) else {
                return
            }
            let disconnectedAccount = initiatingAccount.disconnectedProviderAccount(
                message: "Sign in with \(initiatingAccount.provider.displayName) to connect this account."
            )
            store.updateAccount(disconnectedAccount)
            if account.id == initiatingAccountID {
                loginFlowState = .idle
            }
        }
    }

    private func saveAPIToken() {
        guard !apiTokenIsSaving else {
            return
        }

        let token = trimmedAPIToken
        let initiatingAccountID = account.id
        let initiatingProvider = account.provider
        guard case .valid = APITokenValidator.validate(token, provider: account.provider) else {
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
                try await APITokenValidationClient().validate(token, provider: initiatingProvider)
                let credentialID = try CredentialStore.shared.saveAPIToken(token, accountID: initiatingAccountID)
                guard var initiatingAccount = store.accounts.first(where: { $0.id == initiatingAccountID }) else {
                    do {
                        try CredentialStore.shared.deleteAPIToken(credentialID: credentialID)
                    } catch {
                        Self.logger.error("Could not remove credential after its account disappeared: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }

                initiatingAccount.connectionKind = .apiToken
                initiatingAccount.credentialID = credentialID
                initiatingAccount.accountEmail = nil
                initiatingAccount.providerAccountID = nil
                initiatingAccount.hasUsageSnapshot = false
                initiatingAccount.refreshStatus = .waitingForQuotaSource
                initiatingAccount.refreshMessage = "API token saved. Checking live rate limits."
                initiatingAccount.lastSuccessfulRefreshAt = nil
                store.updateAccount(initiatingAccount)
                if account.id == initiatingAccountID {
                    apiToken = ""
                    didCopyAPIToken = false
                    savedAPITokenPreview = APITokenPreview.mask(token)
                    credentialAccessMessage = nil
                }
                await store.refreshAccount(id: initiatingAccountID)
            } catch {
                if var initiatingAccount = store.accounts.first(where: { $0.id == initiatingAccountID }) {
                    initiatingAccount.connectionKind = .apiToken
                    initiatingAccount.refreshStatus = .refreshFailed
                    initiatingAccount.refreshMessage = (error as? APITokenValidationError)?.message
                        ?? error.localizedDescription
                    store.updateAccount(initiatingAccount)
                }
            }

            if account.id == initiatingAccountID {
                apiTokenIsSaving = false
            }
        }
    }

    private func refreshAPITokenAccount() {
        let initiatingAccountID = account.id
        selectedConnectionKind = .apiToken
        account.connectionKind = .apiToken
        account.refreshStatus = .waitingForQuotaSource
        account.refreshMessage = nil
        account.lastRefreshAttemptAt = Date()

        Task {
            await store.refreshAccount(id: initiatingAccountID)
        }
    }

    private func confirmRevokeAPIToken() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Revoke API token?"
        alert.informativeText = "This removes the saved token for \(account.name) from this Mac."
        alert.addButton(withTitle: "Revoke")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        revokeAPIToken()
    }

    private func revokeAPIToken() {
        do {
            try CredentialStore.shared.deleteAPIToken(credentialID: account.credentialID)
        } catch {
            credentialAccessMessage = error.localizedDescription
            return
        }

        let disconnectedAccount = account.disconnectedProviderAccount(
            message: "Add an API token to reconnect this account."
        )
        selectedConnectionKind = .apiToken
        store.updateAccount(disconnectedAccount)
        didCopyAPIToken = false
        savedAPITokenPreview = nil
        credentialAccessMessage = nil
    }

    private func copySavedAPIToken() {
        guard case .token(let token) = CredentialStore.shared.readAPIToken(credentialID: account.credentialID) else {
            refreshSavedAPITokenPreview()
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
        guard account.connectionKind == .apiToken, account.provider.supports(.apiToken) else {
            savedAPITokenPreview = nil
            credentialAccessMessage = nil
            return
        }

        switch CredentialStore.shared.readAPIToken(credentialID: account.credentialID) {
        case .token(let token):
            savedAPITokenPreview = APITokenPreview.mask(token)
            credentialAccessMessage = nil
        case .missing:
            savedAPITokenPreview = nil
            credentialAccessMessage = account.credentialID == nil
                ? nil
                : "The saved API token is missing from local credential storage. Save it again."
        case .inaccessible(let message):
            savedAPITokenPreview = "Saved token unavailable"
            credentialAccessMessage = message
        }
    }

    private func markLoginFailure(_ result: CommandResult, accountID: QuotaAccount.ID) {
        let message = commandMessage(from: result)
        if var initiatingAccount = store.accounts.first(where: { $0.id == accountID }) {
            initiatingAccount.refreshStatus = .refreshFailed
            initiatingAccount.refreshMessage = message
            store.updateAccount(initiatingAccount)
        }
        if account.id == accountID {
            loginFlowState = .failed(message)
        }
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

    private var accent: Color {
        Color(hex: provider.brandColorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConnectionStatusRow(
                icon: "person.crop.circle.badge.checkmark",
                title: "Use \(provider.displayName) sign-in",
                message: state.statusLine(provider: provider),
                state: state.statusKind
            )

            if state == .connected {
                HStack(spacing: 10) {
                    ConnectionActionButton(
                        title: "Refresh",
                        icon: "arrow.clockwise",
                        isEnabled: true,
                        role: .primary,
                        tint: accent,
                        expands: false,
                        action: primaryAction
                    )

                    ConnectionActionButton(
                        title: "Log out",
                        icon: "rectangle.portrait.and.arrow.right",
                        isEnabled: true,
                        role: .destructive,
                        tint: accent,
                        expands: false,
                        action: logoutAction
                    )

                    Spacer(minLength: 0)
                }
                .padding(.leading, 39)
            } else {
                PrimaryConnectionButton(
                    title: state.buttonTitle(provider: provider),
                    isWorking: state.isWorking,
                    action: primaryAction
                )
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.075),
                            Color.primary.opacity(0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.13), lineWidth: 1)
        }
    }
}

enum APITokenValidation: Equatable {
    case empty
    case valid
    case invalid(String)
}

enum APITokenValidator {
    static func validate(_ token: String, provider: QuotaProviderKind) -> APITokenValidation {
        guard !token.isEmpty else {
            return .empty
        }

        guard token == token.trimmingCharacters(in: .whitespacesAndNewlines),
              token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        else {
            return .invalid("Paste the token without spaces or line breaks.")
        }

        guard provider.supportedConnectionKind == .apiToken else {
            return .invalid("\(provider.displayName) accounts connect with Login, not an API key.")
        }

        guard token.count >= 24 else {
            return .invalid("That key looks too short.")
        }

        guard token.unicodeScalars.allSatisfy({ scalar in
            scalar.value >= 0x21 && scalar.value <= 0x7E
        }) else {
            return .invalid("That key contains an unsupported character.")
        }

        return .valid
    }
}

private enum APITokenValidationError: Error {
    case unsupported(String)
    case rejected(String)
    case server(String, Int)
    case network(String)

    var message: String {
        switch self {
        case .unsupported(let providerName):
            return "\(providerName) accounts do not support API-token connections."
        case .rejected(let providerName):
            return "\(providerName) rejected this API token."
        case .server(let providerName, let statusCode):
            return "Could not validate API token. \(providerName) returned HTTP \(statusCode)."
        case .network(let message):
            return "Could not validate API token: \(message)"
        }
    }
}

struct APITokenValidationClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validate(_ token: String, provider: QuotaProviderKind) async throws {
        var request: URLRequest
        switch provider {
        case .codex, .chatgpt, .claude:
            throw APITokenValidationError.unsupported(provider.displayName)
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!)
            request.setValue(token, forHTTPHeaderField: "x-goog-api-key")
        }
        request.httpMethod = "GET"
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
                throw APITokenValidationError.rejected(provider.displayName)
            default:
                throw APITokenValidationError.server(provider.displayName, httpResponse.statusCode)
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

private struct ProviderSetupTitle: View {
    var provider: QuotaProviderKind

    var body: some View {
        HStack(spacing: 10) {
            ProviderLogoMark(provider: provider, size: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(provider.displayName) setup")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(setupSubtitle)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(hex: provider.brandColorHex))
            }

            Spacer()
        }
    }

    private var setupSubtitle: String {
        switch provider {
        case .codex:
            return "Live agentic limits"
        case .chatgpt:
            return "Chat usage dashboard"
        case .claude:
            return "Shared Claude + Claude Code limits"
        case .gemini:
            return "Google AI project key"
        }
    }
}

private struct ProviderDashboardCard: View {
    var provider: QuotaProviderKind

    private var accent: Color {
        Color(hex: provider.brandColorHex)
    }

    private var dashboardURL: URL {
        provider.usageURL(for: .login)!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConnectionStatusRow(
                icon: provider == .claude ? "sparkles" : "bubble.left.and.bubble.right.fill",
                title: "Usage stays in \(provider.displayName)",
                message: dashboardMessage,
                state: .ready
            )

            Link(destination: dashboardURL) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .bold))
                    Text("Open \(provider.displayName) usage")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.72)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(accent.opacity(0.14), lineWidth: 1)
        }
    }

    private var dashboardMessage: String {
        switch provider {
        case .chatgpt:
            return "ChatGPT does not expose ordinary chat limits to Brim. Codex usage remains separate."
        case .claude:
            return "Claude shows the five-hour and weekly limits shared by Claude and Claude Code."
        case .codex, .gemini:
            return "Open the provider dashboard to verify usage."
        }
    }
}

private struct UnsupportedConnectionCard: View {
    var provider: QuotaProviderKind
    var switchAction: () -> Void

    private var supportedConnectionTitle: String {
        provider.supportedConnectionKind.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConnectionStatusRow(
                icon: "exclamationmark.triangle.fill",
                title: "Connection method retired",
                message: provider.supportedConnectionKind == .login
                    ? "API keys cannot read \(provider.displayName) plan usage. This account must use Login."
                    : "\(provider.displayName) accounts connect with an API key, not Login.",
                state: .needsAttention
            )

            ConnectionActionButton(
                title: "Switch to \(supportedConnectionTitle)",
                icon: "arrow.triangle.2.circlepath",
                isEnabled: true,
                role: .primary,
                action: switchAction
            )
        }
        .padding(14)
        .background(Color.primary.opacity(0.022), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct APITokenConnectionCard: View {
    @Binding var token: String
    var provider: QuotaProviderKind
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
        APITokenValidator.validate(token.trimmingCharacters(in: .whitespacesAndNewlines), provider: provider)
    }

    private var canSave: Bool {
        saveValidation == .valid && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ConnectionStatusRow(
                icon: "key.horizontal",
                title: hasSavedToken ? "Gemini project connected" : "Connect a Gemini project",
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
                        .lineLimit(1)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onChange(of: token) { _, newValue in
                            // Pasted keys often carry newlines/spaces; collapse to one line.
                            let sanitized = newValue.components(separatedBy: .whitespacesAndNewlines).joined()
                            if sanitized != newValue {
                                token = sanitized
                            }
                        }

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
        .background(Color(hex: provider.brandColorHex).opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color(hex: provider.brandColorHex))
                .frame(width: 3)
                .padding(.vertical, 12)
        }
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
    var tint: Color = .primary
    var expands = true
    var action: () -> Void

    private var backgroundColor: Color {
        switch role {
        case .primary:
            return tint.opacity(0.88)
        case .destructive:
            return role.backgroundColor
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))

                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(role.foregroundColor.opacity(isEnabled ? 1 : 0.48))
            .padding(.horizontal, expands ? 10 : 15)
            .frame(minWidth: expands ? 0 : 108, maxWidth: expands ? .infinity : nil)
            .frame(height: 35)
            .background(backgroundColor.opacity(isEnabled ? 1 : 0.48), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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
