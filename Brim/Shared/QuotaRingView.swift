import SwiftUI
import WidgetKit

public enum QuotaRingSurfaceStyle {
    case standard
    case quiet
}

public struct QuotaRingView: View {
    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var lineWidth: CGFloat
    public var showPercent: Bool
    public var surfaceStyle: QuotaRingSurfaceStyle

    private var connectionDotSize: CGFloat {
        max(8, diameter * 0.18)
    }

    private var innerLineWidth: CGFloat {
        max(2, min(lineWidth * 0.92, diameter * 0.09))
    }

    private var innerRingInset: CGFloat {
        max(lineWidth * 2.3, diameter * 0.17)
    }

    public init(
        account: QuotaAccount?,
        diameter: CGFloat,
        lineWidth: CGFloat = 5,
        showPercent: Bool = true,
        surfaceStyle: QuotaRingSurfaceStyle = .standard
    ) {
        self.account = account
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.showPercent = showPercent
        self.surfaceStyle = surfaceStyle
    }

    public var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(account.map { Color(hex: $0.colorHex).opacity(surfaceStyle == .quiet ? 0.025 : 0.055) } ?? Color.primary.opacity(0.025))

                Circle()
                    .stroke(.primary.opacity(account == nil ? 0.07 : surfaceStyle == .quiet ? 0.075 : 0.10), lineWidth: lineWidth)

                if let account {
                    Circle()
                        .trim(from: 0, to: account.hasUsageSnapshot && !account.refreshStatus.hidesQuotaDetails ? account.weeklyRemainingFraction : 0)
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
                        .trim(from: 0, to: account.hasUsageSnapshot && !account.refreshStatus.hidesQuotaDetails ? account.sessionRemainingFraction : 0)
                        .stroke(
                            Color(hex: account.colorHex).opacity(surfaceStyle == .quiet ? 0.62 : 0.58),
                            style: StrokeStyle(lineWidth: innerLineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(innerRingInset)

                    Circle()
                        .fill(Color(hex: account.colorHex).opacity(surfaceStyle == .quiet ? 0.045 : 0.10))
                        .padding(innerRingInset + innerLineWidth * 1.85)

                    ConnectionSignalDot(
                        state: account.signalState,
                        size: connectionDotSize,
                        borderOpacity: 0.70,
                        glowRadius: max(4, diameter * 0.07)
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
        .frame(width: diameter + 8)
        .animation(.snappy(duration: 0.22), value: account?.signalState)
    }

    private var accessibilityValue: String {
        guard let account, account.hasUsageSnapshot, !account.refreshStatus.hidesQuotaDetails else {
            return account?.refreshStatus.title ?? "No account"
        }

        return "Weekly \(account.remainingPercentText), session \(account.sessionPercentText)"
    }
}

public struct NestedQuotaRingView: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var account: QuotaAccount?
    public var diameter: CGFloat
    public var isSelected: Bool

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    private var connectionDotSize: CGFloat {
        max(8, diameter * 0.18)
    }

    public init(account: QuotaAccount?, diameter: CGFloat, isSelected: Bool = false) {
        self.account = account
        self.diameter = diameter
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(
                    isVibrant
                        ? Color(hex: "#1B6F95").opacity(account == nil ? 0.16 : 0.22)
                        : Color.white.opacity(account == nil ? 0.13 : 0.22),
                    lineWidth: 4
                )

            if let account {
                Circle()
                    .trim(from: 0, to: account.hasUsageSnapshot && !account.refreshStatus.hidesQuotaDetails ? account.weeklyRemainingFraction : 0)
                    .stroke(
                        Color(hex: account.colorHex),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.16)
                            : Color.white.opacity(0.16),
                        lineWidth: 7
                    )
                    .padding(13)

                Circle()
                    .trim(from: 0, to: account.hasUsageSnapshot && !account.refreshStatus.hidesQuotaDetails ? account.sessionRemainingFraction : 0)
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.70)
                            : Color.white.opacity(0.82),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(13)

                ConnectionSignalDot(
                    state: account.signalState,
                    size: connectionDotSize,
                    borderOpacity: isVibrant ? 0.34 : 0.72,
                    glowRadius: 4,
                    isVibrant: isVibrant
                )
            }

            if isSelected {
                Circle()
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.44)
                            : Color.white.opacity(0.58),
                        lineWidth: 1.3
                    )
                    .padding(-4)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.snappy(duration: 0.22), value: isSelected)
        .animation(.snappy(duration: 0.22), value: account?.signalState)
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
