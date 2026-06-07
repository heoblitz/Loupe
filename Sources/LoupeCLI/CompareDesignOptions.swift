import Foundation
import LoupeCLIModel
import LoupeCore

struct CompareDesignOptions {
    static let usage = "Usage: loupe ui compare-design <snapshot.json> <design.json> [--json] [--suggest-mutations] [--host <url>] [--limit <n>] [--frame-tolerance <n>] [--color-tolerance <n>] [--corner-radius-tolerance <n>] [--font-size-tolerance <n>] [--max-match-distance <n>] [--no-unexpected]"

    var snapshotURL: URL
    var designURL: URL
    var json: Bool
    var suggestMutations: Bool
    var suggestionHost: URL?
    var limit: Int
    var frameTolerance: Double
    var colorTolerance: Double
    var cornerRadiusTolerance: Double
    var fontSizeTolerance: Double
    var maxMatchDistance: Double
    var includeUnexpectedAppNodes: Bool

    init(_ arguments: [String]) throws {
        guard arguments.count >= 2, !arguments[0].hasPrefix("--"), !arguments[1].hasPrefix("--") else {
            throw CLIError(Self.usage)
        }
        snapshotURL = URL(fileURLWithPath: arguments[0])
        designURL = URL(fileURLWithPath: arguments[1])
        json = false
        suggestMutations = false
        suggestionHost = nil
        limit = 20
        frameTolerance = 2
        colorTolerance = 0.03
        cornerRadiusTolerance = 1
        fontSizeTolerance = 1
        maxMatchDistance = 24
        includeUnexpectedAppNodes = true

        var index = 2
        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
            case "--suggest-mutations":
                suggestMutations = true
            case "--host":
                suggestionHost = try Self.url(after: "--host", in: arguments, index: &index)
            case "--limit":
                limit = try Self.positiveInt(after: "--limit", in: arguments, index: &index)
            case "--frame-tolerance":
                frameTolerance = try Self.double(after: "--frame-tolerance", in: arguments, index: &index)
            case "--color-tolerance":
                colorTolerance = try Self.double(after: "--color-tolerance", in: arguments, index: &index)
            case "--corner-radius-tolerance":
                cornerRadiusTolerance = try Self.double(after: "--corner-radius-tolerance", in: arguments, index: &index)
            case "--font-size-tolerance":
                fontSizeTolerance = try Self.double(after: "--font-size-tolerance", in: arguments, index: &index)
            case "--max-match-distance":
                maxMatchDistance = try Self.double(after: "--max-match-distance", in: arguments, index: &index)
            case "--no-unexpected":
                includeUnexpectedAppNodes = false
            default:
                throw CLIError("Unknown compare-design option: \(arguments[index])")
            }
            index += 1
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

    private static func url(after option: String, in arguments: [String], index: inout Int) throws -> URL {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let url = URL(string: raw), url.scheme != nil, url.host != nil else {
            throw CLIError("\(option) expects a URL")
        }
        return url
    }

    private static func positiveInt(after option: String, in arguments: [String], index: inout Int) throws -> Int {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Int(raw), value > 0 else {
            throw CLIError("\(option) expects a positive integer")
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
}
