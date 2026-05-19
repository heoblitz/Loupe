import Foundation
import LoupeCore

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
