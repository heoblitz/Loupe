import Foundation
import LoupeCLIModel
import LoupeCore

struct MutationListOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var selector: LoupeSelector?
    var includeHidden: Bool
    var outputURL: URL?
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        udid = nil
        bundleID = nil
        selector = nil
        includeHidden = false
        outputURL = nil
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
            case "--ref":
                try UniqueSelector.set(.ref(try Self.value(after: "--ref", in: arguments, index: &index)), on: &selector)
            case "--test-id":
                try UniqueSelector.set(.testID(try Self.value(after: "--test-id", in: arguments, index: &index)), on: &selector)
            case "--text":
                try UniqueSelector.set(.text(try Self.value(after: "--text", in: arguments, index: &index), exact: false), on: &selector)
            case "--exact-text":
                try UniqueSelector.set(.text(try Self.value(after: "--exact-text", in: arguments, index: &index), exact: true), on: &selector)
            case "--role":
                try UniqueSelector.set(.role(try Self.value(after: "--role", in: arguments, index: &index)), on: &selector)
            case "--include-hidden":
                includeHidden = true
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            default:
                throw CLIError("Unknown mutations option: \(arguments[index])")
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
}
