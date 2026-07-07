import SwiftUI
import WidgetKit

public enum QuotaRingSurfaceStyle {
    case standard
    case quiet
}

public struct QuotaRingView: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var lineWidth: CGFloat
    public var showPercent: Bool
    public var surfaceStyle: QuotaRingSurfaceStyle
    public var showsFills: Bool

    /// In the desktop's tinted/vibrant state, layered fills smear into solid discs —
    /// render strokes and the signal dot only.
    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var rendersFills: Bool {
        showsFills && !isVibrant
    }

    // All metrics scale with the diameter (ratios taken from the 32pt sidebar ring),
    // so every ring in the app and widget is an exact scale of the same design.
    private var connectionDotSize: CGFloat {
        max(6, diameter * 0.22)
    }

    private var innerLineWidth: CGFloat {
        max(2, diameter * 0.09)
    }

    private var innerRingInset: CGFloat {
        diameter * 0.2125
    }

    public init(
        account: QuotaAccount?,
        diameter: CGFloat,
        lineWidth: CGFloat? = nil,
        showPercent: Bool = true,
        surfaceStyle: QuotaRingSurfaceStyle = .standard,
        showsFills: Bool = true
    ) {
        self.account = account
        self.diameter = diameter
        self.lineWidth = lineWidth ?? diameter * 0.125
        self.showPercent = showPercent
        self.surfaceStyle = surfaceStyle
        self.showsFills = showsFills
    }

    public var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if rendersFills {
                    Circle()
                        .fill(account.map { Color(hex: $0.colorHex).opacity(surfaceStyle == .quiet ? 0.025 : 0.055) } ?? Color.primary.opacity(0.025))
                }

                Circle()
                    .stroke(.primary.opacity(account == nil ? 0.07 : surfaceStyle == .quiet ? 0.075 : 0.10), lineWidth: lineWidth)

                if let account {
                    // Outer ring = 5h session window (what people watch most),
                    // inner ring = weekly window.
                    Circle()
                        .trim(from: 0, to: account.hasUsageSnapshot && !account.refreshStatus.hidesQuotaDetails ? account.sessionRemainingFraction : 0)
                        .stroke(
                            Color(hex: account.colorHex),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Circle()
                        .stroke(
                            Color(hex: account.colorHex).opacity(surfaceStyle == .quiet ? 0.16 : 0.18),
                            lineWidth: innerLineWidth
                        )
                        .padding(innerRingInset)

                    Circle()
                        .trim(from: 0, to: account.hasUsageSnapshot && !account.refreshStatus.hidesQuotaDetails ? account.weeklyRemainingFraction : 0)
                        .stroke(
                            Color(hex: account.colorHex).opacity(surfaceStyle == .quiet ? 0.62 : 0.58),
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(innerRingInset)

                    if rendersFills {
                        Circle()
                            .fill(Color(hex: account.colorHex).opacity(surfaceStyle == .quiet ? 0.045 : 0.10))
                            .padding(innerRingInset + innerLineWidth * 1.85)
                    }

                    ConnectionSignalDot(
                        state: account.signalState,
                        size: connectionDotSize,
                        borderOpacity: isVibrant ? 0.34 : 0.70,
                        glowRadius: isVibrant ? 0 : max(3, diameter * 0.125),
                        isVibrant: isVibrant
                    )
                }
            }
            .frame(width: diameter, height: diameter)
            .accessibilityLabel("Quota ring")
            .accessibilityValue(accessibilityValue)

            if showPercent {
                Text(account?.remainingPercentText ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(account?.hasUsageSnapshot == true ? 0.62 : 0.34))
                    .frame(height: 15)
            }
        }
        .frame(width: showPercent ? diameter + 8 : diameter)
        .animation(.snappy(duration: 0.22), value: account?.signalState)
    }

    private var accessibilityValue: String {
        guard let account, account.hasUsageSnapshot, !account.refreshStatus.hidesQuotaDetails else {
            return account?.refreshStatus.title ?? "No account"
        }

        return "Session \(account.sessionPercentText), weekly \(account.remainingPercentText)"
    }
}

/// The widget ring is the app ring at widget scale, plus a selection stroke.
public struct NestedQuotaRingView: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var isSelected: Bool

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    public init(account: QuotaAccount?, diameter: CGFloat, isSelected: Bool = false) {
        self.account = account
        self.diameter = diameter
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            QuotaRingView(
                account: account,
                diameter: diameter,
                showPercent: false,
                showsFills: false
            )

            if isSelected {
                Circle()
                    .stroke(
                        Color.primary.opacity(isVibrant ? 0.34 : 0.26),
                        lineWidth: 1.3
                    )
                    .padding(-4.5)
                    .frame(width: diameter, height: diameter)
            }
        }
        .animation(.snappy(duration: 0.22), value: isSelected)
    }
}

private struct ConnectionSignalDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var state: QuotaSignalState
    var size: CGFloat
    var borderOpacity: Double
    var glowRadius: CGFloat
    var isVibrant = false

    private var signalColor: Color {
        switch state {
        case .ready:
            return Color(hex: "#22C55E")
        case .exhausted:
            return Color(hex: "#D9A21B")
        case .waitingForQuotaSource:
            return Color(hex: "#54C7EC")
        case .refreshFailed:
            return Color(hex: "#E58C30")
        case .manual:
            return .secondary
        case .notConnected:
            return Color(hex: "#FF4D57")
        }
    }

    private var dotScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return state == .notConnected ? 0.96 : 1
    }

    var body: some View {
        Circle()
            .fill(signalColor)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(borderOpacity), lineWidth: max(1, size * 0.09))
            }
            .shadow(color: signalColor.opacity(isVibrant ? 0.22 : 0.34), radius: glowRadius)
            .scaleEffect(dotScale)
            .frame(width: size * 1.6, height: size * 1.6)
            .widgetAccentable(false)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: state)
    }
}
