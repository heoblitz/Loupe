import Foundation
import LoupeCLIModel
import LoupeCore

struct InspectOptions {
    var snapshotURL: URL
    var selector: LoupeSelector
    var includeHidden: Bool
    var fields: Set<String>?

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe ui node <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--include-hidden] [--fields node,parent,children,siblings]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        includeHidden = false
        fields = nil

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
            case "--include-hidden":
                includeHidden = true
            case "--fields":
                fields = try Self.fields(try Self.value(after: "--fields", in: arguments, index: &index))
            case "--node-only":
                fields = ["node"]
            default:
                throw CLIError("Unknown inspect option: \(arguments[index])")
            }
            index += 1
        }

        guard let selector else {
            throw CLIError("ui node requires --test-id, --text, --role, or --ref")
        }

        self.selector = selector
    }

    private static func fields(_ rawValue: String) throws -> Set<String> {
        let allowed: Set<String> = ["node", "parent", "children", "siblings"]
        let fields = Set(
            rawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !fields.isEmpty, fields.isSubset(of: allowed) else {
            throw CLIError("--fields expects a comma-separated subset of node,parent,children,siblings")
        }
        return fields
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
}
