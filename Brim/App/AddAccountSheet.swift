import SwiftUI

struct AddAccountCreationMode: Identifiable, Hashable {
    var provider: QuotaProviderKind
    var connectionKind: QuotaConnectionKind
    var title: String
    var subtitle: String
    var detail: String
    var fallbackSystemImage: String

    var id: String {
        "\(provider.rawValue)-\(connectionKind.title)"
    }

    var logoAssetName: String? {
        provider.logoAssetName
    }

    var accentHex: String {
        provider.brandColorHex
    }

    static var available: [AddAccountCreationMode] {
        QuotaProviderKind.allCases.flatMap { $0.accountCreationModes }
    }
}

private extension QuotaProviderKind {
    var accountCreationModes: [AddAccountCreationMode] {
        switch self {
        case .codex:
            return [
                AddAccountCreationMode(
                    provider: self,
                    connectionKind: .login,
                    title: "Codex",
                    subtitle: "Use Codex login",
                    detail: "Track the Codex session already signed in on this Mac.",
                    fallbackSystemImage: "terminal.fill"
                )
            ]
        case .chatgpt:
            return [
                AddAccountCreationMode(
                    provider: self,
                    connectionKind: .login,
                    title: "ChatGPT",
                    subtitle: "Use ChatGPT login",
                    detail: "Track your ChatGPT plan's rate-limit windows.",
                    fallbackSystemImage: "bubble.left.and.bubble.right.fill"
                )
            ]
        case .claude:
            return [
                AddAccountCreationMode(
                    provider: self,
                    connectionKind: .apiToken,
                    title: "Claude",
                    subtitle: "Use an Anthropic API key",
                    detail: "Track Anthropic API rate limits with an sk-ant-… key.",
                    fallbackSystemImage: "sparkle"
                )
            ]
        case .gemini:
            return [
                AddAccountCreationMode(
                    provider: self,
                    connectionKind: .apiToken,
                    title: "Gemini",
                    subtitle: "Use a Google AI API key",
                    detail: "Track a Google AI key (AIza…). Google exposes no live usage yet.",
                    fallbackSystemImage: "diamond.fill"
                )
            ]
        }
    }
}

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    var createAccount: (AddAccountCreationMode) -> Void

    private let modes = AddAccountCreationMode.available

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    AddAccountMark()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Add account")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Choose what Brim should track first. More modes can join this list later.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close")
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(modes) { mode in
                    AddAccountOptionButton(
                        mode: mode,
                        action: { createAccount(mode) }
                    )
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AddAccountMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "#2CCB68").opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "#2CCB68").opacity(0.18), lineWidth: 1)
                }

            Circle()
                .fill(Color(hex: "#2CCB68"))
                .frame(width: 26, height: 26)
                .shadow(color: Color(hex: "#2CCB68").opacity(0.22), radius: 8, y: 3)

            Image(systemName: "plus")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .offset(y: -0.5)
        }
        .frame(width: 46, height: 46)
        .accessibilityLabel("Add account")
    }
}

private struct AddAccountOptionButton: View {
    var mode: AddAccountCreationMode
    var action: () -> Void

    private var accent: Color {
        Color(hex: mode.accentHex)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ProviderModeMark(mode: mode)

                VStack(spacing: 3) {
                    Text(mode.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))

                    Text(mode.subtitle)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .background(
                LinearGradient(
                    colors: [accent.opacity(0.10), Color.primary.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accent.opacity(0.20), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(mode.subtitle)
    }
}

private struct ProviderModeMark: View {
    var mode: AddAccountCreationMode

    private var accent: Color {
        Color(hex: mode.accentHex)
    }

    var body: some View {
        ZStack {
            if let logoAssetName = mode.logoAssetName {
                Image(logoAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .shadow(color: accent.opacity(0.22), radius: 12, y: 5)
            } else {
                Image(systemName: mode.fallbackSystemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.14), in: Circle())
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}
