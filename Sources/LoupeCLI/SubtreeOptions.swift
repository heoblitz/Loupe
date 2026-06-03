import Foundation
import LoupeCLIModel
import LoupeCore

struct SubtreeOptions {
    var snapshotURL: URL
    var selector: LoupeSelector
    var includeHidden: Bool
    var depth: Int

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe ui subtree <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--depth <n>] [--include-hidden]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        includeHidden = false
        depth = 2

        var selector: LoupeSelector?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
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
            case "--depth":
                let raw = try Self.value(after: "--depth", in: arguments, index: &index)
                guard let value = Int(raw), value >= 0 else {
                    throw CLIError("--depth expects a non-negative integer")
                }
                depth = value
            case "--include-hidden":
                includeHidden = true
            default:
                throw CLIError("Unknown subtree option: \(arguments[index])")
            }
            index += 1
        }

        guard let selector else {
            throw CLIError("ui subtree requires --test-id, --text, --role, or --ref")
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
}
