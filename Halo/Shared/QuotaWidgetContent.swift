import SwiftUI
import WidgetKit

public typealias QuotaAccountSlotDecorator = (QuotaAccount, QuotaAccountSlotView) -> AnyView
public typealias QuotaPagerDecorator = (PagerDirection, PagerChevron) -> AnyView

public struct QuotaWidgetContent: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var accounts: [QuotaAccount]
    public var family: WidgetFamilyShape
    public var selectedAccountID: QuotaAccount.ID?
    public var isAccountTextHidden: Bool
    public var pageIndex: Int
    public var surfaceStyle: QuotaWidgetSurfaceStyle
    public var accountSlotDecorator: QuotaAccountSlotDecorator
    public var pagerDecorator: QuotaPagerDecorator
    public var controls: () -> AnyView

    public init(
        accounts: [QuotaAccount],
        family: WidgetFamilyShape,
        selectedAccountID: QuotaAccount.ID? = nil,
        isAccountTextHidden: Bool = false,
        pageIndex: Int = 0,
        surfaceStyle: QuotaWidgetSurfaceStyle = .editorPreview,
        accountSlotDecorator: @escaping QuotaAccountSlotDecorator = { _, slot in AnyView(slot) },
        pagerDecorator: @escaping QuotaPagerDecorator = { _, chevron in AnyView(chevron) },
        controls: @escaping () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.accounts = accounts
        self.family = family
        self.selectedAccountID = selectedAccountID
        self.isAccountTextHidden = isAccountTextHidden
        self.pageIndex = pageIndex
        self.surfaceStyle = surfaceStyle
        self.accountSlotDecorator = accountSlotDecorator
        self.pagerDecorator = pagerDecorator
        self.controls = controls
    }

    public var body: some View {
        let page = QuotaWidgetPage(accounts: accounts, selectedAccountID: selectedAccountID, pageIndex: pageIndex, pageSize: family.slotCount)
        let visibleAccounts = page.visibleAccounts(paddedTo: family.slotCount)
        let showsPager = accounts.count > family.slotCount

        ZStack(alignment: .bottomTrailing) {
            if surfaceStyle == .editorPreview {
                HaloBackground(cornerRadius: family.cornerRadius)
            }

            HStack(spacing: family.pagerSpacing) {
                renderedPager(.left, showsPager: showsPager)

                HStack(spacing: family.accountSpacing) {
                    ForEach(Array(visibleAccounts.enumerated()), id: \.offset) { _, account in
                        if let account {
                            let slot = QuotaAccountSlotView(
                                account: account,
                                family: family,
                                isSelected: account.id == page.selectedAccount?.id,
                                isTextHidden: isAccountTextHidden
                            )
                            accountSlotDecorator(account, slot)
                        } else {
                            QuotaAccountSlotView(account: nil, family: family)
                        }
                    }
                }

                renderedPager(.right, showsPager: showsPager)
            }
            .padding(.horizontal, family.horizontalPadding)
            .padding(.top, family.verticalPadding)
            .padding(.bottom, family.accountRowBottomPadding)

            if family.showsDetails, let selectedAccount = page.selectedAccount {
                QuotaResetReadout(account: selectedAccount, family: family, isTextHidden: isAccountTextHidden)
                    .padding(.leading, family.resetInfoLeadingPadding)
                    .padding(.bottom, family.resetInfoBottomPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            controls()
                .padding(.bottom, family.controlButtonPadding)
                .padding(.trailing, family.controlButtonPadding)
        }
    }

    private func renderedPager(_ direction: PagerDirection, showsPager: Bool) -> some View {
        let chevron = PagerChevron(direction: direction, family: family, isVisible: showsPager)
        return Group {
            if showsPager {
                pagerDecorator(direction, chevron)
            } else {
                chevron
            }
        }
    }
}

public struct QuotaWidgetPage {
    public var accounts: [QuotaAccount]
    public var selectedAccountID: QuotaAccount.ID?
    public var pageIndex: Int
    public var pageSize: Int

    public var visiblePageIndex: Int {
        let safePageSize = max(1, pageSize)
        let maxPageIndex = max(0, Int(ceil(Double(accounts.count) / Double(safePageSize))) - 1)
        return min(max(0, pageIndex), maxPageIndex)
    }

    public var visibleRealAccounts: [QuotaAccount] {
        let safePageSize = max(1, pageSize)
        let startIndex = visiblePageIndex * safePageSize
        return accounts.dropFirst(startIndex).prefix(safePageSize).map { $0 }
    }

    public var selectedAccount: QuotaAccount? {
        visibleRealAccounts.first(where: { $0.id == selectedAccountID }) ?? visibleRealAccounts.first ?? accounts.first
    }

    public func visibleAccounts(paddedTo count: Int) -> [QuotaAccount?] {
        let slots = visibleRealAccounts.map(Optional.some)
        let emptySlots = Array<QuotaAccount?>(repeating: nil, count: max(0, count - slots.count))
        return slots + emptySlots
    }
}
