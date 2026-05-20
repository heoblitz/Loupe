import Foundation
import LoupeCLIModel
import LoupeCore

struct WaitForOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var selector: LoupeSelector
    var timeout: TimeInterval
    var interval: TimeInterval
    var keyPath: String?
    var expectedValue: String?
    var outputURL: URL?

    init(
        host: URL,
        hostWasExplicit: Bool = true,
        udid: String? = nil,
        bundleID: String? = nil,
        selector: LoupeSelector,
        timeout: TimeInterval,
        interval: TimeInterval,
        keyPath: String?,
        expectedValue: String?,
        outputURL: URL? = nil
    ) {
        self.host = host
        self.hostWasExplicit = hostWasExplicit
        self.udid = udid
        self.bundleID = bundleID
        self.selector = selector
        self.timeout = timeout
        self.interval = interval
        self.keyPath = keyPath
        self.expectedValue = expectedValue
        self.outputURL = outputURL
    }

    init(_ arguments: [String], mode: WaitMode) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        timeout = 10
        interval = 0.25
        keyPath = nil
        expectedValue = nil
        outputURL = nil

        var selector: LoupeSelector?
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
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--interval":
                interval = try Self.double(after: "--interval", in: arguments, index: &index)
            case "--key":
                keyPath = try Self.value(after: "--key", in: arguments, index: &index)
            case "--equals":
                expectedValue = try Self.value(after: "--equals", in: arguments, index: &index)
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            default:
                if case .value = mode, !arguments[index].hasPrefix("--") {
                    throw CLIError("wait-for-value expects --key <path> --equals <value>; example: loupe wait-for-value --test-id example.status --key text --equals Done")
                }
                throw CLIError("Unknown wait-for option: \(arguments[index])")
            }
            index += 1
        }

        guard let selector else {
            throw CLIError("wait-for requires --test-id, --text, --role, or --ref")
        }
        if case .value = mode, (keyPath == nil || expectedValue == nil) {
            throw CLIError("wait-for-value requires --key <path> and --equals <value>; example: loupe wait-for-value --test-id example.status --key text --equals Done")
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        guard interval > 0 else {
            throw CLIError("--interval must be greater than 0")
        }

        self.selector = selector
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
