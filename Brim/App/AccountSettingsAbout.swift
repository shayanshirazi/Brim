import SwiftUI

struct AboutSettingsTab: View {
    var openGitHub: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 32) {
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
                .frame(maxWidth: 300, alignment: .leading)
            }
            .frame(maxWidth: 560, alignment: .center)

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
                        width: 142 + CGFloat(index * 38),
                        height: 142 + CGFloat(index * 38)
                    )
            }

            BrimLogoMark(size: 104)
                .shadow(color: Color(hex: "#2CCB68").opacity(0.22), radius: 28, y: 12)

            Circle()
                .fill(Color(hex: "#2CCB68").opacity(0.80))
                .frame(width: 8, height: 8)
                .offset(x: 76, y: -54)
                .shadow(color: Color(hex: "#2CCB68").opacity(0.24), radius: 9, y: 2)

            Circle()
                .fill(Color(hex: "#54C7EC").opacity(0.76))
                .frame(width: 6, height: 6)
                .offset(x: -82, y: 42)
                .shadow(color: Color(hex: "#54C7EC").opacity(0.20), radius: 8, y: 2)
        }
        .frame(width: 218, height: 218)
    }
}

private struct AboutTrustConstellation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                AboutTrustChip(icon: "lock.fill", title: "Local only")
                AboutTrustChip(icon: "chart.bar.xaxis", title: "No analytics")
                AboutTrustChip(icon: "shippingbox", title: "No secrets")
            }

            Text("Credentials stay local. Exports omit secrets and live account data.")
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
