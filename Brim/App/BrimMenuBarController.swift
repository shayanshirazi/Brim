import AppKit
import Combine
import SwiftUI

@MainActor
final class BrimMenuBarController: NSObject, ObservableObject, NSMenuDelegate {
    private let store: QuotaStore
    private let navigation: BrimNavigationModel
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private weak var mainWindow: NSWindow?
    private var stateObserver: AnyCancellable?
    private var defaultsObserver: AnyCancellable?
    private var refreshTimer: AnyCancellable?
    private var scheduledRefreshSeconds: Int?
    private let defaults: UserDefaults

    init(
        store: QuotaStore,
        navigation: BrimNavigationModel,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.navigation = navigation
        self.defaults = defaults
        super.init()
        menu.delegate = self

        stateObserver = store.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusImage()
            }

        defaultsObserver = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: defaults)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleRefreshTimer()
                self?.updateStatusImage()
            }
        scheduleRefreshTimer()
    }

    func install(mainWindow: NSWindow?) {
        if let mainWindow {
            self.mainWindow = mainWindow
            mainWindow.isReleasedWhenClosed = false
        }

        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "dev.brim.app.status-item"
        item.isVisible = true
        item.menu = menu
        item.button?.toolTip = "Brim"
        item.button?.setAccessibilityLabel("Brim")
        statusItem = item
        updateStatusImage()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let preferences = MenuBarPreferences(defaults: defaults)
        let eligibleAccounts = preferences.eligibleAccounts(from: store.accounts)
        let visibleAccounts = preferences.visibleAccounts(from: store.accounts)

        menu.removeAllItems()
        menu.addItem(
            item(
                title: "Open Brim",
                action: #selector(openBrim),
                keyEquivalent: "o"
            )
        )
        menu.addItem(.separator())

        if visibleAccounts.isEmpty {
            let title = store.accounts.isEmpty ? "No accounts yet" : "No accounts selected"
            let emptyItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for account in visibleAccounts {
                let accountItem = item(
                    title: preferences.rowTitle(for: account),
                    action: #selector(openAccount(_:))
                )
                accountItem.representedObject = account.id.uuidString
                accountItem.state = account.id == store.selectedAccountID ? .on : .off
                menu.addItem(accountItem)
            }

            if eligibleAccounts.count > visibleAccounts.count {
                menu.addItem(
                    item(
                        title: "Show all \(eligibleAccounts.count) matching accounts",
                        action: #selector(openBrim)
                    )
                )
            }
        }

        menu.addItem(.separator())
        menu.addItem(item(title: "Refresh Accounts", action: #selector(refreshAccounts)))
        menu.addItem(item(title: "Menu Bar Settings", action: #selector(openMenuBarSettings)))
        menu.addItem(.separator())
        menu.addItem(item(title: "Quit Brim", action: #selector(quit), keyEquivalent: "q"))
    }

    @objc private func openBrim() {
        show(route: .accounts)
    }

    @objc private func openAccount(_ sender: NSMenuItem) {
        guard
            let rawID = sender.representedObject as? String,
            let accountID = UUID(uuidString: rawID)
        else {
            return
        }

        show(route: .account(accountID))
    }

    @objc private func refreshAccounts() {
        Task { @MainActor [weak self] in
            await self?.store.refreshConnectedAccounts()
        }
    }

    @objc private func openMenuBarSettings() {
        show(route: .menuBarSettings)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func item(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func show(route: AppRoute) {
        navigation.navigate(to: route)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = mainWindow ?? Self.findMainWindow() {
            mainWindow = window
            window.makeKeyAndOrderFront(nil)
            return
        }

        guard let url = URL(string: route.urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func updateStatusImage() {
        guard let button = statusItem?.button else {
            return
        }

        let account = MenuBarPreferences(defaults: defaults).iconAccount(
            from: store.accounts,
            selectedAccountID: store.selectedAccountID
        )
        button.image = Self.statusImage(progress: Self.visibleProgress(for: account))
    }

    private func scheduleRefreshTimer() {
        let storedSeconds = defaults.object(forKey: BrimRefreshInterval.storageKey) as? Int
            ?? BrimRefreshInterval.defaultSeconds
        let refreshSeconds = BrimRefreshInterval.normalizedSeconds(storedSeconds)
        guard refreshSeconds != scheduledRefreshSeconds else {
            return
        }

        scheduledRefreshSeconds = refreshSeconds
        refreshTimer = Timer.publish(
            every: TimeInterval(refreshSeconds),
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.store.refreshConnectedAccounts()
            }
        }
    }

    private static func visibleProgress(for account: QuotaAccount?) -> Double {
        guard let account, account.hasUsageSnapshot, !account.refreshStatus.hidesQuotaDetails else {
            return 0
        }

        return max(0, min(1, account.sessionRemainingFraction))
    }

    private static func statusImage(progress: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.5

            NSColor.black.withAlphaComponent(0.32).setStroke()
            let track = NSBezierPath()
            track.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 0,
                endAngle: 360
            )
            track.lineWidth = 2
            track.stroke()

            if progress > 0 {
                NSColor.black.setStroke()
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - (360 * progress),
                    clockwise: true
                )
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                arc.stroke()
            }

            NSColor.black.setFill()
            NSBezierPath(
                ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)
            ).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Brim"
        return image
    }

    private static func findMainWindow() -> NSWindow? {
        NSApplication.shared.windows.first {
            $0.title == "Brim" && $0.canBecomeKey
        }
    }
}

struct BrimMenuBarInstaller: NSViewRepresentable {
    @ObservedObject var controller: BrimMenuBarController

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        install(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        install(from: nsView)
    }

    private func install(from view: NSView) {
        DispatchQueue.main.async {
            controller.install(mainWindow: view.window)
        }
    }
}
