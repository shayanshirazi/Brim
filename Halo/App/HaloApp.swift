import AppKit
import SwiftUI

@main
struct HaloApp: App {
    var body: some Scene {
        WindowGroup {
            HaloAppRootView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct HaloAppRootView: View {
    @State private var store: QuotaStore
    @State private var route: AppRoute?

    init() {
        let refreshService = QuotaRefreshService(
            apiTokenIsAvailable: { CredentialStore.shared.hasAPIToken(credentialID: $0) },
            commandRunner: CodexCommandRunner.loginStatus(profilePath:subcommand:)
        )
        _store = State(initialValue: QuotaStore(repository: QuotaRepository(), refreshService: refreshService))
    }

    var body: some View {
        AccountSettingsView(route: route)
            .environmentObject(store)
            .onAppear {
                NSApplication.shared.applicationIconImage = NSImage(named: "HaloLogo")
            }
            .onOpenURL { url in
                route = AppRoute.parse(url)
            }
    }
}
