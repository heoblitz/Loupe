import Foundation

public enum LoupeRuntimeTouchActionCommand: String, Codable, Equatable, Sendable {
    case tap
    case drag
    case swipe
}

public struct LoupeRuntimeTouchActionRequest: Codable, Equatable, Sendable {
    public var command: LoupeRuntimeTouchActionCommand
    public var start: LoupePoint
    public var end: LoupePoint?
    public var duration: Double?
    public var holdDuration: Double
    public var screen: LoupeSize

    public init(
        command: LoupeRuntimeTouchActionCommand,
        start: LoupePoint,
        end: LoupePoint? = nil,
        duration: Double? = nil,
        holdDuration: Double = 0,
        screen: LoupeSize
    ) {
        self.command = command
        self.start = start
        self.end = end
        self.duration = duration
        self.holdDuration = holdDuration
        self.screen = screen
    }

    public func validationError() -> String? {
        guard screen.width.isFinite, screen.height.isFinite, screen.width > 0, screen.height > 0 else {
            return "Screen dimensions must be finite and positive."
        }
        for point in [start, end].compactMap({ $0 }) {
            guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
                  point.x < screen.width, point.y < screen.height else {
                return "Touch coordinates must be finite and inside the screen."
            }
        }
        if command != .tap, end == nil { return "Swipe and drag require an end point." }
        if command == .tap, end != nil { return "Tap does not accept an end point." }
        let movement = duration ?? (command == .tap ? 0.05 : 0.6)
        guard movement.isFinite, movement > 0, holdDuration.isFinite, holdDuration >= 0,
              movement + holdDuration <= 10 else {
            return "Touch timing must be finite, positive, and total at most 10 seconds."
        }
        if command == .swipe, holdDuration > 0 { return "Swipe does not accept a hold duration." }
        return nil
    }
}

public struct LoupeRuntimeTouchActionResponse: Codable, Equatable, Sendable {
    public var command: LoupeRuntimeTouchActionCommand
    public var start: LoupePoint
    public var end: LoupePoint?
    public var actionElapsed: Double
    public var beforeSnapshotID: String
    public var afterSnapshotID: String

    public init(
        command: LoupeRuntimeTouchActionCommand,
        start: LoupePoint,
        end: LoupePoint?,
        actionElapsed: Double,
        beforeSnapshotID: String,
        afterSnapshotID: String
    ) {
        self.command = command
        self.start = start
        self.end = end
        self.actionElapsed = actionElapsed
        self.beforeSnapshotID = beforeSnapshotID
        self.afterSnapshotID = afterSnapshotID
    }
}
