import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum BrimSettingsTab: CaseIterable, Hashable {
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

struct BrimSettingsView: View {
    @EnvironmentObject private var store: QuotaStore
    @Binding var selectedTab: BrimSettingsTab
    @State private var transferNotice: AccountTransferNotice?

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

                Text(store.accounts.count.brimAccountCountText)
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
            let accountsTransferData = try store.exportAccountsTransferData()
            try withSecurityScopedAccess(to: url) {
                try accountsTransferData.write(to: url, options: [.atomic])
            }
            transferNotice = .success("Exported \(store.accounts.count.brimAccountCountText).")
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
            let previousCredentialIDs = store.accounts.compactMap(\.credentialID)
            let accountsTransferData = try withSecurityScopedAccess(to: url) {
                try Data(contentsOf: url)
            }
            let accountsImportPreview = try QuotaAccountsTransferPayload.importPreview(from: accountsTransferData)
            guard confirmImport(credentialCount: previousCredentialIDs.count, preview: accountsImportPreview) else {
                return
            }

            try store.importAccountsTransferData(accountsTransferData)
            previousCredentialIDs.forEach { CredentialStore.shared.deleteAPIToken(credentialID: $0) }
            transferNotice = .success("Imported \(store.accounts.count.brimAccountCountText). Reconnect secrets on this device.")
        } catch {
            transferNotice = .failure("That file is not a Brim accounts export.")
        }
    }

    private func confirmImport(credentialCount: Int, preview accountsImportPreview: QuotaAccountsImportPreview) -> Bool {
        let alert = NSAlert()
        let credentialText = credentialCount == 0
            ? ""
            : " Local API tokens for the replaced accounts will be removed from Keychain."
        alert.alertStyle = .warning
        alert.messageText = "Replace current accounts?"
        alert.informativeText = "This import contains \(accountsImportPreview.accountCount.brimAccountCountText). It will replace the \(store.accounts.count.brimAccountCountText) currently in Brim.\(credentialText)"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func withSecurityScopedAccess<T>(to url: URL, _ operation: () throws -> T) rethrows -> T {
        let didAccessSecurityScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try operation()
    }

    private func openGitHub() {
        NSWorkspace.shared.open(githubURL)
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
