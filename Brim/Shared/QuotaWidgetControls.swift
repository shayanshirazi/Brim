import SwiftUI
import WidgetKit

public struct QuotaAccountSlotView: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode
    @State private var isDetailHovered = false

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
        isVibrant ? Color(hex: "#24586E") : Color(hex: "#173B46")
    }

    private var detailOpacity: Double {
        guard account != nil else { return 0 }
        return isDetailHovered ? 1 : 0
    }

    public var body: some View {
        VStack(spacing: family.accountLabelSpacing) {
            NestedQuotaRingView(
                account: account,
                diameter: family.ringDiameter,
                isSelected: isSelected
            )
            .frame(width: family.ringSlotWidth, height: family.ringSlotWidth)

            ZStack(alignment: .top) {
                Text(account == nil ? "" : (isTextHidden ? "***" : (account?.sessionPercentText ?? "")))
                    .font(.system(size: family.sessionLabelFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(height: family.sessionLabelHeight)

                Text(hoverDetailText)
                    .font(.system(size: family.weeklyLabelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor.opacity(account == nil ? 0 : 0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(labelColor.opacity(isVibrant ? 0.08 : 0.10), in: Capsule())
                    .offset(y: family.sessionLabelHeight + 2)
                    .opacity(detailOpacity)
            }
            .frame(width: family.accountSlotWidth)
            .contentShape(Rectangle())
            .onHover { isDetailHovered = $0 }
        }
        .frame(width: family.accountSlotWidth)
    }

    private var hoverDetailText: String {
        guard let account else {
            return ""
        }

        return isTextHidden ? "***" : QuotaFormatting.windowLine(for: account)
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
        isVibrant ? Color(hex: "#24586E") : Color(hex: "#173B46")
    }

    public var body: some View {
        EmptyView()
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
        isVibrant ? Color(hex: "#24586E") : Color(hex: "#173B46")
    }

    public var body: some View {
        Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
            .font(.system(size: family.pagerIconSize, weight: .bold, design: .rounded))
            .foregroundStyle(chevronColor.opacity(isVisible ? 0.58 : 0))
            .frame(width: family.pagerButtonSize, height: family.pagerButtonSize)
    }
}
