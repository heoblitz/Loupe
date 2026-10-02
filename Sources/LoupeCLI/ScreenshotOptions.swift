import Foundation
import LoupeCLIModel
import LoupeCore

struct ScreenshotOptions {
    var udid: String
    var outputPath: String
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        var udid = "booted"
        var outputPath: String?
        var timeout: TimeInterval = 10
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--udid", "--device":
                udid = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--output":
                outputPath = try Self.value(after: "--output", in: arguments, index: &index)
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            default:
                throw CLIError("Unknown screenshot option: \(arguments[index])")
            }
            index += 1
        }
        guard let outputPath else {
            throw CLIError("screenshot requires --output <path>")
        }
        self.udid = udid
        self.outputPath = outputPath
        guard timeout.isFinite, timeout > 0 else {
            throw CLIError("--timeout must be finite and greater than 0")
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
