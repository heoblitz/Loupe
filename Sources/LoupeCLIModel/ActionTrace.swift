import Foundation
import LoupeCore

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
