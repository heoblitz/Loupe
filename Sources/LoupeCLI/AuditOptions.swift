import Foundation
import LoupeCLIModel
import LoupeCore

struct AuditOptions {
    var snapshotURL: URL
    var tolerance: Double
    var minOverlapArea: Double
    var minTouchTarget: Double
    var minContrastRatio: Double
    var kinds: Set<LoupeLayoutIssueKind>
    var excludedKinds: Set<LoupeLayoutIssueKind>

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError(Self.usage)
        }

        snapshotURL = URL(fileURLWithPath: path)
        tolerance = 1
        minOverlapArea = 16
        minTouchTarget = 44
        minContrastRatio = 4.5
        kinds = []
        excludedKinds = []

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--tolerance":
                tolerance = try Self.double(after: "--tolerance", in: arguments, index: &index)
            case "--min-overlap-area":
                minOverlapArea = try Self.double(after: "--min-overlap-area", in: arguments, index: &index)
            case "--min-touch-target":
                minTouchTarget = try Self.double(after: "--min-touch-target", in: arguments, index: &index)
            case "--min-contrast-ratio":
                minContrastRatio = try Self.double(after: "--min-contrast-ratio", in: arguments, index: &index)
            case "--kind":
                kinds.formUnion(try Self.kinds(after: "--kind", in: arguments, index: &index))
            case "--exclude-kind":
                excludedKinds.formUnion(try Self.kinds(after: "--exclude-kind", in: arguments, index: &index))
            default:
                throw CLIError("Unknown audit option: \(arguments[index])")
            }
            index += 1
        }
    }

    static var usage: String {
        "Usage: loupe ui audit <snapshot.json> [--tolerance <points>] [--min-overlap-area <points2>] [--min-touch-target <points>] [--min-contrast-ratio <ratio>] [--kind <kind[,kind]>] [--exclude-kind <kind[,kind]>]"
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }

    private static func kinds(after option: String, in arguments: [String], index: inout Int) throws -> Set<LoupeLayoutIssueKind> {
        let raw = try value(after: option, in: arguments, index: &index)
        var parsed = Set<LoupeLayoutIssueKind>()
        for item in raw.split(separator: ",") {
            let value = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let kind = LoupeLayoutIssueKind(rawValue: value) else {
                let allowed = LoupeLayoutIssueKind.allCases.map(\.rawValue).joined(separator: ", ")
                throw CLIError("\(option) expects one of: \(allowed)")
            }
            parsed.insert(kind)
        }
        return parsed
    }
}
