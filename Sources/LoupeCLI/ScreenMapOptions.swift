import Foundation
import LoupeCLIModel

struct ScreenMapOptions {
    var snapshotURL: URL?
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var includeHidden: Bool
    var includeContainers: Bool
    var maxElements: Int
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        snapshotURL = nil
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        includeHidden = false
        includeContainers = false
        maxElements = 200
        timeout = 5

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
            case "--include-hidden":
                includeHidden = true
            case "--include-containers":
                includeContainers = true
            case "--limit":
                let raw = try Self.value(after: "--limit", in: arguments, index: &index)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError("--limit expects a positive integer")
                }
                maxElements = value
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            default:
                throw CLIError("Unknown ui screen option: \(arguments[index])")
            }
            index += 1
        }

        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        if snapshotURL != nil, hostWasExplicit || udid != nil || bundleID != nil {
            throw CLIError("snapshot.json cannot be combined with --host, --udid, or --bundle-id")
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
}
