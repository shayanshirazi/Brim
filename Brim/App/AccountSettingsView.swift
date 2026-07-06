import AppKit
import Combine
import SwiftUI

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

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
