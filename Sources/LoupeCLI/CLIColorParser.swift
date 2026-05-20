import Foundation
import LoupeCLIModel
import LoupeCore

enum CLIColorParser {
    static func color(_ rawValue: String) throws -> LoupeColor {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hexColor = try hexColor(trimmed) {
            return hexColor
        }

        let values = try doubles(rawValue, expected: [3, 4], label: "color")
        let divisor: Double = values.prefix(3).contains { $0 > 1 } ? 255 : 1
        return LoupeColor(
            red: values[0] / divisor,
            green: values[1] / divisor,
            blue: values[2] / divisor,
            alpha: values.count == 4 ? values[3] : 1
        )
    }

    private static func hexColor(_ rawValue: String) throws -> LoupeColor? {
        let pieces = rawValue.split(separator: "_", maxSplits: 1).map(String.init)
        guard pieces.count <= 2 else {
            throw CLIError("Expected color as #RGB, #RRGGBB, RRGGBB_A, or r,g,b[,a]")
        }

        let hex = pieces[0].hasPrefix("#") ? String(pieces[0].dropFirst()) : pieces[0]
        guard isHexLike(hex) else {
            return nil
        }

        let expanded: String
        if hex.count == 3 {
            expanded = hex.map { "\($0)\($0)" }.joined()
        } else {
            expanded = hex
        }
        guard expanded.count == 6 || expanded.count == 8, let raw = UInt64(expanded, radix: 16) else {
            throw CLIError("Expected color as #RGB, #RRGGBB, #RRGGBBAA, RRGGBB_A, or r,g,b[,a]")
        }
        let hasAlpha = expanded.count == 8
        let red = Double((raw >> (hasAlpha ? 24 : 16)) & 0xff) / 255
        let green = Double((raw >> (hasAlpha ? 16 : 8)) & 0xff) / 255
        let blue = Double((raw >> (hasAlpha ? 8 : 0)) & 0xff) / 255
        let encodedAlpha = hasAlpha ? Double(raw & 0xff) / 255 : 1
        let alpha = pieces.count == 2 ? try alphaValue(pieces[1]) : encodedAlpha
        return LoupeColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private static func isHexLike(_ rawValue: String) -> Bool {
        [3, 6, 8].contains(rawValue.count)
            && rawValue.allSatisfy { $0.isHexDigit }
    }

    private static func alphaValue(_ rawValue: String) throws -> Double {
        guard let value = Double(rawValue), value.isFinite, value >= 0, value <= 1 else {
            throw CLIError("Expected hex color alpha between 0 and 1: \(rawValue)")
        }
        return value
    }

    private static func doubles(_ rawValue: String, expected counts: Set<Int>, label: String) throws -> [Double] {
        let parts = rawValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard counts.contains(parts.count) else {
            throw CLIError("Expected \(label) with \(counts.sorted().map(String.init).joined(separator: " or ")) comma-separated numbers")
        }
        return try parts.map { part in
            guard let value = Double(part), value.isFinite else {
                throw CLIError("Expected numeric \(label) component: \(part)")
            }
            return value
        }
    }
}
