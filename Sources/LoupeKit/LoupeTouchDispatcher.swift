import Foundation
import LoupeCore

#if canImport(UIKit) && os(iOS)
import LoupeSyntheticEvents
import UIKit

/// Holds one UITouch across asynchronous phases so gesture timers can run.
@MainActor
enum LoupeTouchDispatcher {
    private static var inFlight = false

    static func perform(_ request: LoupeRuntimeTouchActionRequest) async throws -> LoupeRuntimeTouchActionResponse {
        if let message = request.validationError() {
            throw LoupeMutationError(code: "invalid_touch_request", message: message)
        }
        guard !inFlight else {
            throw LoupeMutationError(status: 409, code: "touch_in_progress", message: "Another touch is still in progress.")
        }
        try Task.checkCancellation()
        inFlight = true
        defer { inFlight = false }
        let agent = LoupeAgent()
        let before = agent.captureSnapshotWithViewRefs().snapshot
        try Task.checkCancellation()
        var error: NSError?
        guard let session = LoupeSyntheticTouchBegin(
            CGPoint(x: request.start.x, y: request.start.y),
            CGSize(width: request.screen.width, height: request.screen.height), &error
        ) else {
            throw failure(error)
        }
        let startedAt = Date()
        var ended = false
        defer { if !ended { LoupeSyntheticTouchCancel(session) } }
        if request.holdDuration > 0 {
            try await pause(request.holdDuration)
        }
        if request.command == .tap {
            try await pause(request.duration ?? 0.05)
        } else if let end = request.end {
            let duration = request.duration ?? 0.6
            let steps = max(1, Int(ceil(duration * 60)))
            for index in 1...steps {
                try await pause(duration / Double(steps))
                let progress = Double(index) / Double(steps)
                let point = CGPoint(
                    x: request.start.x + (end.x - request.start.x) * progress,
                    y: request.start.y + (end.y - request.start.y) * progress
                )
                guard LoupeSyntheticTouchMove(session, point, &error) else { throw failure(error) }
            }
        }
        try Task.checkCancellation()
        guard LoupeSyntheticTouchEnd(session, &error) else { throw failure(error) }
        ended = true
        let elapsed = Date().timeIntervalSince(startedAt)
        let after = agent.captureSnapshotWithViewRefs().snapshot
        return LoupeRuntimeTouchActionResponse(
            command: request.command, start: request.start, end: request.end,
            actionElapsed: elapsed, beforeSnapshotID: before.id, afterSnapshotID: after.id
        )
    }

    private static func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func failure(_ error: NSError?) -> LoupeMutationError {
        LoupeMutationError(code: "touch_delivery_failed", message: error?.localizedDescription ?? "Touch delivery failed.")
    }
}
#endif
