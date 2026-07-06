import SwiftUI

struct PrivacySettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsPanelHeader(
                icon: "lock.shield",
                title: "Privacy policy",
                subtitle: "Brim is designed to keep account details on your Mac."
            )

            VStack(spacing: 10) {
                PrivacyLine(icon: "key.horizontal", title: "Tokens stay in Keychain", detail: "API tokens are saved by macOS Keychain and are not written into widget snapshots or exports.")
                PrivacyLine(icon: "square.stack.3d.up", title: "Widgets receive snapshots", detail: "The widget only gets account names, colors, quota numbers, and display state.")
                PrivacyLine(icon: "arrow.up.doc", title: "Exports skip secrets", detail: "JSON exports move account names, colors, and modes. Emails, profile paths, tokens, and live usage are left on this Mac.")
                PrivacyLine(icon: "chart.bar.xaxis", title: "No analytics", detail: "Brim does not include tracking, analytics, or remote reporting in this app.")
            }

            Spacer(minLength: 0)
        }
        .panelStyle()
    }
}

private struct PrivacyLine: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))
                .frame(width: 30, height: 30)
                .background(Color(hex: "#2CCB68").opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct AboutSettingsTab: View {
    var openGitHub: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 26) {
                AboutLogoOrbit()

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("Brim")
                                .font(.system(size: 46, weight: .black, design: .rounded))
                                .lineLimit(1)

                            BrimVersionBadge()
                                .padding(.top, 8)
                        }

                        Text("A tiny quota instrument for people who like calm tools.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    GitHubStarButton(action: openGitHub)

                    AboutTrustConstellation()
                }
                .frame(width: 330, alignment: .leading)
            }
            .frame(maxWidth: 620, alignment: .center)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panelStyle()
    }
}

private struct AboutLogoOrbit: View {
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Color(hex: index == 1 ? "#54C7EC" : "#2CCB68")
                            .opacity(0.090 - Double(index) * 0.018),
                        lineWidth: 1
                    )
                    .frame(
                        width: 164 + CGFloat(index * 44),
                        height: 164 + CGFloat(index * 44)
                    )
            }

            BrimLogoMark(size: 116)
                .shadow(color: Color(hex: "#2CCB68").opacity(0.22), radius: 32, y: 14)

            Circle()
                .fill(Color(hex: "#2CCB68").opacity(0.80))
                .frame(width: 8, height: 8)
                .offset(x: 88, y: -62)
                .shadow(color: Color(hex: "#2CCB68").opacity(0.24), radius: 9, y: 2)

            Circle()
                .fill(Color(hex: "#54C7EC").opacity(0.76))
                .frame(width: 6, height: 6)
                .offset(x: -96, y: 48)
                .shadow(color: Color(hex: "#54C7EC").opacity(0.20), radius: 8, y: 2)
        }
        .frame(width: 246, height: 246)
    }
}

private struct AboutTrustConstellation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                AboutTrustChip(icon: "lock.fill", title: "Keychain")
                AboutTrustChip(icon: "macwindow", title: "Snapshots")
                AboutTrustChip(icon: "shippingbox", title: "No secrets")
            }

            Text("Tokens stay in Keychain. Widgets and exports receive snapshots only.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 3)
    }
}

private struct AboutTrustChip: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "#2CCB68"))

            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.62))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color.white.opacity(0.40), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(hex: "#2CCB68").opacity(0.13), lineWidth: 1)
        }
        .shadow(color: Color(hex: "#2CCB68").opacity(0.055), radius: 10, y: 4)
    }
}

private struct GitHubStarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: "#24292F"))

                    Text("Star")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#24292F"))
                }
                .padding(.horizontal, 12)
                .frame(height: 34)

                Rectangle()
                    .fill(Color(hex: "#D0D7DE"))
                    .frame(width: 1, height: 34)

                Text("shayanshirazi/Brim")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "#57606A"))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
            }
            .background(Color(hex: "#F6F8FA"), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(hex: "#D0D7DE"), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("Open Brim on GitHub")
    }
}
