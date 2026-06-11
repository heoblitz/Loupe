import Foundation

public enum LoupeRuntimeTouchActionCommand: String, Codable, Equatable {
    case tap
    case drag
    case swipe
}

public struct LoupeRuntimeTouchActionRequest: Codable, Equatable {
    public var command: LoupeRuntimeTouchActionCommand
    public var start: LoupePoint
    public var end: LoupePoint?
    public var duration: Double?

    public init(
        command: LoupeRuntimeTouchActionCommand,
        start: LoupePoint,
        end: LoupePoint? = nil,
        duration: Double? = nil
    ) {
        self.command = command
        self.start = start
        self.end = end
        self.duration = duration
    }
}

public struct LoupeRuntimeTouchActionResponse: Codable, Equatable {
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
