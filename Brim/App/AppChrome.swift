import SwiftUI

struct BrimLogoMark: View {
    var size: CGFloat = 28
    var glow: Bool = true

    var body: some View {
        Image("BrimLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: glow ? Color(hex: "#43E27C").opacity(0.24) : .clear, radius: 10, y: 3)
            .accessibilityLabel("Brim")
    }
}

struct PanelTitle: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
    }
}

struct EmptyAccountsView: View {
    var addAccount: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            BrimLogoMark(size: 96)

            Button(action: addAccount) {
                Label("Add account", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum CopiedCommand {
    case login
    case status
}

extension View {
    func panelStyle() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
    }
}
