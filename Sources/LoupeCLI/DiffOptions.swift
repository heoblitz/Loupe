import Foundation
import LoupeCLIModel
import LoupeCore

struct DiffOptions {
    var beforeURL: URL
    var afterURL: URL
    var json: Bool
    var limit: Int
    var changedOnly: Bool

    init(_ arguments: [String]) throws {
        guard arguments.count >= 2, !arguments[0].hasPrefix("--"), !arguments[1].hasPrefix("--") else {
            throw CLIError("Usage: loupe diff <before-snapshot.json> <after-snapshot.json> [--json] [--changed-only] [--limit <n>]")
        }
        beforeURL = URL(fileURLWithPath: arguments[0])
        afterURL = URL(fileURLWithPath: arguments[1])
        json = false
        limit = 20
        changedOnly = false

        var index = 2
        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
            case "--changed-only", "--changes-only":
                changedOnly = true
            case "--limit":
                let raw = try Self.value(after: "--limit", in: arguments, index: &index)
                guard let value = Int(raw), value > 0 else {
                    throw CLIError("--limit expects a positive integer")
                }
                limit = value
            default:
                throw CLIError("Unknown diff option: \(arguments[index])")
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
