import Foundation
import LoupeCLIModel
import LoupeCore

struct BatchMutationOptions {
    enum TargetSelector: Equatable {
        case refs([String])
        case typeName(String)
        case role(String)
    }

    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var timeout: TimeInterval
    var outputURL: URL?
    var traceDirectory: URL
    var selector: TargetSelector?
    var visibleOnly: Bool
    var yRange: ClosedRange<Double>?
    var includeChildren: Int
    var property: String?
    var valueLabel: String
    var values: [LoupeMutationValue]
    var animate: Bool
    var animationDuration: Double
    var animationDelay: Double
    var animationCurve: String

    init(_ arguments: [String]) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        timeout = 5
        outputURL = nil
        traceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-set-many-\(Self.timestamp())", isDirectory: true)
        selector = nil
        visibleOnly = true
        yRange = nil
        includeChildren = 0
        property = nil
        valueLabel = "value"
        values = []
        animate = false
        animationDuration = 0.25
        animationDelay = 0
        animationCurve = "easeInOut"

        var positionals: [String] = []
        var index = 0
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
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--trace-dir":
                traceDirectory = URL(fileURLWithPath: try Self.value(after: "--trace-dir", in: arguments, index: &index), isDirectory: true)
            case "--refs":
                selector = .refs(try Self.refList(try Self.value(after: "--refs", in: arguments, index: &index)))
            case "--type-name":
                selector = .typeName(try Self.value(after: "--type-name", in: arguments, index: &index))
            case "--role":
                selector = .role(try Self.value(after: "--role", in: arguments, index: &index))
            case "--all":
                visibleOnly = false
            case "--visible-only":
                visibleOnly = true
            case "--y-range":
                yRange = try Self.range(try Self.value(after: "--y-range", in: arguments, index: &index))
            case "--include-children":
                includeChildren = try Self.int(after: "--include-children", in: arguments, index: &index)
            case "--property", "--key":
                property = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--value":
                valueLabel = "value"
                values = [.string(try Self.value(after: "--value", in: arguments, index: &index))]
            case "--number":
                valueLabel = "number"
                values = [try Self.numberValue(try Self.value(after: "--number", in: arguments, index: &index))]
            case "--bool":
                valueLabel = "bool"
                values = [.bool(try Self.boolValue(try Self.value(after: "--bool", in: arguments, index: &index)))]
            case "--color":
                valueLabel = "color"
                values = [.color(try CLIColorParser.color(try Self.value(after: "--color", in: arguments, index: &index)))]
            case "--colors":
                valueLabel = "colors"
                values = try Self.colorSequence(after: "--colors", in: arguments, index: &index)
            case "--animate":
                animate = true
            case "--no-animate":
                animate = false
            case "--duration":
                animationDuration = try Self.double(after: "--duration", in: arguments, index: &index)
            case "--delay":
                animationDelay = try Self.double(after: "--delay", in: arguments, index: &index)
            case "--curve":
                animationCurve = try Self.value(after: "--curve", in: arguments, index: &index)
            case "--help", "-h":
                throw CLIError(Self.usage)
            default:
                if arguments[index].hasPrefix("--") {
                    throw CLIError("Unknown set-many option: \(arguments[index])")
                }
                positionals.append(arguments[index])
            }
            index += 1
        }

        if property == nil, !positionals.isEmpty {
            property = positionals.removeFirst()
        }
        if values.isEmpty, !positionals.isEmpty {
            valueLabel = "value"
            values = [.string(positionals.removeFirst())]
        }
        guard positionals.isEmpty else {
            throw CLIError("Unexpected set-many arguments: \(positionals.joined(separator: " "))")
        }
        guard selector != nil else {
            throw CLIError("set-many requires --refs, --type-name, or --role")
        }
        guard let property, !property.isEmpty else {
            throw CLIError("set-many requires <property> or --property <property>")
        }
        guard !values.isEmpty else {
            throw CLIError("set-many requires --value, --color, --colors, or a positional value")
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        guard includeChildren >= 0 else {
            throw CLIError("--include-children must be greater than or equal to 0")
        }
        if animate {
            guard animationDuration > 0 else {
                throw CLIError("--duration must be greater than 0")
            }
            guard animationDelay >= 0 else {
                throw CLIError("--delay must be greater than or equal to 0")
            }
        }
    }

    var animation: LoupeMutationAnimation? {
        animate ? LoupeMutationAnimation(duration: animationDuration, delay: animationDelay, curve: animationCurve) : nil
    }

    var selectorDescription: String {
        switch selector {
        case let .refs(refs):
            return "refs:\(refs.joined(separator: ","))"
        case let .typeName(typeName):
            return "typeName:\(typeName)"
        case let .role(role):
            return "role:\(role)"
        case nil:
            return "none"
        }
    }

    static let usage = """
    Usage: loupe set-many (--refs <refs> | --type-name <name> | --role <role>) <property> (--value <value> | --number <n> | --bool <bool> | --color <color> | --colors <colors>)
           loupe set-many --type-name ListCollectionViewCell backgroundColor --colors FDE2E4_1 BEE1E6_1 --include-children 2
           loupe set-many --refs n1,n2 alpha --number 0.5 --trace-dir /tmp/loupe-set-many

    Options:
      --host <url>              Runtime host. Defaults to current runtime or http://127.0.0.1:8765.
      --udid, --device <sim>    Validate the selected runtime belongs to this simulator.
      --bundle-id <id>          Resolve the runtime host by bundle id.
      --trace-dir <path>        Write prev-snapshot.json, next-snapshot.json, diff.json, targets.json, and summary.json.
      --output <path>           Write the compact JSON summary to a file.
      --visible-only            Match only visible nodes. Default.
      --all                     Include hidden nodes.
      --y-range min,max         Filter matched target nodes by frame.y.
      --include-children <n>    Also mutate the first n child refs for each matched target.
      --timeout <seconds>       HTTP timeout. Default 5.
      --animate / --no-animate  Animate or apply immediately. Default --no-animate.

    Colors:
      FFE4E6_1                  Hex RGB plus alpha suffix.
      255,228,230,1             0...255 RGB plus alpha.
      1,0.894,0.902,1           0...1 RGB plus alpha.
      #FDE2E4                   CSS-style hex.
    """

    private static func refList(_ rawValue: String) throws -> [String] {
        let refs = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !refs.isEmpty else {
            throw CLIError("--refs expects one or more comma-separated refs")
        }
        return refs
    }

    private static func colorSequence(after option: String, in arguments: [String], index: inout Int) throws -> [LoupeMutationValue] {
        var values: [LoupeMutationValue] = []
        var valueIndex = index + 1
        while valueIndex < arguments.count, !arguments[valueIndex].hasPrefix("--") {
            let pieces = arguments[valueIndex].split(separator: ";").map(String.init)
            for piece in pieces where !piece.isEmpty {
                values.append(.color(try CLIColorParser.color(piece)))
            }
            valueIndex += 1
        }
        guard !values.isEmpty else {
            throw CLIError("\(option) requires one or more colors")
        }
        index = valueIndex - 1
        return values
    }

    private static func numberValue(_ rawValue: String) throws -> LoupeMutationValue {
        guard let value = Double(rawValue), value.isFinite else {
            throw CLIError("Expected numeric value: \(rawValue)")
        }
        return value.rounded() == value ? .int(Int(value)) : .double(value)
    }

    private static func boolValue(_ rawValue: String) throws -> Bool {
        if ["true", "yes", "1"].contains(rawValue.lowercased()) { return true }
        if ["false", "no", "0"].contains(rawValue.lowercased()) { return false }
        throw CLIError("Expected boolean value: \(rawValue)")
    }

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
        guard let url = URL(string: raw), url.scheme != nil else {
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

    private static func int(after option: String, in arguments: [String], index: inout Int) throws -> Int {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Int(raw) else {
            throw CLIError("\(option) expects an integer")
        }
        return value
    }

    private static func range(_ rawValue: String) throws -> ClosedRange<Double> {
        let parts = rawValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = Double(parts[0]),
              let end = Double(parts[1]),
              start.isFinite,
              end.isFinite,
              start <= end else {
            throw CLIError("--y-range expects min,max")
        }
        return start...end
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}
