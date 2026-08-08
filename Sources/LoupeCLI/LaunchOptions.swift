import Foundation
import LoupeCLIModel
import LoupeCore

struct LaunchOptions {
    var bundleID: String
    var device: String
    var dylibPath: String?
    var environment: [String: String]
    var host: URL?
    var port: UInt16?
    var bindHost: String?
    var shouldInject: Bool
    var macOSAppPath: String?
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        var bundleID: String?
        var device = "booted"
        var dylibPath: String?
        var environment: [String: String] = [:]
        var host: URL?
        var port: UInt16?
        var bindHost: String?
        var shouldInject = false
        var macOSAppPath: String?
        var launchMode: String?
        var timeout: TimeInterval = 15
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--bundle-id":
                bundleID = try Self.value(after: argument, in: arguments, index: &index)
            case "--device", "--udid":
                device = try Self.value(after: argument, in: arguments, index: &index)
            case "--macos-app":
                macOSAppPath = try Self.value(after: argument, in: arguments, index: &index)
            case "--dylib":
                if launchMode == "linked" {
                    throw CLIError("--dylib cannot be combined with --linked or --no-inject")
                }
                dylibPath = try Self.value(after: argument, in: arguments, index: &index)
                shouldInject = true
                launchMode = "inject"
            case "--inject":
                if launchMode == "linked" {
                    throw CLIError("--inject cannot be combined with --linked or --no-inject")
                }
                shouldInject = true
                launchMode = "inject"
            case "--linked", "--no-inject":
                if launchMode == "inject" {
                    throw CLIError("\(argument) cannot be combined with --inject or --dylib")
                }
                shouldInject = false
                launchMode = "linked"
            case "--host":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let url = URL(string: raw) else {
                    throw CLIError("Invalid --host URL: \(raw)")
                }
                host = url
            case "--port":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let value = UInt16(raw), value > 0 else {
                    throw CLIError("--port must be a valid TCP port")
                }
                port = value
            case "--bind-host":
                bindHost = try Self.value(after: argument, in: arguments, index: &index)
            case "--env":
                let pair = try Self.value(after: argument, in: arguments, index: &index)
                let pieces = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else {
                    throw CLIError("--env expects KEY=VALUE")
                }
                environment[pieces[0]] = pieces[1]
            case "--timeout":
                timeout = try Self.double(after: argument, in: arguments, index: &index)
            default:
                throw CLIError("Unknown launch option: \(argument)")
            }

            index += 1
        }

        guard let bundleID else {
            throw CLIError("launch requires --bundle-id <id>")
        }
        if macOSAppPath != nil, device != "booted" {
            throw CLIError("--macos-app cannot be combined with --device or --udid")
        }

        self.bundleID = bundleID
        self.device = device
        self.dylibPath = dylibPath
        self.environment = environment
        self.host = host
        self.port = port
        self.bindHost = bindHost
        self.shouldInject = shouldInject
        self.macOSAppPath = macOSAppPath
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        self.timeout = timeout
    }

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
