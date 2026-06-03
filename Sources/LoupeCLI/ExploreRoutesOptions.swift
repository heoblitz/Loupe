import Foundation
import LoupeCLIModel
import LoupeCore

struct ExploreRoutesOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var limit: Int
    var timeout: TimeInterval
    var settleDelay: TimeInterval
    var outputURL: URL?
    var traceDirectory: URL?
    var backTestID: String?
    var backPoint: LoupePoint
    var json: Bool

    init(_ arguments: [String]) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        limit = 5
        timeout = 5
        settleDelay = 0.6
        backTestID = "BackButton"
        backPoint = LoupePoint(x: 36, y: 84)
        json = false

        var udid: String?
        var bundleID: String?
        var outputURL: URL?
        var traceDirectory: URL?
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
            case "--limit":
                limit = try Self.int(after: "--limit", in: arguments, index: &index)
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--settle":
                settleDelay = try Self.double(after: "--settle", in: arguments, index: &index)
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--trace-dir":
                traceDirectory = URL(fileURLWithPath: try Self.value(after: "--trace-dir", in: arguments, index: &index), isDirectory: true)
            case "--back-test-id":
                backTestID = try Self.value(after: "--back-test-id", in: arguments, index: &index)
            case "--no-back-test-id":
                backTestID = nil
            case "--back-point":
                backPoint = try Self.point(after: "--back-point", in: arguments, index: &index)
            case "--json":
                json = true
            default:
                throw CLIError("Unknown debug trace explore option: \(arguments[index])")
            }
            index += 1
        }

        guard limit > 0 else {
            throw CLIError("--limit must be greater than 0")
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        guard settleDelay >= 0 else {
            throw CLIError("--settle must be zero or greater")
        }

        self.udid = udid
        self.bundleID = bundleID
        self.outputURL = outputURL
        self.traceDirectory = traceDirectory
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func int(after option: String, in arguments: [String], index: inout Int) throws -> Int {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Int(raw) else {
            throw CLIError("\(option) expects an integer")
        }
        return value
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }

    private static func point(after option: String, in arguments: [String], index: inout Int) throws -> LoupePoint {
        let raw = try value(after: option, in: arguments, index: &index)
        let parts = raw.split(separator: ",").map(String.init)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            throw CLIError("\(option) expects x,y")
        }
        return LoupePoint(x: x, y: y)
    }
}
