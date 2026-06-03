import Foundation
import LoupeCLIModel
import LoupeCore

struct MutationSetOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var timeout: TimeInterval
    var outputURL: URL?
    var request: LoupeMutationRequest

    init(_ arguments: [String]) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        timeout = 5
        outputURL = nil

        var selector: LoupeMutationSelector?
        var property: String?
        var rawValue: String?
        var valueType = "auto"
        var layout = true
        var animate = true
        var animationDuration = 0.25
        var animationDelay = 0.0
        var animationCurve = "easeInOut"
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
            case "--test-id", "--testID":
                selector = LoupeMutationSelector(kind: .testID, value: try Self.value(after: arguments[index], in: arguments, index: &index))
            case "--ref":
                selector = LoupeMutationSelector(kind: .ref, value: try Self.value(after: "--ref", in: arguments, index: &index))
            case "--role":
                selector = LoupeMutationSelector(kind: .role, value: try Self.value(after: "--role", in: arguments, index: &index))
            case "--text":
                selector = LoupeMutationSelector(kind: .text, value: try Self.value(after: "--text", in: arguments, index: &index), exact: false)
            case "--property", "--key":
                property = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--value":
                rawValue = try Self.value(after: "--value", in: arguments, index: &index)
            case "--type":
                valueType = try Self.value(after: "--type", in: arguments, index: &index)
            case "--bool":
                valueType = "bool"
                rawValue = try Self.value(after: "--bool", in: arguments, index: &index)
            case "--number":
                valueType = "number"
                rawValue = try Self.value(after: "--number", in: arguments, index: &index)
            case "--string":
                valueType = "string"
                rawValue = try Self.value(after: "--string", in: arguments, index: &index)
            case "--color":
                valueType = "color"
                rawValue = try Self.value(after: "--color", in: arguments, index: &index)
            case "--rect":
                valueType = "rect"
                rawValue = try Self.value(after: "--rect", in: arguments, index: &index)
            case "--point":
                valueType = "point"
                rawValue = try Self.value(after: "--point", in: arguments, index: &index)
            case "--size":
                valueType = "size"
                rawValue = try Self.value(after: "--size", in: arguments, index: &index)
            case "--no-layout":
                layout = false
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
                    throw CLIError("Unknown set option: \(arguments[index])")
                }
                positionals.append(arguments[index])
            }
            index += 1
        }

        if property == nil, !positionals.isEmpty {
            property = positionals.removeFirst()
        }
        if rawValue == nil, !positionals.isEmpty {
            rawValue = positionals.removeFirst()
        }
        guard positionals.isEmpty else {
            throw CLIError("Unexpected set arguments: \(positionals.joined(separator: " "))")
        }
        guard let selector else {
            throw CLIError("set requires --test-id, --ref, --role, or --text")
        }
        guard let property, !property.isEmpty else {
            throw CLIError("set requires <property> or --property <property>")
        }
        guard let rawValue else {
            throw CLIError("set requires <value> or --value <value>")
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        if animate {
            guard animationDuration > 0 else {
                throw CLIError("--duration must be greater than 0")
            }
            guard animationDelay >= 0 else {
                throw CLIError("--delay must be greater than or equal to 0")
            }
        }

        let value = try Self.mutationValue(rawValue, type: valueType, property: property)
        let animation = animate
            ? LoupeMutationAnimation(duration: animationDuration, delay: animationDelay, curve: animationCurve)
            : nil
        request = LoupeMutationRequest(
            selector: selector,
            property: property,
            value: value,
            layout: layout,
            animation: animation
        )
    }

    static let usage = """
    Usage: loupe ui set (--test-id <id> | --ref <ref> | --role <role> | --text <text>) <property> <value> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]
           loupe ui set --test-id card.title text "New title"
           loupe ui set --test-id card backgroundColor --color '#ff3366'
           loupe ui set --test-id card.title text "New title" --output /tmp/loupe-set.json
           loupe ui set --test-id card frame --rect 20,120,220,80
           loupe ui set --test-id card frame --rect 20,120,220,80 --duration 0.3
           loupe ui set --test-id card frame --rect 20,120,220,80 --no-animate
    """

    private static func mutationValue(_ rawValue: String, type: String, property: String) throws -> LoupeMutationValue {
        switch type.lowercased() {
        case "auto":
            return try inferredMutationValue(rawValue, property: property)
        case "bool":
            return .bool(try bool(rawValue))
        case "int":
            guard let value = Int(rawValue) else { throw CLIError("Expected integer value: \(rawValue)") }
            return .int(value)
        case "number", "double":
            guard let value = Double(rawValue) else { throw CLIError("Expected numeric value: \(rawValue)") }
            return value.rounded() == value ? .int(Int(value)) : .double(value)
        case "string":
            return .string(rawValue)
        case "color":
            return .color(try CLIColorParser.color(rawValue))
        case "rect":
            return .rect(try rect(rawValue))
        case "point":
            return .point(try point(rawValue))
        case "size":
            return .size(try size(rawValue))
        default:
            throw CLIError("Unknown set value type: \(type)")
        }
    }

    private static func inferredMutationValue(_ rawValue: String, property: String) throws -> LoupeMutationValue {
        let normalized = property.lowercased()
        if normalized.contains("color") || rawValue.hasPrefix("#") {
            return .color(try CLIColorParser.color(rawValue))
        }
        if stringLikeProperty(normalized) {
            return .string(rawValue)
        }
        if normalized == "frame" || normalized == "bounds" {
            return .rect(try rect(rawValue))
        }
        if normalized == "center" || normalized.hasSuffix(".center") || normalized.hasSuffix("point") {
            return .point(try point(rawValue))
        }
        if normalized.contains("offset") || normalized.hasSuffix("size") {
            return .size(try size(rawValue))
        }
        if ["true", "false", "yes", "no", "0", "1"].contains(rawValue.lowercased()),
           normalized.contains("hidden")
            || normalized.contains("enabled")
            || normalized.contains("opaque")
            || normalized.contains("clip")
            || normalized.contains("ison")
            || normalized.contains("iselement") {
            return .bool(try bool(rawValue))
        }
        if let int = Int(rawValue) {
            return .int(int)
        }
        if let double = Double(rawValue), double.isFinite {
            return .double(double)
        }
        return .string(rawValue)
    }

    private static func stringLikeProperty(_ normalizedProperty: String) -> Bool {
        normalizedProperty == "text"
            || normalizedProperty.hasSuffix(".text")
            || normalizedProperty == "label"
            || normalizedProperty.hasSuffix(".label")
            || normalizedProperty == "placeholder"
            || normalizedProperty.hasSuffix(".placeholder")
            || normalizedProperty == "accessibility.value"
            || normalizedProperty == "accessibility.hint"
            || normalizedProperty == "accessibility.identifier"
            || normalizedProperty == "testid"
    }

    private static func bool(_ rawValue: String) throws -> Bool {
        if ["true", "yes", "1"].contains(rawValue.lowercased()) { return true }
        if ["false", "no", "0"].contains(rawValue.lowercased()) { return false }
        throw CLIError("Expected boolean value: \(rawValue)")
    }

    private static func rect(_ rawValue: String) throws -> LoupeRect {
        let values = try doubles(rawValue, expected: [4], label: "rect")
        return LoupeRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    private static func point(_ rawValue: String) throws -> LoupePoint {
        let values = try doubles(rawValue, expected: [2], label: "point")
        return LoupePoint(x: values[0], y: values[1])
    }

    private static func size(_ rawValue: String) throws -> LoupeSize {
        let values = try doubles(rawValue, expected: [2], label: "size")
        return LoupeSize(width: values[0], height: values[1])
    }

    private static func doubles(_ rawValue: String, expected: [Int], label: String) throws -> [Double] {
        let values = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard expected.contains(values.count) else {
            throw CLIError("Expected \(label) with \(expected.map(String.init).joined(separator: " or ")) comma-separated numbers")
        }
        return try values.map { value in
            guard let double = Double(value), double.isFinite else {
                throw CLIError("Invalid \(label) number: \(value)")
            }
            return double
        }
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

    private static func url(after option: String, in arguments: [String], index: inout Int) throws -> URL {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let url = URL(string: raw) else {
            throw CLIError("Invalid URL for \(option): \(raw)")
        }
        return url
    }
}
