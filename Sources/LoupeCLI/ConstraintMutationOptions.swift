import Foundation
import LoupeCLIModel
import LoupeCore

struct ConstraintMutationOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var outputURL: URL?
    var timeout: TimeInterval
    var request: LoupeConstraintMutationRequest

    init(_ arguments: [String], deactivate: Bool) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        outputURL = nil
        timeout = 5

        var id: String?
        var constant: Double?
        var priority: Double?
        var isActive: Bool? = deactivate ? false : nil
        var layout = true
        var positionals: [String] = []
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--host":
                let raw = try Self.value(after: "--host", in: arguments, index: &index)
                guard let url = URL(string: raw) else {
                    throw CLIError("Invalid --host URL: \(raw)")
                }
                host = url
                hostWasExplicit = true
            case "--udid", "--device":
                udid = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--bundle-id":
                bundleID = try Self.value(after: "--bundle-id", in: arguments, index: &index)
            case "--id":
                id = try Self.value(after: "--id", in: arguments, index: &index)
            case "--constant":
                constant = try Self.double(after: "--constant", in: arguments, index: &index)
            case "--priority":
                priority = try Self.double(after: "--priority", in: arguments, index: &index)
            case "--active", "--is-active":
                isActive = try Self.bool(try Self.value(after: arguments[index], in: arguments, index: &index))
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--no-layout":
                layout = false
            case "--help", "-h":
                throw CLIError(Self.usage(deactivate: deactivate))
            default:
                if arguments[index].hasPrefix("--") {
                    throw CLIError("Unknown constraint option: \(arguments[index])")
                }
                positionals.append(arguments[index])
            }
            index += 1
        }

        if id == nil, let first = positionals.first, first.hasPrefix("c") {
            id = positionals.removeFirst()
        }
        while positionals.count >= 2 {
            let property = positionals.removeFirst()
            let rawValue = positionals.removeFirst()
            switch property {
            case "constant":
                guard let value = Double(rawValue) else { throw CLIError("constant expects a number") }
                constant = value
            case "priority":
                guard let value = Double(rawValue) else { throw CLIError("priority expects a number") }
                priority = value
            case "active", "isActive":
                isActive = try Self.bool(rawValue)
            default:
                throw CLIError("Unknown constraint property: \(property)")
            }
        }
        guard positionals.isEmpty else {
            throw CLIError("Unexpected constraint arguments: \(positionals.joined(separator: " "))")
        }
        guard let id, !id.isEmpty else {
            throw CLIError("constraint mutation requires --id <constraint-id>")
        }
        guard constant != nil || priority != nil || isActive != nil else {
            throw CLIError("constraint mutation requires constant, priority, or active")
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }

        request = LoupeConstraintMutationRequest(
            id: id,
            constant: constant,
            priority: priority,
            isActive: isActive,
            layout: layout
        )
    }

    static func usage(deactivate: Bool) -> String {
        if deactivate {
            return "Usage: loupe ui deactivate-constraint --id <constraint-id> [--host <url>]"
        }
        return "Usage: loupe ui set-constraint --id <constraint-id> constant <value> [priority <value>] [active true|false]"
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

    private static func bool(_ rawValue: String) throws -> Bool {
        if ["true", "yes", "1"].contains(rawValue.lowercased()) { return true }
        if ["false", "no", "0"].contains(rawValue.lowercased()) { return false }
        throw CLIError("Expected boolean value: \(rawValue)")
    }
}
