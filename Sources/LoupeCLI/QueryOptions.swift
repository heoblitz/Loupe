import Foundation
import LoupeCLIModel
import LoupeCore

struct QueryOptions {
    var snapshotURL: URL?
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var selector: LoupeSelector
    var includeHidden: Bool
    var maxResults: Int
    var tree: QueryTree
    var waitForMatch: Bool
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        if arguments.isEmpty {
            throw CLIError(Self.usage)
        }

        snapshotURL = nil
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        includeHidden = false
        maxResults = 50
        tree = .view
        waitForMatch = false
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
            case "--test-id":
                selector = .testID(try Self.value(after: "--test-id", in: arguments, index: &index))
            case "--text":
                selector = .text(try Self.value(after: "--text", in: arguments, index: &index), exact: false)
            case "--exact-text":
                selector = .text(try Self.value(after: "--exact-text", in: arguments, index: &index), exact: true)
            case "--role":
                selector = .role(try Self.value(after: "--role", in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: "--ref", in: arguments, index: &index))
            case "--include-hidden":
                includeHidden = true
            case "--max-results":
                let rawValue = try Self.value(after: "--max-results", in: arguments, index: &index)
                guard let value = Int(rawValue), value > 0 else {
                    throw CLIError("--max-results expects a positive integer")
                }
                maxResults = value
            case "--tree":
                let rawValue = try Self.value(after: "--tree", in: arguments, index: &index)
                guard let value = QueryTree(rawValue: rawValue) else {
                    throw CLIError("--tree expects view or accessibility")
                }
                tree = value
            case "--wait":
                waitForMatch = true
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            default:
                throw CLIError("Unknown query option: \(arguments[index])")
            }

            index += 1
        }

        guard let selector else {
            throw CLIError("query requires one selector option")
        }
        if waitForMatch, snapshotURL != nil {
            throw CLIError("--wait requires a live runtime query; omit snapshot.json")
        }

        self.selector = selector
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
    }

    static let usage = "Usage: loupe ui query [snapshot.json] (--test-id <id> | --text <text> | --exact-text <text> | --role <role> | --ref <ref>) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--tree view|accessibility] [--include-hidden] [--max-results <n>] [--wait] [--timeout <seconds>]"

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
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
