import AppIntents
import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let accounts: [QuotaAccount]
    let selectedAccountID: QuotaAccount.ID?
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(
            date: Date(),
            accounts: QuotaAccount.examples,
            selectedAccountID: QuotaAccount.examples.first?.id
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
        let accounts = QuotaStore.widgetSnapshot()
        return QuotaEntry(
            date: Date(),
            accounts: accounts,
            selectedAccountID: QuotaStore.selectedAccountID() ?? accounts.first?.id
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
            QuotaStore.setSelectedAccountID(uuid)
        }
        return .result()
    }
}

struct HaloWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    let entry: QuotaEntry

    var body: some View {
        let family: WidgetFamilyShape = widgetFamily == .systemSmall ? .small : .medium

        InteractiveQuotaWidgetCard(
            accounts: entry.accounts,
            family: family,
            selectedAccountID: entry.selectedAccountID
        )
        .containerBackground(for: .widget) {
            Color.clear
        }
    }
}

private struct InteractiveQuotaWidgetCard: View {
    var accounts: [QuotaAccount]
    var family: WidgetFamilyShape
    var selectedAccountID: QuotaAccount.ID?

    private var selectedAccount: QuotaAccount? {
        accounts.first(where: { $0.id == selectedAccountID }) ?? accounts.first
    }

    var body: some View {
        let slots = accounts.prefix(family.slotCount).map(Optional.some)
        let emptySlots = Array<QuotaAccount?>(repeating: nil, count: max(0, family.slotCount - slots.count))
        let visibleAccounts = slots + emptySlots

        ZStack(alignment: .topTrailing) {
            HaloBackground(cornerRadius: family.cornerRadius)

            VStack(spacing: family.verticalSpacing) {
                Spacer(minLength: 0)

                HStack(spacing: family.ringSpacing) {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.offset) { _, account in
                        if let account {
                            Button(intent: SelectQuotaAccountIntent(accountID: account.id.uuidString)) {
                                NestedQuotaRingView(
                                    account: account,
                                    diameter: family.ringDiameter,
                                    isSelected: account.id == selectedAccount?.id
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(width: family.ringSlotWidth, height: family.ringSlotWidth)
                        } else {
                            NestedQuotaRingView(account: nil, diameter: family.ringDiameter)
                                .frame(width: family.ringSlotWidth, height: family.ringSlotWidth)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if family.showsDetails, let selectedAccount {
                    QuotaWidgetDetail(account: selectedAccount)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, family.horizontalPadding)
            .padding(.vertical, family.verticalPadding)

            if let editURL = URL(string: "halo://accounts") {
                Link(destination: editURL) {
                    Image(systemName: "pencil")
                        .font(.system(size: family.editIconSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: family.editButtonSize, height: family.editButtonSize)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, family.editButtonPadding)
                .padding(.trailing, family.editButtonPadding)
            }
        }
    }
}

@main
struct HaloWidget: Widget {
    let kind = "HaloWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in
            HaloWidgetView(entry: entry)
        }
        .configurationDisplayName("Halo")
        .description("Track weekly quota across local accounts.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
