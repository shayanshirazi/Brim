import SwiftUI
import WidgetKit

public enum QuotaWidgetSurfaceStyle {
    case none
    case editorPreview
}

public struct BrimBackground: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                isVibrant
                    ? Color(hex: "#2F94C7").opacity(0.16)
                    : Color(hex: "#2084B5").opacity(0.20)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isVibrant
                            ? Color(hex: "#1B6F95").opacity(0.22)
                            : Color.white.opacity(0.22),
                        lineWidth: 1
                    )
            }
    }
}

public struct DesktopWidgetSurface: View {
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    private var isVibrant: Bool {
        widgetRenderingMode == .vibrant
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isVibrant ? 0.08 : 0.20),
                                Color.white.opacity(isVibrant ? 0.03 : 0.08),
                                Color(hex: "#65D8E8").opacity(isVibrant ? 0.03 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isVibrant ? 0.16 : 0.22),
                                Color.clear,
                                Color(hex: "#BFF6EE").opacity(isVibrant ? 0.04 : 0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        isVibrant ? Color.white.opacity(0.24) : Color.white.opacity(0.52),
                        lineWidth: 1
                    )
            }
    }
}
