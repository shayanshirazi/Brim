import SwiftUI
import WidgetKit

public struct QuotaAccountSlotView: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

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

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var labelColor: Color {
        isVibrant ? Color(hex: "#24586E") : Color.white
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
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(account.map { QuotaFormatting.sessionWindowLabel(for: $0) } ?? "")
                        .font(.system(size: family.weeklyLabelFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(account == nil ? "" : (isTextHidden ? "***" : (account?.sessionPercentText ?? "")))
                        .font(.system(size: family.sessionLabelFontSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(height: family.sessionLabelHeight)

                Text(account == nil ? "" : (isTextHidden ? "***" : "weekly \(account?.remainingPercentText ?? "")"))
                    .font(.system(size: family.weeklyLabelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(height: family.weeklyLabelHeight)
            }
            .frame(width: family.accountSlotWidth)
        }
        .frame(width: family.accountSlotWidth)
    }
}

public struct QuotaResetReadout: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount
    public var family: WidgetFamilyShape
    public var isTextHidden: Bool

    public init(account: QuotaAccount, family: WidgetFamilyShape, isTextHidden: Bool = false) {
        self.account = account
        self.family = family
        self.isTextHidden = isTextHidden
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var labelColor: Color {
        isVibrant ? Color(hex: "#24586E") : Color.white
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(isTextHidden ? "***" : "Weekly reset in \(account.weeklyResetRelativeText())")
                .font(.system(size: family.resetInfoPrimaryFontSize, weight: .bold, design: .rounded))
                .foregroundStyle(labelColor.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(isTextHidden ? "***" : account.weeklyResetDateText())
                .font(.system(size: family.resetInfoSecondaryFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(labelColor.opacity(0.58))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(width: family.resetInfoWidth, alignment: .leading)
    }
}

public struct PagerChevron: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var direction: PagerDirection
    public var family: WidgetFamilyShape
    public var isVisible: Bool

    public init(direction: PagerDirection, family: WidgetFamilyShape, isVisible: Bool) {
        self.direction = direction
        self.family = family
        self.isVisible = isVisible
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var chevronColor: Color {
        isVibrant ? Color(hex: "#24586E") : Color.white
    }

    public var body: some View {
        Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
            .font(.system(size: family.pagerIconSize, weight: .bold, design: .rounded))
            .foregroundStyle(chevronColor.opacity(isVisible ? 0.58 : 0))
            .frame(width: family.pagerButtonSize, height: family.pagerButtonSize)
    }
}
