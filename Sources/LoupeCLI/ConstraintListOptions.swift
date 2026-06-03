import Foundation
import LoupeCLIModel
import LoupeCore

struct ConstraintListOptions {
    var snapshotURL: URL?
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var selector: LoupeSelector
    var includeHidden: Bool
    var outputURL: URL?
    var json: Bool
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        snapshotURL = nil
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        includeHidden = false
        outputURL = nil
        json = false
        timeout = 5

        var selector: LoupeSelector?
        var index = 0
        if let first = arguments.first, !first.hasPrefix("--") {
            snapshotURL = URL(fileURLWithPath: first)
            index = 1
        }

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
            case "--ref":
                selector = .ref(try Self.value(after: "--ref", in: arguments, index: &index))
            case "--test-id":
                selector = .testID(try Self.value(after: "--test-id", in: arguments, index: &index))
            case "--text":
                selector = .text(try Self.value(after: "--text", in: arguments, index: &index), exact: false)
            case "--exact-text":
                selector = .text(try Self.value(after: "--exact-text", in: arguments, index: &index), exact: true)
            case "--role":
                selector = .role(try Self.value(after: "--role", in: arguments, index: &index))
            case "--include-hidden":
                includeHidden = true
            case "--json":
                json = true
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--help", "-h":
                throw CLIError(Self.usage)
            default:
                throw CLIError("Unknown constraints option: \(arguments[index])")
            }
            index += 1
        }

        guard let selector else {
            throw CLIError(Self.usage)
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        self.selector = selector
    }

    static let usage = """
    Usage: loupe ui constraints [snapshot.json] (--ref <ref> | --test-id <id> | --text <text>) [--json]
    """

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
}
