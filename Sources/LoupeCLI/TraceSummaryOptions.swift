import Foundation
import LoupeCLIModel
import LoupeCore

struct TraceSummaryOptions {
    var directory: URL
    var json: Bool
    var limit: Int

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe debug trace summary <trace-dir> [--json] [--limit <n>]")
        }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        json = false
        limit = 20

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
            case "--limit":
                let raw = try Self.value(after: "--limit", in: arguments, index: &index)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError("--limit expects a positive integer")
                }
                limit = value
            default:
                throw CLIError("Unknown trace-summary option: \(arguments[index])")
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
}
