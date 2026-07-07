import Foundation
import LoupeCLIModel

struct CaptureReportOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var outputDirectory: URL
    var screenMapLimit: Int
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        outputDirectory = Self.defaultOutputDirectory()
        screenMapLimit = 120
        timeout = 5

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
                outputDirectory = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--screen-map-limit":
                let raw = try Self.value(after: "--screen-map-limit", in: arguments, index: &index)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError("--screen-map-limit expects a positive integer")
                }
                screenMapLimit = value
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            default:
                throw CLIError("Unknown ui report option: \(arguments[index])")
            }
            index += 1
        }

        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
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

    private static func defaultOutputDirectory() -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-report-\(stamp)", isDirectory: true)
    }
}
