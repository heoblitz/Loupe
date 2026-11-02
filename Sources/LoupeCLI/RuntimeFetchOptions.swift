import Foundation
import LoupeCLIModel
import LoupeCore

struct RuntimeFetchOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var outputURL: URL?
    var timeout: TimeInterval

    init(
        host: URL,
        hostWasExplicit: Bool,
        udid: String?,
        bundleID: String?,
        outputURL: URL?,
        timeout: TimeInterval
    ) {
        self.host = host
        self.hostWasExplicit = hostWasExplicit
        self.udid = udid
        self.bundleID = bundleID
        self.outputURL = outputURL
        self.timeout = timeout
    }

    init(_ arguments: [String], usage: String, defaultTimeout: TimeInterval = 5) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        var udid: String?
        var bundleID: String?
        var outputURL: URL?
        var timeout = defaultTimeout
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
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--help", "-h":
                throw CLIError(usage)
            default:
                throw CLIError("Unknown runtime option: \(arguments[index])")
            }
            index += 1
        }
        self.udid = udid
        self.bundleID = bundleID
        self.outputURL = outputURL
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        self.timeout = timeout
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
