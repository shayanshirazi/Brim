import AppKit
import SwiftUI

struct AccountEditor: View {
    @Binding var account: QuotaAccount
    var openPersonalizationSettings: () -> Void = {}

    private let detailPanelMinHeight: CGFloat = 372

    private var profilePath: Binding<String> {
        Binding(
            get: { account.resolvedProviderProfilePath },
            set: { account.providerProfilePath = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HeaderPanel(account: $account)

            GeometryReader { geometry in
                let detailHeight = max(detailPanelMinHeight, geometry.size.height)

                HStack(alignment: .top, spacing: 18) {
                    DetailPanelSurface(height: detailHeight) {
                        ProviderProfilePanel(
                            account: $account,
                            profilePath: profilePath,
                            openPersonalizationSettings: openPersonalizationSettings
                        )
                    }
                    .frame(maxWidth: .infinity)

                    DetailPanelSurface(height: detailHeight) {
                        UsagePanel(account: $account)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: geometry.size.width, height: detailHeight, alignment: .top)
            }
            .frame(minHeight: detailPanelMinHeight, maxHeight: .infinity, alignment: .top)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DetailPanelSurface<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(18)
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
    }
}

private struct HeaderPanel: View {
    @Binding var account: QuotaAccount
    @State private var isEditingName = false
    @State private var draftName = ""
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            QuotaRingView(
                account: account,
                diameter: 82,
                lineWidth: 6,
                showPercent: false,
                surfaceStyle: .quiet
            )
            .frame(width: 98, height: 98)
            .help(ringHelpText)
            .background {
                ZStack {
                    Circle()
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.50))

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: account.colorHex).opacity(0.075),
                                    Color(hex: account.colorHex).opacity(0.025),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 66
                            )
                        )

                    Circle()
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)

                    Circle()
                        .stroke(Color.primary.opacity(0.045), lineWidth: 1)
                        .padding(1)
                }
            }
            .shadow(color: Color(hex: account.colorHex).opacity(0.075), radius: 20, y: 8)
            .shadow(color: Color.primary.opacity(0.035), radius: 12, y: 4)

            VStack(alignment: .leading, spacing: 9) {
                nameEditor

                if let accountEmail = account.normalizedAccountEmail {
                    Text(accountEmail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 320, alignment: .leading)
                }

                AccountIdentifierRow(account: account)
            }
            .frame(maxHeight: .infinity, alignment: .center)

            Spacer()

            ConnectionStatusPill(account: account)
        }
        .frame(minHeight: 104, alignment: .center)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background {
            headerBackground
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.36),
                            Color.white.opacity(0.16),
                            Color.primary.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.primary.opacity(0.035), radius: 18, y: 8)
    }

    private var ringHelpText: String {
        let sessionWindow = QuotaFormatting.windowDuration(account.sessionWindowMinutes)
        return "Outer ring: weekly limit. Inner ring: \(sessionWindow) session."
    }

    private var headerBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.56))

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.10),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: account.colorHex).opacity(0.038),
                            Color.clear,
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: account.colorHex).opacity(0.07),
                            Color(hex: account.colorHex).opacity(0.018),
                            Color.clear
                        ],
                        center: .leading,
                        startRadius: 0,
                        endRadius: 340
                    )
                )

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.10)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
        }
    }

    private var nameEditor: some View {
        HStack(alignment: .center, spacing: 7) {
            if isEditingName {
                TextField("Account name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .focused($isNameFieldFocused)
                    .onSubmit(commitName)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: 320, alignment: .leading)
                    .background(
                        Color(nsColor: .textBackgroundColor).opacity(0.82),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            } else {
                Text(account.headerDisplayName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Button(action: isEditingName ? commitName : beginEditingName) {
                Image(systemName: isEditingName ? "checkmark" : "pencil.tip")
                    .font(.system(size: isEditingName ? 11 : 13, weight: .bold))
                    .foregroundStyle(isEditingName ? Color(hex: account.colorHex) : .primary.opacity(0.56))
                    .frame(width: 26, height: 26)
                    .background(
                        Color(nsColor: .textBackgroundColor).opacity(0.72),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help(isEditingName ? "Save account name" : "Edit account name")
            .offset(y: -1)
        }
    }

    private func beginEditingName() {
        draftName = account.name
        isEditingName = true

        DispatchQueue.main.async {
            isNameFieldFocused = true
        }
    }

    private func commitName() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            account.name = trimmedName
        }

        isEditingName = false
        isNameFieldFocused = false
    }

}

private struct AccountIdentifierRow: View {
    var account: QuotaAccount
    @State private var didCopy = false
    private var canCopyIdentifier: Bool {
        !account.copyableAccountIdentifier.isEmpty
    }

    var body: some View {
        HStack(spacing: 7) {
            Text("Session ID \(account.shortAccountIdentifier)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(action: copyIdentifier) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(copyIconColor)
                    .frame(width: 22, height: 22)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.68), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canCopyIdentifier)
            .help("Copy session ID")
        }
        .frame(maxWidth: 280, alignment: .leading)
    }

    private var copyIconColor: Color {
        if didCopy {
            return Color(hex: account.colorHex)
        }

        return canCopyIdentifier ? Color.secondary : Color.secondary.opacity(0.42)
    }

    private func copyIdentifier() {
        guard canCopyIdentifier else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(account.copyableAccountIdentifier, forType: .string)
        didCopy = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            didCopy = false
        }
    }
}

struct ConnectionStatusPill: View {
    var account: QuotaAccount

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.68), lineWidth: 1)
                }
                .shadow(color: color.opacity(0.24), radius: 4, y: 1)

            Text(account.signalState.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule()
                .fill(color.opacity(0.11))
                .overlay {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.26),
                                    Color.white.opacity(0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
        )
        .overlay {
            Capsule()
                .stroke(color.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: color.opacity(0.08), radius: 10, y: 4)
        .foregroundStyle(color)
    }

    private var color: Color {
        switch account.signalState {
        case .ready:
            return Color(hex: "#32D873")
        case .exhausted:
            return Color(hex: "#B7791F")
        case .waitingForQuotaSource:
            return Color(hex: "#54C7EC")
        case .refreshFailed:
            return Color(hex: "#E58C30")
        case .manual:
            return Color.secondary
        case .notConnected:
            return Color(hex: "#FF4D57")
        }
    }
}
