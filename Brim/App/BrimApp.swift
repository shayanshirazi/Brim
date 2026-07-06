import AppKit
import SwiftUI

@main
struct BrimApp: App {
    var body: some Scene {
        WindowGroup {
            BrimAppRootView()
                .frame(width: BrimWindowMetrics.defaultWidth, height: BrimWindowMetrics.defaultHeight)
                .background(WindowSizeConfigurator())
        }
        .defaultSize(width: BrimWindowMetrics.defaultWidth, height: BrimWindowMetrics.defaultHeight)
        .windowStyle(.hiddenTitleBar)
    }
}

private enum BrimWindowMetrics {
    static let defaultWidth: CGFloat = 980
    static let defaultHeight: CGFloat = 620
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

            let targetSize = NSSize(
                width: BrimWindowMetrics.defaultWidth,
                height: BrimWindowMetrics.defaultHeight
            )
            window.minSize = targetSize
            window.maxSize = targetSize
            window.styleMask.remove(.resizable)

            guard !coordinator.didApplyInitialSize else {
                return
            }
            coordinator.didApplyInitialSize = true

            let currentSize = window.frame.size

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
                NSApplication.shared.applicationIconImage = NSImage(named: "BrimLogo")
            }
            .onOpenURL { url in
                route = AppRoute.parse(url)
            }
    }
}
