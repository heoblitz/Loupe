import Foundation
import LoupeCore

package protocol ActionDispatchOptions {
    var backend: String { get }
    var udid: String { get }
    var timeout: TimeInterval { get }
    var endPoint: LoupePoint? { get }
    var duration: Double? { get }
    var text: String? { get }
    var startSpread: Double? { get }
    var endSpread: Double? { get }
    var traceDirectory: URL? { get }
}

package extension ActionDispatchOptions {
    func requireEndPoint(command: String) throws -> LoupePoint {
        guard let endPoint else {
            throw CLIError("\(command) requires --to x,y")
        }
        return endPoint
    }
}

package struct ActionScreen: Equatable {
    package var size: LoupeSize
    package var scale: Double

    package init(size: LoupeSize, scale: Double) {
        self.size = size
        self.scale = scale
    }
}

package enum ActionScreenResolver {
    package static func explicit(_ size: LoupeSize) -> ActionScreen? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        return ActionScreen(size: size, scale: 1)
    }

    package static func resolve(explicit: LoupeSize, fallback: LoupeScreen) -> ActionScreen {
        if let screen = self.explicit(explicit) {
            return screen
        }
        return ActionScreen(size: fallback.size, scale: fallback.scale)
    }
}

package struct ActionOptions: ActionDispatchOptions {
    package var command: String
    package var host: URL
    package var hostWasExplicit: Bool
    package var backend: String
    package var udid: String
    package var timeout: TimeInterval
    package var selector: LoupeSelector?
    package var point: LoupePoint?
    package var endPoint: LoupePoint?
    package var screen: LoupeSize
    package var duration: Double?
    package var text: String?
    package var startSpread: Double?
    package var endSpread: Double?
    package var traceDirectory: URL?
    package var expectVisibleTestID: String?

    package init(command: String, arguments: [String]) throws {
        self.command = command
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        backend = "auto"
        udid = "booted"
        timeout = 8
        screen = LoupeSize(width: 0, height: 0)

        var selector: LoupeSelector?
        var point: LoupePoint?
        var endPoint: LoupePoint?
        var duration: Double?
        var text: String?
        var startSpread: Double?
        var endSpread: Double?
        var traceDirectory: URL?
        var expectVisibleTestID: String?
        var screenWidth: Double?
        var screenHeight: Double?
        var hasX = false
        var hasY = false
        var index = 0

        if command == "type", let first = arguments.first, !first.hasPrefix("--") {
            text = first
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
            case "--test-id":
                selector = .testID(try Self.value(after: argument, in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: argument, in: arguments, index: &index))
            case "--text":
                let value = try Self.value(after: argument, in: arguments, index: &index)
                if command == "type" {
                    text = value
                } else if command == "tap" {
                    throw CLIError("tap expects --test-id, --ref, or coordinates")
                } else {
                    throw CLIError("\(command) expects --test-id, --ref, or coordinates")
                }
            case "--exact-text":
                _ = try Self.value(after: argument, in: arguments, index: &index)
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
                expectVisibleTestID = try Self.value(after: argument, in: arguments, index: &index)
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
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }

        if hasX != hasY {
            throw CLIError("--x and --y must be provided together")
        }

        if command == "tap" {
            if selector != nil, point != nil {
                throw CLIError("tap accepts exactly one target: --test-id, --ref, or --x <n> --y <n>")
            }
            if selector == nil, point == nil {
                throw CLIError("tap requires --test-id, --ref, or --x <n> --y <n>")
            }
        }

        self.selector = selector
        self.point = point
        self.endPoint = endPoint
        self.duration = duration
        self.text = text
        self.startSpread = startSpread
        self.endSpread = endSpread
        self.traceDirectory = traceDirectory
        self.expectVisibleTestID = expectVisibleTestID
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
}

package struct ReplayActionOptions: ActionDispatchOptions {
    package var backend: String
    package var udid: String
    package var timeout: TimeInterval
    package var endPoint: LoupePoint?
    package var duration: Double?
    package var text: String?
    package var startSpread: Double?
    package var endSpread: Double?
    package var traceDirectory: URL?

    package init(
        backend: String,
        udid: String,
        timeout: TimeInterval,
        endPoint: LoupePoint? = nil,
        duration: Double? = nil,
        text: String? = nil,
        startSpread: Double? = nil,
        endSpread: Double? = nil,
        traceDirectory: URL? = nil
    ) {
        self.backend = backend
        self.udid = udid
        self.timeout = timeout
        self.endPoint = endPoint
        self.duration = duration
        self.text = text
        self.startSpread = startSpread
        self.endSpread = endSpread
        self.traceDirectory = traceDirectory
    }
}

package struct ReplayAction {
    package var command: String
    package var target: ActionTarget
    package var endPoint: LoupePoint?
    package var startSpread: Double?
    package var endSpread: Double?
    package var selector: LoupeSelector?

    package init(
        command: String,
        target: ActionTarget,
        endPoint: LoupePoint?,
        startSpread: Double?,
        endSpread: Double?,
        selector: LoupeSelector?
    ) {
        self.command = command
        self.target = target
        self.endPoint = endPoint
        self.startSpread = startSpread
        self.endSpread = endSpread
        self.selector = selector
    }
}

package enum ActionTargetSource: CustomStringConvertible {
    case accessibility(ref: String, sourceRef: String)
    case view(ref: String)
    case coordinates
    case keyboardFocus

    package var description: String {
        switch self {
        case let .accessibility(ref, sourceRef):
            return "accessibility:\(ref):source:\(sourceRef)"
        case let .view(ref):
            return "view:\(ref)"
        case .coordinates:
            return "coordinates"
        case .keyboardFocus:
            return "keyboardFocus"
        }
    }
}

package struct ActionTarget {
    package var point: LoupePoint
    package var screen: LoupeSize
    package var screenScale: Double
    package var source: ActionTargetSource
    package var match: ActionTargetMatch?

    package init(
        point: LoupePoint,
        screen: LoupeSize,
        screenScale: Double,
        source: ActionTargetSource,
        match: ActionTargetMatch? = nil
    ) {
        self.point = point
        self.screen = screen
        self.screenScale = screenScale
        self.source = source
        self.match = match
    }
}

package enum ActionTargetMatch {
    case accessibility(LoupeAccessibilityQueryResult)
    case view(LoupeQueryResult)

    package var trace: ActionTargetTrace {
        switch self {
        case let .accessibility(result):
            return ActionTargetTrace(
                tree: "accessibility",
                ref: result.ref,
                sourceRef: result.sourceRef,
                typeName: nil,
                role: result.role,
                testID: result.testID,
                label: nil,
                value: nil,
                text: result.text,
                frame: result.frame,
                activationPoint: result.activationPoint,
                isVisible: result.isVisible,
                isEnabled: result.isEnabled,
                isInteractive: result.isInteractive
            )
        case let .view(result):
            return ActionTargetTrace(
                tree: "view",
                ref: result.ref,
                sourceRef: nil,
                typeName: nil,
                role: result.role,
                testID: result.testID,
                label: nil,
                value: nil,
                text: result.text,
                frame: result.frame,
                activationPoint: nil,
                isVisible: result.isVisible,
                isEnabled: result.isEnabled,
                isInteractive: result.isInteractive
            )
        }
    }
}

package struct ActionTargetTrace: Codable, Equatable {
    package var tree: String
    package var ref: String
    package var sourceRef: String?
    package var typeName: String?
    package var role: String?
    package var testID: String?
    package var label: String?
    package var value: String?
    package var text: String?
    package var frame: LoupeRect?
    package var activationPoint: LoupePoint?
    package var isVisible: Bool
    package var isEnabled: Bool
    package var isInteractive: Bool

    package init(
        tree: String,
        ref: String,
        sourceRef: String?,
        typeName: String?,
        role: String?,
        testID: String?,
        label: String?,
        value: String?,
        text: String?,
        frame: LoupeRect?,
        activationPoint: LoupePoint?,
        isVisible: Bool,
        isEnabled: Bool,
        isInteractive: Bool
    ) {
        self.tree = tree
        self.ref = ref
        self.sourceRef = sourceRef
        self.typeName = typeName
        self.role = role
        self.testID = testID
        self.label = label
        self.value = value
        self.text = text
        self.frame = frame
        self.activationPoint = activationPoint
        self.isVisible = isVisible
        self.isEnabled = isEnabled
        self.isInteractive = isInteractive
    }
}

package struct LoupeCLIActionTrace: Codable, Equatable {
    package var command: String
    package var phase: String
    package var host: String
    package var backend: String
    package var udid: String
    package var selector: String?
    package var point: LoupePoint?
    package var endPoint: LoupePoint?
    package var duration: Double?
    package var text: String?
    package var resolvedPoint: LoupePoint?
    package var resolvedScreen: LoupeSize?
    package var resolvedSource: String?
    package var resolvedTarget: ActionTargetTrace?
    package var recordedAt: Date

    package init(
        command: String,
        phase: String,
        host: String,
        backend: String,
        udid: String,
        selector: String?,
        point: LoupePoint?,
        endPoint: LoupePoint?,
        duration: Double?,
        text: String?,
        resolvedPoint: LoupePoint?,
        resolvedScreen: LoupeSize?,
        resolvedSource: String?,
        resolvedTarget: ActionTargetTrace?,
        recordedAt: Date
    ) {
        self.command = command
        self.phase = phase
        self.host = host
        self.backend = backend
        self.udid = udid
        self.selector = selector
        self.point = point
        self.endPoint = endPoint
        self.duration = duration
        self.text = text
        self.resolvedPoint = resolvedPoint
        self.resolvedScreen = resolvedScreen
        self.resolvedSource = resolvedSource
        self.resolvedTarget = resolvedTarget
        self.recordedAt = recordedAt
    }
}

package struct LoupeCLIActionErrorTrace: Codable, Equatable {
    package var message: String
    package var recordedAt: Date

    package init(message: String, recordedAt: Date) {
        self.message = message
        self.recordedAt = recordedAt
    }
}

package struct CLIError: Error, CustomStringConvertible, Equatable {
    package var description: String

    package init(_ description: String) {
        self.description = description
    }
}
