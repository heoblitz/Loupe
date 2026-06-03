import Foundation
import LoupeCLIModel
import LoupeCore

struct AccessibilityOptions {
    var snapshotURL: URL
    var includeHidden: Bool

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe ui accessibility <snapshot.json> [--include-hidden]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        includeHidden = false

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--include-hidden":
                includeHidden = true
            default:
                throw CLIError("Unknown accessibility option: \(arguments[index])")
            }
            index += 1
        }
    }
}
