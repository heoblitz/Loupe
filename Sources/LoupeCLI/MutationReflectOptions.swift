import Foundation
import LoupeCLIModel
import LoupeCore

struct MutationReflectOptions {
    var mutationURL: URL
    var sourceRoot: URL
    var outputURL: URL?

    init(_ arguments: [String]) throws {
        guard let first = arguments.first, !first.hasPrefix("--") else {
            throw CLIError("Usage: loupe ui reflect <mutation-response.json> --source <dir> [--output <path>]")
        }

        mutationURL = URL(fileURLWithPath: first)
        sourceRoot = URL(fileURLWithPath: ".")
        outputURL = nil
        var resolvedSourceRoot: URL?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--source", "--source-root":
                resolvedSourceRoot = URL(fileURLWithPath: try Self.value(after: arguments[index], in: arguments, index: &index))
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--help", "-h":
                throw CLIError("Usage: loupe ui reflect <mutation-response.json> --source <dir> [--output <path>]")
            default:
                throw CLIError("Unknown reflect option: \(arguments[index])")
            }
            index += 1
        }

        guard let resolvedSourceRoot else {
            throw CLIError("reflect requires --source <dir>")
        }
        sourceRoot = resolvedSourceRoot
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
