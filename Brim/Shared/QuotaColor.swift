import Foundation
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

    public static func randomCustomHex(excluding excludedHexes: Set<String> = []) -> String {
        for _ in 0..<64 {
            let color = customHex(
                hue: Double.random(in: 0..<1),
                saturation: Double.random(in: 0.56...0.86),
                brightness: Double.random(in: 0.78...0.96)
            )

            if !excludedHexes.contains(color) {
                return color
            }
        }

        return fallbackCustomHex(excluding: excludedHexes)
    }

    private static func fallbackCustomHex(excluding excludedHexes: Set<String>) -> String {
        for hueStep in 0..<360 {
            let color = customHex(
                hue: Double(hueStep) / 360,
                saturation: 0.72,
                brightness: 0.90
            )

            if !excludedHexes.contains(color) {
                return color
            }
        }

        return fallbackHex
    }

    private static func customHex(hue: Double, saturation: Double, brightness: Double) -> String {
        let normalizedHue = hue - floor(hue)
        let sector = normalizedHue * 6
        let chroma = brightness * saturation
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let match = brightness - chroma

        let components: (Double, Double, Double)
        switch sector {
        case 0..<1:
            components = (chroma, secondary, 0)
        case 1..<2:
            components = (secondary, chroma, 0)
        case 2..<3:
            components = (0, chroma, secondary)
        case 3..<4:
            components = (0, secondary, chroma)
        case 4..<5:
            components = (secondary, 0, chroma)
        default:
            components = (chroma, 0, secondary)
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round((components.0 + match) * 255)),
            Int(round((components.1 + match) * 255)),
            Int(round((components.2 + match) * 255))
        )
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
