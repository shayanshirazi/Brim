import AppKit
import OSLog
import SwiftUI

@main
struct BrimApp: App {
    private static let credentialMigrationLogger = Logger(
        subsystem: "dev.brim.app",
        category: "credential-migration"
    )

    @NSApplicationDelegateAdaptor(BrimApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store: QuotaStore
    @StateObject private var navigation: BrimNavigationModel
    @StateObject private var menuBarController: BrimMenuBarController

    init() {
        let repository = QuotaRepository()
        let savedAccounts = repository.load().state.accounts
        for account in savedAccounts where account.provider.usesProviderDashboard {
            do {
                // Older builds used the account UUID as the Keychain account value.
                try CredentialStore.shared.deleteAPIToken(credentialID: account.id.uuidString)
            } catch {
                Self.credentialMigrationLogger.error(
                    "retired_api_token_cleanup_failed account_id=\(account.id.uuidString, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        do {
            try ProviderProfileStorage.removeProfilesForDashboardOnlyProviders()
        } catch {
            Self.credentialMigrationLogger.error(
                "retired_profile_cleanup_failed error=\(error.localizedDescription, privacy: .public)"
            )
        }

        let refreshService = QuotaRefreshService(
            apiTokenProvider: { CredentialStore.shared.readAPIToken(credentialID: $0) }
        )
        let store = QuotaStore(
            repository: repository,
            refreshService: refreshService
        )
        let navigation = BrimNavigationModel()
        _store = StateObject(wrappedValue: store)
        _navigation = StateObject(wrappedValue: navigation)
        _menuBarController = StateObject(
            wrappedValue: BrimMenuBarController(
                store: store,
                navigation: navigation
            )
        )
    }

    var body: some Scene {
        Window("Brim", id: BrimSceneID.mainWindow) {
            BrimAppRootView(
                navigation: navigation,
                menuBarController: menuBarController
            )
                .environmentObject(store)
                .frame(
                    minWidth: BrimWindowMetrics.minWidth,
                    maxWidth: .infinity,
                    minHeight: BrimWindowMetrics.minHeight,
                    maxHeight: .infinity
                )
                .background(WindowSizeConfigurator())
                .background(BrimMenuBarInstaller(controller: menuBarController))
        }
        .defaultSize(width: BrimWindowMetrics.defaultWidth, height: BrimWindowMetrics.defaultHeight)
        .windowStyle(.hiddenTitleBar)
    }
}

@MainActor
final class BrimApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private enum BrimSceneID {
    static let mainWindow = "main-window"
}

@MainActor
final class BrimNavigationModel: ObservableObject {
    @Published private(set) var route: AppRoute?

    func navigate(to route: AppRoute) {
        // Reset first so selecting the same destination twice still replays the
        // navigation after the user has moved elsewhere inside the window.
        self.route = nil
        Task { @MainActor [weak self] in
            self?.route = route
        }
    }
}

enum BrimWindowMetrics {
    static let defaultWidth: CGFloat = 980
    static let defaultHeight: CGFloat = 620
    static let minWidth: CGFloat = 980
    static let minHeight: CGFloat = 620
    static let maxWidth: CGFloat = 1280
    static let maxHeight: CGFloat = 820
}

private struct WindowSizeConfigurator: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(for: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView, coordinator: context.coordinator)
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                return
            }

            let minSize = NSSize(width: BrimWindowMetrics.minWidth, height: BrimWindowMetrics.minHeight)
            let maxSize = NSSize(width: BrimWindowMetrics.maxWidth, height: BrimWindowMetrics.maxHeight)
            window.minSize = minSize
            window.maxSize = maxSize
            window.styleMask.insert(.resizable)

            guard !coordinator.didApplyInitialSize else {
                return
            }
            coordinator.didApplyInitialSize = true

            let currentSize = window.frame.size
            let targetSize = NSSize(
                width: min(max(currentSize.width, BrimWindowMetrics.defaultWidth), BrimWindowMetrics.maxWidth),
                height: min(max(currentSize.height, BrimWindowMetrics.defaultHeight), BrimWindowMetrics.maxHeight)
            )

            guard currentSize != targetSize else {
                return
            }

            window.setContentSize(targetSize)
            window.center()
        }
    }

    final class Coordinator {
        var didApplyInitialSize = false
    }
}

private struct BrimAppRootView: View {
    @ObservedObject var navigation: BrimNavigationModel
    @ObservedObject var menuBarController: BrimMenuBarController

    var body: some View {
        AccountSettingsView(route: navigation.route)
            .onOpenURL { url in
                guard let route = AppRoute.parse(url) else {
                    return
                }

                navigation.navigate(to: route)
            }
    }
}
