import Foundation
import LoupeCore

package struct AccessibilityActionOptions {
    package var host = URL(string: "http://127.0.0.1:8765")!
    package var hostWasExplicit = false
    package var udid: String?
    package var udidWasExplicit = false
    package var timeout: TimeInterval = 8
    package var targetAlias: Int?
    package var selector: LoupeSelector?
    package var action: LoupeAccessibilityAction

    package init(arguments: [String]) throws {
        var targetAlias: Int?
        var selector: LoupeSelector?
        var actionRaw: String?
        var index = 0

        if let first = arguments.first, first.hasPrefix("#") {
            targetAlias = try Self.targetAlias(first)
            index = 1
            if index < arguments.count, !arguments[index].hasPrefix("--") {
                actionRaw = arguments[index]
                index += 1
            }
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--host":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let url = URL(string: raw) else { throw CLIError("Invalid URL for --host: \(raw)") }
                host = url
                hostWasExplicit = true
            case "--udid", "--device":
                udid = try Self.value(after: argument, in: arguments, index: &index)
                udidWasExplicit = true
            case "--timeout":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let value = Double(raw), value > 0 else { throw CLIError("--timeout must be greater than 0") }
                timeout = value
            case "--test-id":
                selector = .testID(try Self.value(after: argument, in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: argument, in: arguments, index: &index))
            case "--action":
                actionRaw = try Self.value(after: argument, in: arguments, index: &index)
            default:
                throw CLIError("Unknown perform option: \(argument)")
            }
            index += 1
        }

        let targetCount = [targetAlias != nil, selector != nil].filter { $0 }.count
        guard targetCount == 1 else {
            throw CLIError("perform requires exactly one target: '#N', --test-id, or --ref")
        }
        guard let actionRaw, !actionRaw.isEmpty else {
            throw CLIError("perform requires an action, for example: loupe act perform '#2' increment")
        }
        let action = LoupeAccessibilityAction.parse(actionRaw)
        if action.name == "custom", action.customName?.isEmpty != false {
            throw CLIError("custom action requires a name, for example: 'custom:Copy link'")
        }

        self.targetAlias = targetAlias
        self.selector = selector
        self.action = action
    }

    private static func targetAlias(_ raw: String) throws -> Int {
        let digits = raw.dropFirst()
        guard raw.first == "#",
              !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              digits.first != "0",
              let value = Int(digits) else {
            throw CLIError("Invalid action target alias: \(raw). Rerun `loupe act targets`")
        }
        return value
    }

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else { throw CLIError("\(option) requires a value") }
        index = valueIndex
        return arguments[valueIndex]
    }
}

package struct TargetedInputOptions {
    package var targetArguments: [String]
    package var text: String
    package var commonArguments: [String]

    package init(arguments: [String]) throws {
        if arguments.count >= 2, arguments[0].hasPrefix("#") {
            _ = try AccessibilityActionOptions(arguments: [arguments[0], "activate"])
            targetArguments = [arguments[0]]
            text = arguments[1]
            commonArguments = Array(arguments.dropFirst(2))
            return
        }

        var targetArguments: [String] = []
        var commonArguments: [String] = []
        var text: String?
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else { throw CLIError("\(option) requires a value") }
            let value = arguments[index + 1]
            switch option {
            case "--test-id", "--ref":
                targetArguments.append(contentsOf: [option, value])
            case "--text":
                text = value
            case "--host", "--udid", "--device", "--timeout":
                commonArguments.append(contentsOf: [option, value])
            default:
                throw CLIError("Unknown input option: \(option)")
            }
            index += 2
        }
        guard targetArguments.count == 2 else {
            throw CLIError("input requires exactly one target: '#N', --test-id, or --ref")
        }
        guard let text else { throw CLIError("input with --test-id or --ref requires --text <text>") }
        self.targetArguments = targetArguments
        self.text = text
        self.commonArguments = commonArguments
    }
}
