import LoupeCore

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
