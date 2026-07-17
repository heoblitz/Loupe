import Foundation
import LoupeCore

package struct ActionOptions: ActionDispatchOptions {
    package var command: String
    package var host: URL
    package var hostWasExplicit: Bool
    package var backend: String
    package var udid: String
    package var udidWasExplicit: Bool
    package var timeout: TimeInterval
    package var selector: LoupeSelector?
    package var targetAlias: Int?
    package var snapshotURL: URL?
    package var point: LoupePoint?
    package var endPoint: LoupePoint?
    package var screen: LoupeSize
    package var duration: Double?
    package var text: String?
    package var press: String?
    package var startSpread: Double?
    package var endSpread: Double?
    package var traceDirectory: URL?
    package var expectVisibleTestID: String?
    package var expectVisibleSelector: LoupeSelector?
    package var verifyScroll: Bool

    package init(command: String, arguments: [String]) throws {
        self.command = command
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        backend = "auto"
        udid = "booted"
        udidWasExplicit = false
        timeout = 8
        screen = LoupeSize(width: 0, height: 0)

        var selector: LoupeSelector?
        var targetAlias: Int?
        var snapshotURL: URL?
        var point: LoupePoint?
        var endPoint: LoupePoint?
        var duration: Double?
        var text: String?
        var press: String?
        var startSpread: Double?
        var endSpread: Double?
        var traceDirectory: URL?
        var expectVisibleTestID: String?
        var expectVisibleSelector: LoupeSelector?
        var verifyScroll = true
        var screenWidth: Double?
        var screenHeight: Double?
        var hasX = false
        var hasY = false
        var index = 0

        if command == "tap", let first = arguments.first, !first.hasPrefix("--") {
            targetAlias = try Self.targetAlias(first)
            index = 1
        }
        if command == "type", let first = arguments.first, !first.hasPrefix("--") {
            text = first
            index = 1
        }
        if command == "press", let first = arguments.first, !first.hasPrefix("--") {
            press = try Self.pressButton(first)
            index = 1
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--host":
                host = try Self.url(after: argument, in: arguments, index: &index)
                hostWasExplicit = true
            case "--backend":
                backend = try Self.value(after: argument, in: arguments, index: &index)
            case "--udid", "--device":
                udid = try Self.value(after: argument, in: arguments, index: &index)
                udidWasExplicit = true
            case "--test-id":
                selector = .testID(try Self.value(after: argument, in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: argument, in: arguments, index: &index))
            case "--snapshot":
                snapshotURL = URL(fileURLWithPath: try Self.value(after: argument, in: arguments, index: &index))
            case "--text":
                let value = try Self.value(after: argument, in: arguments, index: &index)
                if command == "type" {
                    text = value
                } else if command == "press" {
                    throw CLIError("press expects a button: up|down|left|right|select|menu|playPause")
                } else if command == "tap" {
                    throw CLIError("tap expects --test-id, --ref, or coordinates")
                } else {
                    throw CLIError("\(command) expects --test-id, --ref, or coordinates")
                }
            case "--exact-text":
                _ = try Self.value(after: argument, in: arguments, index: &index)
                if command == "press" {
                    throw CLIError("press expects a button: up|down|left|right|select|menu|playPause")
                }
                if command == "tap" {
                    throw CLIError("tap expects --test-id, --ref, or coordinates")
                }
                throw CLIError("\(command) expects --test-id, --ref, or coordinates")
            case "--x":
                let x = try Self.double(after: argument, in: arguments, index: &index)
                let y = point?.y ?? 0
                point = LoupePoint(x: x, y: y)
                hasX = true
            case "--y":
                let y = try Self.double(after: argument, in: arguments, index: &index)
                let x = point?.x ?? 0
                point = LoupePoint(x: x, y: y)
                hasY = true
            case "--from", "--center":
                point = try Self.point(after: argument, in: arguments, index: &index)
            case "--to":
                endPoint = try Self.point(after: argument, in: arguments, index: &index)
            case "--width":
                screenWidth = try Self.double(after: argument, in: arguments, index: &index)
            case "--height":
                screenHeight = try Self.double(after: argument, in: arguments, index: &index)
            case "--duration":
                duration = try Self.double(after: argument, in: arguments, index: &index)
            case "--timeout":
                timeout = try Self.double(after: argument, in: arguments, index: &index)
            case "--start-spread":
                startSpread = try Self.double(after: argument, in: arguments, index: &index)
            case "--end-spread":
                endSpread = try Self.double(after: argument, in: arguments, index: &index)
            case "--trace-dir":
                traceDirectory = URL(fileURLWithPath: try Self.value(after: argument, in: arguments, index: &index))
            case "--expect-visible":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                let selector = Self.expectVisibleSelector(from: raw)
                expectVisibleSelector = selector
                if case let .testID(testID) = selector {
                    expectVisibleTestID = testID
                }
            case "--no-verify-scroll":
                verifyScroll = false
            default:
                throw CLIError("Unknown \(command) option: \(argument)")
            }
            index += 1
        }

        if let screenWidth, let screenHeight {
            screen = LoupeSize(width: screenWidth, height: screenHeight)
        }

        if command == "type", text == nil {
            throw CLIError("type requires text")
        }
        if command == "press", press == nil {
            throw CLIError("press requires a button: up|down|left|right|select|menu|playPause")
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }

        if hasX != hasY {
            throw CLIError("--x and --y must be provided together")
        }

        if command == "tap" {
            let targetCount = [selector != nil, point != nil, targetAlias != nil].filter { $0 }.count
            if targetCount > 1 {
                throw CLIError("tap accepts exactly one target: '#N', --test-id, --ref, or --x <n> --y <n>")
            }
            if targetCount == 0 {
                throw CLIError("tap requires '#N', --test-id, --ref, or --x <n> --y <n>")
            }
            if targetAlias != nil, snapshotURL != nil {
                throw CLIError("tap '#N' does not accept --snapshot; rerun `loupe act targets`")
            }
        }
        if command == "press" {
            if selector != nil || point != nil || endPoint != nil || snapshotURL != nil {
                throw CLIError("press does not accept selectors, coordinates, or snapshots")
            }
        }

        self.selector = selector
        self.targetAlias = targetAlias
        self.snapshotURL = snapshotURL
        self.point = point
        self.endPoint = endPoint
        self.duration = duration
        self.text = text
        self.press = press
        self.startSpread = startSpread
        self.endSpread = endSpread
        self.traceDirectory = traceDirectory
        self.expectVisibleTestID = expectVisibleTestID
        self.expectVisibleSelector = expectVisibleSelector
        self.verifyScroll = verifyScroll
    }

    private static func targetAlias(_ raw: String) throws -> Int {
        guard raw.first == "#" else {
            throw CLIError("Unknown tap target: \(raw). Use a quoted alias such as '#1', --test-id, --ref, or coordinates")
        }
        let digits = raw.dropFirst()
        guard !digits.isEmpty,
              digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              digits.first != "0",
              let value = Int(digits) else {
            throw CLIError("Invalid action target alias: \(raw). Run `loupe act targets` and use a quoted alias such as '#1'")
        }
        return value
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

    private static func point(after option: String, in arguments: [String], index: inout Int) throws -> LoupePoint {
        let raw = try value(after: option, in: arguments, index: &index)
        let parts = raw.split(separator: ",").map(String.init)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            throw CLIError("\(option) expects x,y")
        }
        return LoupePoint(x: x, y: y)
    }

    private static func url(after option: String, in arguments: [String], index: inout Int) throws -> URL {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let url = URL(string: raw) else {
            throw CLIError("Invalid URL for \(option): \(raw)")
        }
        return url
    }

    private static func expectVisibleSelector(from raw: String) -> LoupeSelector {
        guard let delimiter = raw.firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return .testID(raw)
        }

        let key = raw[..<delimiter]
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
        let valueStart = raw.index(after: delimiter)
        let value = String(raw[valueStart...])

        switch key {
        case "testid", "id":
            return .testID(value)
        case "ref":
            return .ref(value)
        case "role":
            return .role(value)
        case "text", "containstext":
            return .text(value, exact: false)
        case "exacttext":
            return .text(value, exact: true)
        default:
            return .testID(raw)
        }
    }

    private static func pressButton(_ raw: String) throws -> String {
        let normalized = raw
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        switch normalized {
        case "up":
            return "up"
        case "down":
            return "down"
        case "left":
            return "left"
        case "right":
            return "right"
        case "select", "ok", "enter":
            return "select"
        case "menu", "back":
            return "menu"
        case "playpause", "play":
            return "playPause"
        default:
            throw CLIError("Unknown press button: \(raw). Expected up, down, left, right, select, menu, or playPause")
        }
    }
}
