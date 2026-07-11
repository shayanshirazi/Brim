import SwiftUI

struct AppVersion: Equatable {
    var marketingVersion: String
    var buildNumber: String

    static let current = AppVersion(bundle: .main)

    init(
        marketingVersion: String,
        buildNumber: String
    ) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    init(bundle: Bundle) {
        marketingVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var badgeText: String {
        "v\(marketingVersion)"
    }
}

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

struct BrimVersionBadge: View {
    var version: AppVersion = .current

    var body: some View {
        Text(version.badgeText)
            .font(.system(size: 9, weight: .black, design: .rounded))
            .foregroundStyle(Color(hex: "#2CCB68").opacity(0.82))
            .padding(.horizontal, 5)
            .frame(height: 16)
            .background(Color(hex: "#2CCB68").opacity(0.10), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(hex: "#2CCB68").opacity(0.18), lineWidth: 1)
            }
            .accessibilityLabel("Version \(version.marketingVersion)")
    }
}

struct PanelTitle: View {
    var icon: String
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.primary.opacity(0.68))
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.045), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                }
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
        }
    }
}

struct SettingsGearMark: View {
    var size: CGFloat = 32
    var isSelected: Bool = true

    var body: some View {
        Image(systemName: "gearshape")
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(isSelected ? Color(hex: "#2CCB68") : .secondary)
            .frame(width: size, height: size)
            .background(
                isSelected ? Color(hex: "#2CCB68").opacity(0.13) : Color.primary.opacity(0.045),
                in: Circle()
            )
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

extension View {
    func panelStyle(insets: CGFloat = 18) -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(insets)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
    }
}

/// Small monochrome provider logo shown next to account names.
struct ProviderLogoMark: View {
    var provider: QuotaProviderKind
    var size: CGFloat

    var body: some View {
        if let assetName = provider.logoAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .help(provider.displayName)
                .accessibilityLabel(provider.displayName)
        }
    }
}
