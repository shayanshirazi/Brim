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
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(isVibrant ? 0.10 : 0.12), lineWidth: 1)
            }
    }
}

