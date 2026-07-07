import AppIntents
import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let accounts: [QuotaAccount]
    let selectedAccountID: QuotaAccount.ID?
    let isAccountTextHidden: Bool
    let pageIndex: Int
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(
            date: Date(),
            accounts: QuotaAccountDefaults.examples,
            selectedAccountID: QuotaAccountDefaults.examples.first?.id,
            isAccountTextHidden: false,
            pageIndex: 0
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(snapshotEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let entry = snapshotEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func snapshotEntry() -> QuotaEntry {
        let state = QuotaWidgetCommands.snapshot()
        return QuotaEntry(
            date: Date(),
            accounts: state.accounts,
            selectedAccountID: state.selectedAccountID,
            isAccountTextHidden: state.isAccountTextHidden,
            pageIndex: state.widgetPageIndex
        )
    }
}

struct SelectQuotaAccountIntent: AppIntent {
    static var title: LocalizedStringResource = "Select quota account"

    @Parameter(title: "Account ID")
    var accountID: String

    init() {
        accountID = ""
    }

    init(accountID: String) {
        self.accountID = accountID
    }

    func perform() async throws -> some IntentResult {
        if let uuid = UUID(uuidString: accountID) {
            QuotaWidgetCommands.selectAccount(id: uuid)
        }
        return .result()
    }
}

struct ToggleAccountTextVisibilityIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle account text visibility"

    init() {}

    func perform() async throws -> some IntentResult {
        QuotaWidgetCommands.toggleAccountTextHidden()
        return .result()
    }
}

struct MoveWidgetPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Move widget page"

    @Parameter(title: "Offset")
    var offset: Int

    @Parameter(title: "Page size")
    var pageSize: Int

    init() {
        offset = 0
        pageSize = 1
    }

    init(offset: Int, pageSize: Int) {
        self.offset = offset
        self.pageSize = pageSize
    }

    func perform() async throws -> some IntentResult {
        QuotaWidgetCommands.moveWidgetPage(by: offset, pageSize: pageSize)
        return .result()
    }
}

struct BrimWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: QuotaEntry

    var body: some View {
        let family: WidgetFamilyShape = widgetFamily == .systemSmall ? .small : .medium

        QuotaWidgetContent(
            accounts: entry.accounts,
            family: family,
            selectedAccountID: entry.selectedAccountID,
            isAccountTextHidden: false,
            pageIndex: entry.pageIndex,
            surfaceStyle: .none,
            accountSlotDecorator: { account, slot in
                AnyView(
                    Button(intent: SelectQuotaAccountIntent(accountID: account.id.uuidString)) {
                        slot
                    }
                    .buttonStyle(.plain)
                )
            },
            pagerDecorator: { direction, chevron in
                AnyView(
                    Button(intent: MoveWidgetPageIntent(offset: direction == .left ? -1 : 1, pageSize: family.slotCount)) {
                        chevron
                    }
                    .buttonStyle(.plain)
                )
            },
            controls: {
                AnyView(
                    WidgetControls(family: family)
                )
            }
        )
        // Native glass: let the system render the material. A solid-looking result
        // comes from system settings (widget style Monochrome, "Dim widgets on
        // desktop", or Reduce Transparency), not from this code.
        .containerBackground(for: .widget) {
            Color.clear.background(.ultraThinMaterial)
        }
    }
}

private struct WidgetControls: View {
    var family: WidgetFamilyShape

    private var controlForeground: Color {
        Color.primary.opacity(0.55)
    }

    var body: some View {
        if let editURL = URL(string: AppRoute.accounts.urlString) {
            Link(destination: editURL) {
                controlIcon("pencil")
            }
            .buttonStyle(.plain)
        }
    }

    private func controlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: family.controlIconSize + 2, weight: .semibold, design: .rounded))
            .foregroundStyle(controlForeground)
            .frame(width: family.controlButtonSize, height: family.controlButtonSize)
    }
}

@main
struct BrimWidget: Widget {
    let kind = "BrimWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            BrimWidgetView(entry: entry)
        }
        .configurationDisplayName("Brim")
        .description("Track weekly quota across local accounts.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
        // The background must stay removable: on the macOS desktop the system strips
        // it and draws the same frosted glass Apple's widgets get. Forcing it off
        // renders our background as an opaque card instead.
    }
}
