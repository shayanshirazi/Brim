import SwiftUI

#if os(macOS)
import AppKit
#endif

public enum QuotaColor {
    public static let fallbackHex = "#40E06B"

    public static func normalizedHex(_ hex: String) -> String? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, UInt64(cleaned, radix: 16) != nil else {
            return nil
        }
        return "#\(cleaned.uppercased())"
    }
}

public extension Color {
    init(hex: String) {
        let normalized = QuotaColor.normalizedHex(hex) ?? QuotaColor.fallbackHex
        let cleaned = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(cleaned, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    var quotaHexString: String {
        #if os(macOS)
        let nativeColor = NSColor(self)
        guard let color = nativeColor.usingColorSpace(.sRGB) else {
            return QuotaColor.fallbackHex
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
        #else
        return QuotaColor.fallbackHex
        #endif
    }
}
