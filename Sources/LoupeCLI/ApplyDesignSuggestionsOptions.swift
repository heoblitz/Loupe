import Foundation
import LoupeCLIModel
import LoupeCore

struct ApplyDesignSuggestionsOptions {
    static let usage = """
    Usage: loupe ui apply-design-suggestions <compare-design.json> [--host <url>] [--snapshot <snapshot.json>] [--output-dir <dir>] [--max <n>] [--properties <list>] [--dry-run]
           loupe ui compare-design report/snapshot.json design.json --json --suggest-mutations > compare.json
           loupe ui apply-design-suggestions compare.json --host http://127.0.0.1:8765 --snapshot report/snapshot.json --output-dir /tmp/loupe-design-probes
           loupe ui apply-design-suggestions compare.json --snapshot report/snapshot.json --dry-run --output-dir /tmp/loupe-design-probes

    Applies a bounded set of compare-design mutation suggestions and writes
    before/after snapshots, mutation responses, diff, and summary artifacts.
    By default, selects at most three suggestions and prioritizes copy/style
    changes before probing at most one frame mutation.
    Dry-run mode does not require a live host and writes only the selected
    suggestions plus summary artifacts.
    """

    var compareURL: URL
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var timeout: TimeInterval
    var snapshotURL: URL?
    var outputDirectory: URL
    var maxSuggestions: Int
    var allowedProperties: Set<String>
    var propertyFilterWasExplicit: Bool
    var dryRun: Bool

    init(_ arguments: [String]) throws {
        guard let first = arguments.first, !first.hasPrefix("--") else {
            throw CLIError(Self.usage)
        }

        compareURL = URL(fileURLWithPath: first)
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        timeout = 5
        snapshotURL = nil
        outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-apply-design-suggestions-\(Self.timestamp())", isDirectory: true)
        maxSuggestions = 3
        allowedProperties = Set(Self.defaultProperties)
        propertyFilterWasExplicit = false
        dryRun = false

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--host":
                host = try Self.url(after: "--host", in: arguments, index: &index)
                hostWasExplicit = true
            case "--udid", "--device":
                udid = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--bundle-id":
                bundleID = try Self.value(after: "--bundle-id", in: arguments, index: &index)
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--snapshot":
                snapshotURL = URL(fileURLWithPath: try Self.value(after: "--snapshot", in: arguments, index: &index))
            case "--output-dir":
                outputDirectory = URL(fileURLWithPath: try Self.value(after: "--output-dir", in: arguments, index: &index), isDirectory: true)
            case "--max", "--limit":
                maxSuggestions = try Self.positiveInt(after: arguments[index], in: arguments, index: &index)
            case "--properties":
                allowedProperties = try Self.propertySet(try Self.value(after: "--properties", in: arguments, index: &index))
                propertyFilterWasExplicit = true
            case "--dry-run":
                dryRun = true
            case "--help", "-h":
                throw CLIError(Self.usage)
            default:
                throw CLIError("Unknown apply-design-suggestions option: \(arguments[index])")
            }
            index += 1
        }

        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        guard maxSuggestions > 0 else {
            throw CLIError("--max must be greater than 0")
        }
        guard !allowedProperties.isEmpty else {
            throw CLIError("--properties must include at least one property")
        }
    }

    func selectedSuggestions<T: Sequence>(
        from suggestions: T
    ) -> [T.Element] where T.Element == LoupeDesignMutationSuggestion {
        let filtered = suggestions.enumerated().filter { allowedProperties.contains($0.element.property) }
        guard !propertyFilterWasExplicit else {
            return Array(filtered.prefix(maxSuggestions).map(\.element))
        }

        let ranked = filtered.sorted { lhs, rhs in
            let lhsPriority = Self.defaultSelectionPriority(for: lhs.element.property)
            let rhsPriority = Self.defaultSelectionPriority(for: rhs.element.property)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return lhs.offset < rhs.offset
        }

        let nonFrameSuggestions = ranked.filter { $0.element.property != "frame" }
        let frameSuggestions = ranked.filter { $0.element.property == "frame" }
        let ordered = nonFrameSuggestions.isEmpty
            ? ranked
            : nonFrameSuggestions + Array(frameSuggestions.prefix(Self.defaultFrameProbeLimit))
        return Array(ordered.prefix(maxSuggestions).map(\.element))
    }

    static let defaultProperties = [
        "text",
        "textColor",
        "backgroundColor",
        "cornerRadius",
        "fontSize",
        "frame",
    ]

    private static func defaultSelectionPriority(for property: String) -> Int {
        switch property {
        case "text":
            return 0
        case "textColor":
            return 10
        case "backgroundColor":
            return 20
        case "cornerRadius":
            return 30
        case "fontSize":
            return 40
        case "frame":
            return 90
        default:
            return 50
        }
    }

    private static let defaultFrameProbeLimit = 1

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func url(after option: String, in arguments: [String], index: inout Int) throws -> URL {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let url = URL(string: raw), url.scheme != nil, url.host != nil else {
            throw CLIError("\(option) expects a URL")
        }
        return url
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw), value.isFinite else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }

    private static func positiveInt(after option: String, in arguments: [String], index: inout Int) throws -> Int {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Int(raw), value > 0 else {
            throw CLIError("\(option) expects a positive integer")
        }
        return value
    }

    private static func propertySet(_ rawValue: String) throws -> Set<String> {
        let properties = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !properties.isEmpty else {
            throw CLIError("--properties expects one or more comma-separated properties")
        }
        return Set(properties)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
