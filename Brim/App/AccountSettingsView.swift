import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var isRefreshingAll = false
    @State private var selectedSettingsTab: BrimSettingsTab = .about
    @State private var resizeDragStartWidth: CGFloat?
    @State private var liveSidebarWidth = SplitLayoutMetrics.defaultSidebarWidth
    @AppStorage("brim.sidebar-width.v2") private var storedSidebarWidth = SplitLayoutMetrics.defaultSidebarWidth

    var route: AppRoute?

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
            if store.accounts.isEmpty, !showsSettings {
                FirstRunOnboardingView(
                    storageStatus: store.storageStatus,
                    addAccount: addAccount,
                    openTransferSettings: openTransferSettings
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
                            openSettings: openSettings,
                            refreshAllAccounts: refreshAllAccounts,
                            isRefreshingAll: isRefreshingAll
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

    private func refreshAllAccounts() {
        guard !isRefreshingAll else {
            return
        }

        isRefreshingAll = true
        Task { @MainActor in
            await store.refreshConnectedAccounts()
            isRefreshingAll = false
        }
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

        let removedAccount = store.accounts[index]
        let remainingAccounts = store.accounts.filter { $0.id != accountID }
        do {
            try LocalAccountSecrets.delete(for: removedAccount, remainingAccounts: remainingAccounts)
        } catch {
            presentLocalSecretDeletionError(error, accountName: removedAccount.name)
            return
        }

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

    private func presentLocalSecretDeletionError(_ error: Error, accountName: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Could not delete \(accountName)"
        alert.informativeText = "Brim kept the account because its local credentials could not be removed. \(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

    private func openTransferSettings() {
        selectedSettingsTab = .transfer
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
        case .account(let accountID):
            let resolvedID = store.accounts.first(where: { $0.id == accountID })?.id
            selectedAccountID = resolvedID ?? store.accounts.first?.id
            if let resolvedID {
                store.selectAccount(id: resolvedID)
            }
            showsSettings = false
        case .menuBarSettings:
            selectedSettingsTab = .menuBar
            showsSettings = true
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
    static let defaultSidebarWidth: CGFloat = 312
    static let minSidebarWidth: CGFloat = 206
    static let maxSidebarWidth: CGFloat = 340
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

private enum BrimSettingsTab: CaseIterable, Hashable {
    case about
    case personalization
    case menuBar
    case transfer
    case privacy

    var title: String {
        switch self {
        case .privacy: return "Privacy"
        case .transfer: return "Sync"
        case .personalization: return "Personalize"
        case .menuBar: return "Menu bar"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .privacy: return "lock.shield"
        case .transfer: return "arrow.up.arrow.down"
        case .personalization: return "slider.horizontal.3"
        case .menuBar: return "menubar.rectangle"
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

            GeometryReader { viewport in
                ScrollView(.vertical) {
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
                        case .menuBar:
                            MenuBarSettingsTab()
                        case .about:
                            AboutSettingsTab(openGitHub: openGitHub)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: viewport.size.height,
                        alignment: .topLeading
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            let accountsBeingReplaced = store.accounts
            let previousCredentialCount = accountsBeingReplaced.compactMap(\.credentialID).count
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let preview = try QuotaAccountsTransferPayload.importPreview(from: data)
            guard confirmImport(credentialCount: previousCredentialCount, preview: preview) else {
                return
            }

            try store.importAccountsData(data)
            let cleanupFailures = LocalAccountSecrets.deleteAllBestEffort(for: accountsBeingReplaced)
            if cleanupFailures.isEmpty {
                transferNotice = .success("Imported \(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s"). Reconnect secrets on this device.")
            } else {
                let failedAccountNames = cleanupFailures.map(\.accountName).joined(separator: ", ")
                transferNotice = .failure(
                    "Accounts were imported, but Brim could not remove local credentials for: \(failedAccountNames)."
                )
            }
        } catch let error as QuotaStoreError {
            transferNotice = .failure(error.localizedDescription)
        } catch let error as QuotaAccountsTransferError {
            transferNotice = .failure(error.localizedDescription)
        } catch {
            transferNotice = .failure("That file is not a Brim accounts export.")
        }
    }

    private func confirmImport(credentialCount: Int, preview: QuotaAccountsImportPreview) -> Bool {
        let alert = NSAlert()
        let accountText = "\(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s")"
        let credentialText = credentialCount == 0
            ? ""
            : " Local API tokens for the replaced accounts will be removed from private credential storage."
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
                title: "Privacy & disclaimer",
                subtitle: "Brim is designed to keep account details on your Mac."
            )

            ScrollView {
                VStack(spacing: 10) {
                    PrivacyLine(icon: "key.horizontal", title: "Credentials stay local", detail: "API keys use private local credential storage (Keychain in signed builds). OAuth login credentials use private, account-specific Brim profile files. Neither is written into exports.")
                    PrivacyLine(icon: "menubar.rectangle", title: "Menu-bar data stays local", detail: "The menu bar reads the same in-memory account state as Brim. It does not create a second snapshot, share data with another process, or receive credentials.")
                    PrivacyLine(icon: "arrow.up.doc", title: "Exports skip secrets", detail: "JSON exports contain account names, colors, and modes only. Emails, profile paths, tokens, and live usage never leave this Mac. You are responsible for any file you choose to export and share.")
                    PrivacyLine(icon: "chart.bar.xaxis", title: "No analytics", detail: "Brim contains no tracking, telemetry, or remote reporting. Authenticated requests go only to Codex for live usage or Google to validate a Gemini project key. ChatGPT and Claude credentials never enter Brim; their usage links open in your browser.")
                    PrivacyLine(icon: "building.2", title: "Third-party services", detail: "Brim is an independent open-source project. It is not affiliated with, endorsed by, or sponsored by OpenAI, Anthropic, or any other provider. Product names and logos are trademarks of their respective owners and are used for identification only. Your use of connected services remains governed by each provider's own terms; you are responsible for ensuring your use complies with them.")
                    PrivacyLine(icon: "exclamationmark.shield", title: "No warranty", detail: "Brim is provided \"as is\" and \"as available\", without warranty of any kind, express or implied, including merchantability, fitness for a particular purpose, accuracy, and non-infringement. Displayed quota and rate-limit figures are estimates derived from provider responses and may be incomplete, delayed, or wrong — do not rely on them for billing, compliance, or any decision with financial consequences.")
                    PrivacyLine(icon: "scalemass", title: "Limitation of liability", detail: "To the maximum extent permitted by law, the authors and contributors of Brim shall not be liable for any direct, indirect, incidental, special, consequential, or exemplary damages — including lost profits, data loss, account suspension, or provider charges — arising from the use of, or inability to use, this software, even if advised of the possibility of such damages. Your sole and exclusive remedy is to stop using the software.")
                    PrivacyLine(icon: "doc.text", title: "Open-source license", detail: "Brim's source code is distributed under its open-source license. That license, including its disclaimer of warranty and limitation of liability, governs your use of the software. By using Brim you accept those terms; if you do not accept them, do not use the software.")
                }
                .padding(.bottom, 4)
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
                title: "Sync",
                subtitle: "Carry Brim account setup between Macs with a JSON file."
            )

            Spacer(minLength: 0)

            HStack(spacing: 24) {
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
            .padding(.horizontal, 30)
            .frame(maxWidth: 470)
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
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 50, height: 50)
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
            .frame(width: 154, height: 154, alignment: .center)
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
        .frame(width: 154, height: 154)
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

struct SettingsPanelHeader: View {
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
