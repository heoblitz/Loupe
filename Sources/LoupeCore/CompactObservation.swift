import Foundation

public struct LoupeVisibleText: Codable, Equatable {
    public var ref: String
    public var typeName: String
    public var className: String?
    public var role: String?
    public var testID: String?
    public var text: String
    public var frame: LoupeRect?

    public init(
        ref: String,
        typeName: String,
        className: String?,
        role: String?,
        testID: String?,
        text: String,
        frame: LoupeRect?
    ) {
        self.ref = ref
        self.typeName = typeName
        self.className = className
        self.role = role
        self.testID = testID
        self.text = text
        self.frame = frame
    }
}

public struct LoupeInteractiveElement: Codable, Equatable {
    public var ref: String
    public var typeName: String
    public var className: String?
    public var role: String?
    public var text: String?
    public var testID: String?
    public var frame: LoupeRect?
    public var enabled: Bool

    public init(
        ref: String,
        typeName: String,
        className: String?,
        role: String?,
        text: String?,
        testID: String?,
        frame: LoupeRect?,
        enabled: Bool
    ) {
        self.ref = ref
        self.typeName = typeName
        self.className = className
        self.role = role
        self.text = text
        self.testID = testID
        self.frame = frame
        self.enabled = enabled
    }
}

public struct LoupeCompactObservation: Codable, Equatable {
    public var snapshotID: String
    public var screen: LoupeScreen
    public var visibleTexts: [LoupeVisibleText]
    public var interactive: [LoupeInteractiveElement]

    public init(
        snapshotID: String,
        screen: LoupeScreen,
        visibleTexts: [LoupeVisibleText],
        interactive: [LoupeInteractiveElement]
    ) {
        self.snapshotID = snapshotID
        self.screen = screen
        self.visibleTexts = visibleTexts
        self.interactive = interactive
    }
}

public struct LoupeObservationOptions: Equatable {
    public var maxVisibleTexts: Int
    public var maxInteractiveElements: Int

    public init(maxVisibleTexts: Int = 50, maxInteractiveElements: Int = 30) {
        self.maxVisibleTexts = maxVisibleTexts
        self.maxInteractiveElements = maxInteractiveElements
    }
}

public enum LoupeObservationCompactor {
    public static func compact(
        _ snapshot: LoupeSnapshot,
        options: LoupeObservationOptions = LoupeObservationOptions()
    ) -> LoupeCompactObservation {
        let screenRect = LoupeRect(
            x: 0,
            y: 0,
            width: snapshot.screen.size.width,
            height: snapshot.screen.size.height
        )

        let visibleNodes = snapshot.nodes.values
            .filter { node in
                guard node.isVisible, let frame = node.frame else { return false }
                return frame.intersects(screenRect)
            }
            .sorted(by: visualOrder)

        let visibleTexts = visibleNodes
            .compactMap { node -> LoupeVisibleText? in
                guard let text = displayText(for: node), !text.isEmpty else { return nil }
                return LoupeVisibleText(
                    ref: node.ref,
                    typeName: node.typeName,
                    className: node.uiKit?.className,
                    role: node.role,
                    testID: node.testID,
                    text: text,
                    frame: node.frame
                )
            }
            .prefix(options.maxVisibleTexts)

        let interactive = visibleNodes
            .filter(\.isInteractive)
            .sorted(by: interactiveOrder)
            .map { node in
                LoupeInteractiveElement(
                    ref: node.ref,
                    typeName: node.typeName,
                    className: node.uiKit?.className,
                    role: node.role,
                    text: displayText(for: node),
                    testID: node.testID,
                    frame: node.frame,
                    enabled: node.isEnabled
                )
            }
            .prefix(options.maxInteractiveElements)

        return LoupeCompactObservation(
            snapshotID: snapshot.id,
            screen: snapshot.screen,
            visibleTexts: Array(visibleTexts),
            interactive: Array(interactive)
        )
    }

    public static func displayText(for node: LoupeNode) -> String? {
        [node.text, node.label, node.value, node.placeholder]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func visualOrder(_ lhs: LoupeNode, _ rhs: LoupeNode) -> Bool {
        guard let lhsFrame = lhs.frame else { return false }
        guard let rhsFrame = rhs.frame else { return true }

        if abs(lhsFrame.y - rhsFrame.y) > 1 {
            return lhsFrame.y < rhsFrame.y
        }

        return lhsFrame.x < rhsFrame.x
    }

    private static func interactiveOrder(_ lhs: LoupeNode, _ rhs: LoupeNode) -> Bool {
        if (lhs.testID != nil) != (rhs.testID != nil) {
            return lhs.testID != nil
        }

        if (lhs.role != nil) != (rhs.role != nil) {
            return lhs.role != nil
        }

        return visualOrder(lhs, rhs)
    }
}
