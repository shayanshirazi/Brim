import SwiftUI

struct AccountEditor: View {
    @Binding var account: QuotaAccount
    @State private var copiedCommand: CopiedCommand?

    private var codexProfilePath: Binding<String> {
        Binding(
            get: { account.resolvedCodexProfilePath },
            set: { account.codexProfilePath = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderPanel(account: account)

                HStack(alignment: .top, spacing: 18) {
                    CodexProfilePanel(
                        account: $account,
                        codexProfilePath: codexProfilePath,
                        copiedCommand: $copiedCommand
                    )
                    .frame(maxWidth: .infinity)

                    UsagePanel(account: $account)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct HeaderPanel: View {
    var account: QuotaAccount

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            QuotaRingView(account: account, diameter: 76, lineWidth: 6, showPercent: false)
                .frame(width: 92, height: 92)
                .background(Color(hex: account.colorHex).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 8) {
                Text(account.name)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text(QuotaFormatting.remainingLine(for: account))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                ProgressView(value: account.weeklyRemainingFraction)
                    .tint(Color(hex: account.colorHex))
                    .frame(maxWidth: 340)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                ConnectionStatusPill(account: account)

                Text(refreshCopy)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 180, alignment: .trailing)
            }
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: account.colorHex).opacity(0.12),
                    Color(nsColor: .controlBackgroundColor).opacity(0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        }
    }

    private var refreshCopy: String {
        if let refreshMessage = account.refreshMessage, !refreshMessage.isEmpty {
            return refreshMessage
        }

        if let lastSuccessfulRefreshAt = account.lastSuccessfulRefreshAt {
            return "Last refreshed \(lastSuccessfulRefreshAt.formatted(date: .omitted, time: .shortened))"
        }

        if let lastRefreshAttemptAt = account.lastRefreshAttemptAt {
            return "Last attempt \(lastRefreshAttemptAt.formatted(date: .omitted, time: .shortened))"
        }

        return "Attempts refresh every 5 min once connected"
    }
}

struct ConnectionStatusPill: View {
    var account: QuotaAccount

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(account.refreshStatus.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private var color: Color {
        switch account.refreshStatus {
        case .ready:
            return Color(hex: "#32D873")
        case .waitingForQuotaSource:
            return Color(hex: "#54C7EC")
        case .refreshFailed:
            return Color(hex: "#E58C30")
        case .manual:
            return Color.secondary
        case .notConnected:
            return Color.secondary
        }
    }
}
