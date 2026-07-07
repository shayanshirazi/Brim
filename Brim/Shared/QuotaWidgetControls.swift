import SwiftUI
import WidgetKit

public struct QuotaAccountSlotView: View {
    public var account: QuotaAccount?
    public var family: WidgetFamilyShape
    public var isSelected: Bool
    public var isTextHidden: Bool

    public init(
        account: QuotaAccount?,
        family: WidgetFamilyShape,
        isSelected: Bool = false,
        isTextHidden: Bool = false
    ) {
        self.account = account
        self.family = family
        self.isSelected = isSelected
        self.isTextHidden = isTextHidden
    }

    public var body: some View {
        VStack(spacing: family.accountLabelSpacing) {
            NestedQuotaRingView(
                account: account,
                diameter: family.ringDiameter,
                isSelected: isSelected
            )
            .frame(width: family.ringSlotWidth, height: family.ringSlotWidth)

            VStack(spacing: 1) {
                Text(account == nil ? "" : (isTextHidden ? "***" : (account?.sessionPercentText ?? "")))
                    .font(.system(size: family.sessionLabelFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(account == nil ? 0 : 0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(height: family.sessionLabelHeight)

                Text(account == nil ? "" : (isTextHidden ? "***" : (account?.remainingPercentText ?? "")))
                    .font(.system(size: family.weeklyLabelFontSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(account == nil ? 0 : 0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(height: family.weeklyLabelHeight)
            }
            .frame(width: family.accountSlotWidth)
        }
        .frame(width: family.accountSlotWidth)
    }
}

public struct PagerChevron: View {
    public var direction: PagerDirection
    public var family: WidgetFamilyShape
    public var isVisible: Bool

    public init(direction: PagerDirection, family: WidgetFamilyShape, isVisible: Bool) {
        self.direction = direction
        self.family = family
        self.isVisible = isVisible
    }

    public var body: some View {
        Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
            .font(.system(size: family.pagerIconSize, weight: .bold, design: .rounded))
            .foregroundStyle(.primary.opacity(isVisible ? 0.55 : 0))
            .frame(width: family.pagerButtonSize, height: family.pagerButtonSize)
    }
}
