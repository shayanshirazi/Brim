import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum BrimRefreshInterval: Int, CaseIterable, Identifiable {
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1800

    static let storageKey = "brim.refresh-interval-seconds.v1"
    static let modeStorageKey = "brim.refresh-mode.v1"
    static let defaultSeconds = BrimRefreshInterval.fiveMinutes.rawValue
    static let minimumSeconds = 60
    static let maximumSeconds = 86_400

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        }
    }

    var detail: String {
        switch self {
        case .oneMinute: return "Most current"
        case .fiveMinutes: return "Balanced"
        case .fifteenMinutes: return "Quieter"
        case .thirtyMinutes: return "Lightest touch"
        }
    }

    static func normalizedSeconds(_ seconds: Int) -> Int {
        min(max(seconds, minimumSeconds), maximumSeconds)
    }

    static func displayTitle(for seconds: Int) -> String {
        let normalizedSeconds = normalizedSeconds(seconds)
        if let preset = BrimRefreshInterval(rawValue: normalizedSeconds) {
            return preset.title
        }

        let minutes = max(1, normalizedSeconds / 60)
        if minutes >= 60, minutes.isMultiple(of: 60) {
            return "\(minutes / 60) hr"
        }

        return "\(minutes) min"
    }
}

private enum RefreshFrequencyMode: String {
    case preset
    case custom
}

private enum CustomRefreshUnit: String, CaseIterable, Identifiable, Hashable {
    case minutes
    case hours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes: return "min"
        case .hours: return "hr"
        }
    }

    var amountRange: ClosedRange<Int> {
        switch self {
        case .minutes: return 1...1440
        case .hours: return 1...24
        }
    }

    func seconds(for amount: Int) -> Int {
        switch self {
        case .minutes: return amount * 60
        case .hours: return amount * 3600
        }
    }
}

struct AccountSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @State private var selectedAccountID: QuotaAccount.ID?
    @State private var showsAddAccountSheet = false
    @State private var showsSettings = false
    @State private var selectedSettingsTab: BrimSettingsTab = .about
    @State private var resizeDragStartWidth: CGFloat?
    @State private var liveSidebarWidth = SplitLayoutMetrics.defaultSidebarWidth
    @AppStorage("brim.sidebar-width.v1") private var storedSidebarWidth = SplitLayoutMetrics.defaultSidebarWidth
    @AppStorage(BrimRefreshInterval.storageKey) private var refreshIntervalSeconds = BrimRefreshInterval.defaultSeconds

    var route: AppRoute?
    private var refreshTimer: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(
            every: TimeInterval(BrimRefreshInterval.normalizedSeconds(refreshIntervalSeconds)),
            on: .main,
            in: .common
        )
        .autoconnect()
    }

    private var constrainedSidebarWidth: CGFloat {
        Self.clampedSidebarWidth(liveSidebarWidth)
    }

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

    private var sidebarSelectedAccountID: Binding<QuotaAccount.ID?> {
        Binding(
            get: {
                showsSettings ? nil : selectedAccountID
            },
            set: { accountID in
                selectedAccountID = accountID
            }
        )
    }

    var body: some View {
        Group {
            if store.accounts.isEmpty {
                FirstRunOnboardingView(
                    storageStatus: store.storageStatus,
                    addAccount: addAccount
                )
            } else {
                GeometryReader { geometry in
                    let sidebarWidth = min(
                        constrainedSidebarWidth,
                        max(SplitLayoutMetrics.minSidebarWidth, geometry.size.width - SplitLayoutMetrics.handleWidth)
                    )
                    let contentWidth = max(0, geometry.size.width - sidebarWidth - SplitLayoutMetrics.handleWidth)

                    HStack(spacing: 0) {
                        AccountSidebar(
                            accounts: store.accounts,
                            selectedAccountID: sidebarSelectedAccountID,
                            addAccount: addAccount,
                            removeAccount: removeAccount,
                            moveAccounts: moveAccounts,
                            renameAccount: renameAccount,
                            selectAccount: selectAccount,
                            isSettingsSelected: showsSettings,
                            openSettings: openSettings
                        )
                        .frame(width: sidebarWidth)
                        .transaction { transaction in
                            if resizeDragStartWidth != nil {
                                transaction.animation = nil
                            }
                        }

                        SplitResizeHandle(isDragging: resizeDragStartWidth != nil)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        if resizeDragStartWidth == nil {
                                            resizeDragStartWidth = sidebarWidth
                                        }

                                        let startWidth = resizeDragStartWidth ?? sidebarWidth
                                        setLiveSidebarWidth(startWidth + value.translation.width)
                                    }
                                    .onEnded { _ in
                                        let finalWidth = constrainedSidebarWidth
                                        liveSidebarWidth = finalWidth
                                        storedSidebarWidth = finalWidth
                                        resizeDragStartWidth = nil
                                    }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.snappy(duration: 0.18)) {
                                    liveSidebarWidth = SplitLayoutMetrics.defaultSidebarWidth
                                    storedSidebarWidth = SplitLayoutMetrics.defaultSidebarWidth
                                }
                            }

                        Group {
                            VStack(spacing: 0) {
                                StorageStatusBanner(status: store.storageStatus)

                                if showsSettings {
                                    BrimSettingsView(selectedTab: $selectedSettingsTab)
                                } else if let selectedAccount {
                                    AccountEditor(
                                        account: selectedAccount,
                                        openPersonalizationSettings: openPersonalizationSettings
                                    )
                                } else {
                                    EmptyAccountsView(addAccount: addAccount)
                                }
                            }
                        }
                        .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
                        .clipped()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                    .clipped()
                    .onChange(of: sidebarWidth) { _, width in
                        guard resizeDragStartWidth == nil, abs(width - liveSidebarWidth) >= 0.5 else {
                            return
                        }

                        liveSidebarWidth = width
                        storedSidebarWidth = width
                    }
                }
            }
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
            liveSidebarWidth = Self.clampedSidebarWidth(storedSidebarWidth)
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
            AddAccountSheet { mode in
                createAccount(mode: mode)
                showsAddAccountSheet = false
            }
        }
    }

    private func addAccount() {
        showsAddAccountSheet = true
    }

    private func createAccount(mode: AddAccountCreationMode) {
        store.addAccount(provider: mode.provider, connectionKind: mode.connectionKind)
        selectedAccountID = store.accounts.last?.id
        store.selectAccount(id: selectedAccountID)
        showsSettings = false
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
        showsSettings = false
    }

    private func openSettings() {
        showsSettings = true
    }

    private func openPersonalizationSettings() {
        selectedSettingsTab = .personalization
        showsSettings = true
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
            showsSettings = false
        case nil:
            break
        }
    }

    private static func clampedSidebarWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, SplitLayoutMetrics.minSidebarWidth), SplitLayoutMetrics.maxSidebarWidth)
    }

    private func setLiveSidebarWidth(_ width: CGFloat) {
        let clampedWidth = Self.clampedSidebarWidth(width)
        guard abs(clampedWidth - liveSidebarWidth) >= 0.5 else {
            return
        }

        liveSidebarWidth = clampedWidth
    }
}

private enum SplitLayoutMetrics {
    static let defaultSidebarWidth: CGFloat = 218
    static let minSidebarWidth: CGFloat = 206
    static let maxSidebarWidth: CGFloat = 312
    static let handleWidth: CGFloat = 9
}

private struct SplitResizeHandle: View {
    var isDragging: Bool
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)

            Rectangle()
                .fill(isDragging || isHovering ? Color(hex: "#2CCB68").opacity(0.58) : Color.primary.opacity(0.12))
                .frame(width: isDragging || isHovering ? 2 : 1)
                .animation(.snappy(duration: 0.14), value: isDragging || isHovering)
        }
        .frame(width: SplitLayoutMetrics.handleWidth)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .help("Drag to resize the sidebar. Double-click to reset.")
        .accessibilityLabel("Resize sidebar")
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
            return "Add your first account to start tracking usage."
        case .corrupted:
            return "Saved account data could not be read, so Brim preserved the broken payload and loaded examples."
        case .saveFailed:
            return "Brim could not save the latest account changes."
        case .unavailable:
            return "Shared widget storage is unavailable."
        }
    }
}

private enum BrimSettingsTab: CaseIterable, Hashable {
    case about
    case personalization
    case transfer
    case privacy

    var title: String {
        switch self {
        case .privacy: return "Privacy"
        case .transfer: return "Import / Export"
        case .personalization: return "Personalize"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .privacy: return "lock.shield"
        case .transfer: return "arrow.up.arrow.down"
        case .personalization: return "slider.horizontal.3"
        case .about: return "sparkle.magnifyingglass"
        }
    }
}

private struct BrimSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @Binding var selectedTab: BrimSettingsTab
    @State private var transferNotice: TransferNotice?

    private let githubURL = URL(string: "https://github.com/shayanshirazi/Brim")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                SettingsGearMark(size: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 7) {
                        Text("Settings")
                            .font(.system(size: 30, weight: .black, design: .rounded))

                        BrimVersionBadge()
                            .padding(.top, 3)
                    }

                    Text("Small controls for a small, local-first tool.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#245C3D").opacity(0.72))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color(hex: "#2CCB68").opacity(0.12), in: Capsule())
            }

            SettingsTabRail(selectedTab: $selectedTab)

            Group {
                switch selectedTab {
                case .privacy:
                    PrivacySettingsTab()
                case .transfer:
                    TransferSettingsTab(
                        accountCount: store.accounts.count,
                        notice: transferNotice,
                        exportAccounts: exportAccounts,
                        importAccounts: importAccounts
                    )
                case .personalization:
                    PersonalizationSettingsTab()
                case .about:
                    AboutSettingsTab(openGitHub: openGitHub)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func exportAccounts() {
        let panel = NSSavePanel()
        panel.title = "Export Brim accounts"
        panel.nameFieldStringValue = "brim-accounts.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try store.exportAccountsData()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try data.write(to: url, options: [.atomic])
            transferNotice = .success("Exported \(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s").")
        } catch {
            transferNotice = .failure("Could not export accounts.")
        }
    }

    private func importAccounts() {
        let panel = NSOpenPanel()
        panel.title = "Import Brim accounts"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let didAccess = url.startAccessingSecurityScopedResource()
            let previousCredentialIDs = store.accounts.compactMap(\.credentialID)
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let preview = try QuotaAccountsTransferPayload.importPreview(from: data)
            guard confirmImport(credentialCount: previousCredentialIDs.count, preview: preview) else {
                return
            }

            try store.importAccountsData(data)
            previousCredentialIDs.forEach { CredentialStore.shared.deleteAPIToken(credentialID: $0) }
            transferNotice = .success("Imported \(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s"). Reconnect secrets on this device.")
        } catch {
            transferNotice = .failure("That file is not a Brim accounts export.")
        }
    }

    private func confirmImport(credentialCount: Int, preview: QuotaAccountsImportPreview) -> Bool {
        let alert = NSAlert()
        let accountText = "\(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s")"
        let credentialText = credentialCount == 0
            ? ""
            : " Local API tokens for the replaced accounts will be removed from Keychain."
        alert.alertStyle = .warning
        alert.messageText = "Replace current accounts?"
        alert.informativeText = "This import contains \(preview.accountCount) account\(preview.accountCount == 1 ? "" : "s"). It will replace the \(accountText) currently in Brim.\(credentialText)"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func openGitHub() {
        NSWorkspace.shared.open(githubURL)
    }
}

@MainActor
private final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published var notice: String?

    init() {
        refresh()
    }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refresh()
            notice = SMAppService.mainApp.status == .requiresApproval
                ? "Approve Brim in macOS Login Items to finish."
                : nil
        } catch {
            refresh()
            notice = enabled
                ? "macOS could not add Brim to Login Items."
                : "macOS could not remove Brim from Login Items."
        }
    }
}

private struct PersonalizationSettingsTab: View {
    @AppStorage(BrimRefreshInterval.storageKey) private var refreshIntervalSeconds = BrimRefreshInterval.defaultSeconds
    @AppStorage(BrimRefreshInterval.modeStorageKey) private var refreshModeRaw = RefreshFrequencyMode.preset.rawValue
    @AppStorage("brim.refresh-custom-amount.v1") private var customRefreshAmount = 45
    @AppStorage("brim.refresh-custom-unit.v1") private var customRefreshUnitRaw = CustomRefreshUnit.minutes.rawValue
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelHeader(
                icon: "slider.horizontal.3",
                title: "Personalization",
                subtitle: "Tune the small habits that make Brim feel native on this Mac."
            )

            VStack(spacing: 10) {
                PreferenceControlRow(
                    icon: "power",
                    title: "Start Brim on startup",
                    detail: "Open Brim automatically when you sign in to this Mac."
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { launchAtLogin.isEnabled },
                            set: { launchAtLogin.setEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                RefreshFrequencyPreferenceRow(
                    refreshIntervalSeconds: $refreshIntervalSeconds,
                    refreshModeRaw: $refreshModeRaw,
                    customRefreshAmount: $customRefreshAmount,
                    customRefreshUnitRaw: $customRefreshUnitRaw
                )
            }

            if let notice = launchAtLogin.notice {
                SettingsInlineNotice(icon: "info.circle.fill", text: notice)
            }

            Spacer(minLength: 0)
        }
        .panelStyle()
        .onAppear {
            launchAtLogin.refresh()
        }
    }
}

private struct RefreshFrequencyPreferenceRow: View {
    @Binding var refreshIntervalSeconds: Int
    @Binding var refreshModeRaw: String
    @Binding var customRefreshAmount: Int
    @Binding var customRefreshUnitRaw: String

    private static let customSelectionTag = -1

    private var mode: RefreshFrequencyMode {
        RefreshFrequencyMode(rawValue: refreshModeRaw) ?? .preset
    }

    private var customUnit: CustomRefreshUnit {
        CustomRefreshUnit(rawValue: customRefreshUnitRaw) ?? .minutes
    }

    private var isCustomSelected: Bool {
        mode == .custom || BrimRefreshInterval(rawValue: refreshIntervalSeconds) == nil
    }

    private var customSeconds: Int {
        customUnit.seconds(for: clamped(customRefreshAmount, for: customUnit))
    }

    private var selection: Binding<Int> {
        Binding(
            get: {
                if isCustomSelected {
                    return Self.customSelectionTag
                }

                return BrimRefreshInterval(rawValue: refreshIntervalSeconds)?.rawValue
                    ?? Self.customSelectionTag
            },
            set: { nextSelection in
                withAnimation(.snappy(duration: 0.18)) {
                    if nextSelection == Self.customSelectionTag {
                        refreshModeRaw = RefreshFrequencyMode.custom.rawValue
                        refreshIntervalSeconds = BrimRefreshInterval.normalizedSeconds(customSeconds)
                    } else if let interval = BrimRefreshInterval(rawValue: nextSelection) {
                        refreshModeRaw = RefreshFrequencyMode.preset.rawValue
                        refreshIntervalSeconds = interval.rawValue
                    }
                }
            }
        )
    }

    private var amount: Binding<Int> {
        Binding(
            get: { clamped(customRefreshAmount, for: customUnit) },
            set: { nextAmount in
                customRefreshAmount = clamped(nextAmount, for: customUnit)
                refreshModeRaw = RefreshFrequencyMode.custom.rawValue
                refreshIntervalSeconds = BrimRefreshInterval.normalizedSeconds(customSeconds)
            }
        )
    }

    private var unit: Binding<CustomRefreshUnit> {
        Binding(
            get: { customUnit },
            set: { nextUnit in
                let nextAmount = clamped(customRefreshAmount, for: nextUnit)
                customRefreshUnitRaw = nextUnit.rawValue
                customRefreshAmount = nextAmount
                refreshModeRaw = RefreshFrequencyMode.custom.rawValue
                refreshIntervalSeconds = BrimRefreshInterval.normalizedSeconds(nextUnit.seconds(for: nextAmount))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "#2CCB68"))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "#2CCB68").opacity(0.11), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Refresh frequency")
                        .font(.system(size: 13, weight: .bold, design: .rounded))

                    Text("How often Brim checks connected accounts.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Picker("Refresh frequency", selection: selection) {
                    ForEach(BrimRefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval.rawValue)
                    }

                    Text("Custom").tag(Self.customSelectionTag)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 356)
            }

            if isCustomSelected {
                customEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCustomSelected ? Color(hex: "#2CCB68").opacity(0.16) : Color.primary.opacity(0.055), lineWidth: 1)
        }
        .animation(.snappy(duration: 0.18), value: isCustomSelected)
    }

    private var customEditor: some View {
        HStack(spacing: 8) {
            Label("Every", systemImage: "timer")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(width: 72, alignment: .leading)

            Spacer(minLength: 0)

            IntervalAdjustButton(
                icon: "minus",
                isEnabled: amount.wrappedValue > customUnit.amountRange.lowerBound,
                action: { adjustCustomAmount(by: -1) }
            )

            HStack(spacing: 7) {
                TextField("Amount", value: amount, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)

                Picker("Unit", selection: unit) {
                    ForEach(CustomRefreshUnit.allCases) { unit in
                        Text(unit.title).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 88)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 34)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.92), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.065), lineWidth: 1)
            }

            IntervalAdjustButton(
                icon: "plus",
                isEnabled: amount.wrappedValue < customUnit.amountRange.upperBound,
                action: { adjustCustomAmount(by: 1) }
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.46), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
        }
    }

    private func clamped(_ amount: Int, for unit: CustomRefreshUnit) -> Int {
        min(max(amount, unit.amountRange.lowerBound), unit.amountRange.upperBound)
    }

    private func adjustCustomAmount(by delta: Int) {
        amount.wrappedValue = amount.wrappedValue + delta
    }
}

private struct IntervalAdjustButton: View {
    var icon: String
    var isEnabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isEnabled ? Color.primary.opacity(0.58) : Color.primary.opacity(0.22))
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(isEnabled ? 0.045 : 0.022), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(isEnabled ? 0.055 : 0.025), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct PreferenceControlRow<Control: View>: View {
    var icon: String
    var title: String
    var detail: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))
                .frame(width: 32, height: 32)
                .background(Color(hex: "#2CCB68").opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            control()
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        }
    }
}

private struct SettingsInlineNotice: View {
    var icon: String
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))

            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))

            Spacer(minLength: 0)
        }
        .foregroundStyle(Color(hex: "#2F7A4B"))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(hex: "#2CCB68").opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SettingsTabRail: View {
    @Binding var selectedTab: BrimSettingsTab

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BrimSettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))

                        Text(tab.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selectedTab == tab ? Color(hex: "#245C3D") : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        selectedTab == tab ? Color(hex: "#2CCB68").opacity(0.13) : Color.primary.opacity(0.035),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selectedTab == tab ? Color(hex: "#2CCB68").opacity(0.30) : Color.clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PrivacySettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelHeader(
                icon: "lock.shield",
                title: "Privacy policy",
                subtitle: "Brim is designed to keep account details on your Mac."
            )

            VStack(spacing: 10) {
                PrivacyLine(icon: "key.horizontal", title: "Tokens stay in Keychain", detail: "API tokens are saved by macOS Keychain and are not written into widget snapshots or exports.")
                PrivacyLine(icon: "square.stack.3d.up", title: "Widgets receive snapshots", detail: "The widget only gets account names, colors, quota numbers, and display state.")
                PrivacyLine(icon: "arrow.up.doc", title: "Exports skip secrets", detail: "JSON exports move account names, colors, and modes. Emails, profile paths, tokens, and live usage are left on this Mac.")
                PrivacyLine(icon: "chart.bar.xaxis", title: "No analytics", detail: "Brim does not include tracking, analytics, or remote reporting in this app.")
            }

            Spacer(minLength: 0)
        }
        .panelStyle()
    }
}

private struct PrivacyLine: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))
                .frame(width: 30, height: 30)
                .background(Color(hex: "#2CCB68").opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct TransferSettingsTab: View {
    var accountCount: Int
    var notice: TransferNotice?
    var exportAccounts: () -> Void
    var importAccounts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPanelHeader(
                icon: "arrow.up.arrow.down",
                title: "Move accounts",
                subtitle: "Carry Brim account setup between Macs with a JSON file."
            )

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                TransferAction(
                    icon: "square.and.arrow.up",
                    title: "Export JSON",
                    detail: "\(accountCount) account\(accountCount == 1 ? "" : "s"), setup only",
                    color: Color(hex: "#2CCB68"),
                    action: exportAccounts
                )

                TransferAction(
                    icon: "square.and.arrow.down",
                    title: "Import JSON",
                    detail: "Replace accounts on this Mac",
                    color: Color(hex: "#54C7EC"),
                    action: importAccounts
                )
            }
            .padding(.horizontal, 38)
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)

            VStack(spacing: 9) {
                TransferNote(notice: notice)
                    .frame(maxWidth: .infinity)

                Text("Imports replace the current Brim account list. Tokens, login sessions, local profile paths, and live usage are intentionally not portable; reconnect them after import.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430, alignment: .center)
                    .padding(.horizontal, 26)
            }
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panelStyle()
    }
}

private struct TransferAction: View {
    var icon: String
    var title: String
    var detail: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 44, height: 44)
                    .background(color.opacity(0.13), in: Circle())

                VStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 142, height: 142, alignment: .center)
            .background(
                LinearGradient(
                    colors: [color.opacity(0.11), Color.primary.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 142, height: 142)
    }
}

private enum TransferNotice: Equatable {
    case success(String)
    case failure(String)
}

private struct TransferNote: View {
    var notice: TransferNotice?

    var body: some View {
        if let notice {
            HStack(spacing: 9) {
                Image(systemName: icon(for: notice))
                    .font(.system(size: 13, weight: .bold))
                Text(text(for: notice))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(color(for: notice))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(color(for: notice).opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func text(for notice: TransferNotice) -> String {
        switch notice {
        case .success(let text), .failure(let text):
            return text
        }
    }

    private func icon(for notice: TransferNotice) -> String {
        switch notice {
        case .success:
            return "checkmark.seal.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private func color(for notice: TransferNotice) -> Color {
        switch notice {
        case .success:
            return Color(hex: "#2CCB68")
        case .failure:
            return Color(hex: "#FF4D57")
        }
    }
}

private struct AboutSettingsTab: View {
    var openGitHub: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 26) {
                AboutLogoOrbit()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("Brim")
                                .font(.system(size: 46, weight: .black, design: .rounded))
                                .lineLimit(1)

                            BrimVersionBadge()
                                .padding(.top, 8)
                        }

                        Text("A tiny quota instrument for people who like calm tools.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    GitHubStarButton(action: openGitHub)

                    AboutTrustConstellation()
                }
                .frame(width: 330, alignment: .leading)
            }
            .frame(maxWidth: 620, alignment: .center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelStyle()
    }
}

private struct AboutLogoOrbit: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Color(hex: index == 1 ? "#54C7EC" : "#2CCB68")
                            .opacity(0.090 - Double(index) * 0.018),
                        lineWidth: 1
                    )
                    .frame(
                        width: 164 + CGFloat(index * 44),
                        height: 164 + CGFloat(index * 44)
                    )
            }

            BrimLogoMark(size: 116)
                .shadow(color: Color(hex: "#2CCB68").opacity(0.22), radius: 32, y: 14)

            Circle()
                .fill(Color(hex: "#2CCB68").opacity(0.80))
                .frame(width: 8, height: 8)
                .offset(x: 88, y: -62)
                .shadow(color: Color(hex: "#2CCB68").opacity(0.24), radius: 9, y: 2)

            Circle()
                .fill(Color(hex: "#54C7EC").opacity(0.76))
                .frame(width: 6, height: 6)
                .offset(x: -96, y: 48)
                .shadow(color: Color(hex: "#54C7EC").opacity(0.20), radius: 8, y: 2)
        }
        .frame(width: 246, height: 246)
    }
}

private struct AboutTrustConstellation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                AboutTrustChip(icon: "lock.fill", title: "Keychain")
                AboutTrustChip(icon: "macwindow", title: "Snapshots")
                AboutTrustChip(icon: "shippingbox", title: "No secrets")
            }

            Text("Tokens stay in Keychain. Widgets and exports receive snapshots only.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }
}

private struct AboutTrustChip: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))

            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.62))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.40), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(hex: "#2CCB68").opacity(0.13), lineWidth: 1)
        }
        .shadow(color: Color(hex: "#2CCB68").opacity(0.055), radius: 10, y: 4)
    }
}

private struct GitHubStarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "#24292F"))

                    Text("Star")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#24292F"))
                }
                .padding(.horizontal, 12)
                .frame(height: 34)

                Rectangle()
                    .fill(Color(hex: "#D0D7DE"))
                    .frame(width: 1, height: 34)

                Text("shayanshirazi/Brim")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#57606A"))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
            }
            .background(Color(hex: "#F6F8FA"), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(hex: "#D0D7DE"), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Open Brim on GitHub")
    }
}

private struct SettingsPanelHeader: View {
    var icon: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))
                .frame(width: 36, height: 36)
                .background(Color(hex: "#2CCB68").opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
