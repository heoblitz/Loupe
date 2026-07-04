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

public struct LoupeVisualSurface: Codable, Equatable {
    public var ref: String
    public var typeName: String
    public var className: String?
    public var frameworkBundleIdentifier: String?
    public var testID: String?
    public var frame: LoupeRect?
    public var note: String

    public init(
        ref: String,
        typeName: String,
        className: String?,
        frameworkBundleIdentifier: String?,
        testID: String?,
        frame: LoupeRect?,
        note: String
    ) {
        self.ref = ref
        self.typeName = typeName
        self.className = className
        self.frameworkBundleIdentifier = frameworkBundleIdentifier
        self.testID = testID
        self.frame = frame
        self.note = note
    }
}

public struct LoupeCompactObservation: Codable, Equatable {
    public var snapshotID: String
    public var screen: LoupeScreen
    public var visibleTexts: [LoupeVisibleText]
    public var interactive: [LoupeInteractiveElement]
    public var visualSurfaces: [LoupeVisualSurface]

    public init(
        snapshotID: String,
        screen: LoupeScreen,
        visibleTexts: [LoupeVisibleText],
        interactive: [LoupeInteractiveElement],
        visualSurfaces: [LoupeVisualSurface] = []
    ) {
        self.snapshotID = snapshotID
        self.screen = screen
        self.visibleTexts = visibleTexts
        self.interactive = interactive
        self.visualSurfaces = visualSurfaces
    }

    enum CodingKeys: String, CodingKey {
        case snapshotID
        case screen
        case visibleTexts
        case interactive
        case visualSurfaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        snapshotID = try container.decode(String.self, forKey: .snapshotID)
        screen = try container.decode(LoupeScreen.self, forKey: .screen)
        visibleTexts = try container.decode([LoupeVisibleText].self, forKey: .visibleTexts)
        interactive = try container.decode([LoupeInteractiveElement].self, forKey: .interactive)
        visualSurfaces = try container.decodeIfPresent([LoupeVisualSurface].self, forKey: .visualSurfaces) ?? []
    }
}

public struct LoupeObservationOptions: Equatable {
    public var maxVisibleTexts: Int
    public var maxInteractiveElements: Int
    public var maxVisualSurfaces: Int

    public init(maxVisibleTexts: Int = 50, maxInteractiveElements: Int = 30, maxVisualSurfaces: Int = 10) {
        self.maxVisibleTexts = maxVisibleTexts
        self.maxInteractiveElements = maxInteractiveElements
        self.maxVisualSurfaces = maxVisualSurfaces
    }
}

public enum LoupeObservationCompactor {
    public static func compact(
        _ snapshot: LoupeSnapshot,
        options: LoupeObservationOptions = LoupeObservationOptions()
    ) -> LoupeCompactObservation {
        compact(LoupeSnapshotContext(snapshot: snapshot), options: options)
    }

    public static func compact(
        _ context: LoupeSnapshotContext,
        options: LoupeObservationOptions = LoupeObservationOptions()
    ) -> LoupeCompactObservation {
        let snapshot = context.snapshot
        let screenRect = context.screenRect
        let hasKnownScreenSize = context.hasKnownScreenSize
        let surfaceVisibleRefs = context.surfaceVisibleRefs

        let visibleNodes = snapshot.nodes.values
            .filter { node in
                guard surfaceVisibleRefs.contains(node.ref), let frame = node.frame else { return false }
                return !hasKnownScreenSize || frame.intersects(screenRect)
            }
            .sorted(by: visualOrder)

        let visibleTexts = visibleNodes
            .compactMap { node -> (node: LoupeNode, text: LoupeVisibleText)? in
                guard let text = context.displayText(for: node), !text.isEmpty else { return nil }
                if suppressesSystemChromeSemanticDuplicateText(node, text: text, in: snapshot, screenRect: screenRect) {
                    return nil
                }
                if suppressesRolelessAppleSystemAggregateText(node, in: snapshot, screenRect: screenRect) {
                    return nil
                }
                if hasVisibleTextDescendant(node, in: snapshot, screenRect: screenRect),
                   !preservesAggregateTextTarget(node) {
                    return nil
                }
                return (node, LoupeVisibleText(
                    ref: node.ref,
                    typeName: node.typeName,
                    className: node.platform?.className,
                    role: node.role,
                    testID: node.testID,
                    text: text,
                    frame: node.frame
                ))
            }
            .sorted { lhs, rhs in
                visibleTextOrder(lhs.node, rhs.node, screenRect: screenRect)
            }
            .map(\.text)
            .prefix(options.maxVisibleTexts)

        let interactive = visibleNodes
            .filter { node in
                node.isInteractive
                    && !isRootContextNode(node)
                    && !isRolelessAppleSystemChromeAggregate(node, in: snapshot)
                    && !isRolelessAppleSystemAggregateContainer(node, screenRect: screenRect)
                    && !isRolelessAppleSystemBackdrop(node, screenRect: screenRect)
                    && !isSystemOwnedCellAccessory(node, in: snapshot)
            }
            .sorted { lhs, rhs in
                interactiveOrder(lhs, rhs, screenRect: screenRect)
            }
            .map { node in
                LoupeInteractiveElement(
                    ref: node.ref,
                    typeName: node.typeName,
                    className: node.platform?.className,
                    role: node.role,
                    text: interactiveDisplayText(for: node, screenRect: screenRect),
                    testID: node.testID,
                    frame: node.frame,
                    enabled: node.isEnabled
                )
            }
            .prefix(options.maxInteractiveElements)

        let visualSurfaces = visibleNodes
            .compactMap { node -> (node: LoupeNode, note: String)? in
                guard let note = visualSurfaceNote(for: node, in: snapshot, screenRect: screenRect) else {
                    return nil
                }
                return (node, note)
            }
            .sorted(by: visualSurfaceOrder)
            .map { node, note in
                LoupeVisualSurface(
                    ref: node.ref,
                    typeName: node.typeName,
                    className: node.platform?.className,
                    frameworkBundleIdentifier: node.runtime?.frameworkBundleIdentifier,
                    testID: node.testID,
                    frame: node.frame,
                    note: note
                )
            }
            .prefix(options.maxVisualSurfaces)

        return LoupeCompactObservation(
            snapshotID: snapshot.id,
            screen: snapshot.screen,
            visibleTexts: Array(visibleTexts),
            interactive: Array(interactive),
            visualSurfaces: Array(visualSurfaces)
        )
    }

    public static func displayText(for node: LoupeNode) -> String? {
        [node.text, node.renderedText, node.semanticText, node.label, node.value, node.placeholder]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func interactiveDisplayText(for node: LoupeNode, screenRect: LoupeRect) -> String? {
        guard let text = displayText(for: node) else {
            return nil
        }
        if suppressesInteractiveAggregateText(node, screenRect: screenRect) {
            return nil
        }
        return text
    }

    private static func visualOrder(_ lhs: LoupeNode, _ rhs: LoupeNode) -> Bool {
        guard let lhsFrame = lhs.frame else { return false }
        guard let rhsFrame = rhs.frame else { return true }

        if abs(lhsFrame.y - rhsFrame.y) > 1 {
            return lhsFrame.y < rhsFrame.y
        }

        return lhsFrame.x < rhsFrame.x
    }

    private static func interactiveOrder(
        _ lhs: LoupeNode,
        _ rhs: LoupeNode,
        screenRect: LoupeRect
    ) -> Bool {
        let lhsPriority = interactivePriority(lhs, screenRect: screenRect)
        let rhsPriority = interactivePriority(rhs, screenRect: screenRect)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }

        return visualOrder(lhs, rhs)
    }

    private static func interactivePriority(_ node: LoupeNode, screenRect: LoupeRect) -> Int {
        if node.testID != nil {
            return 0
        }

        let text = displayText(for: node)
        let hasSpecificText = text != nil && !isLikelyAggregateTextNode(node, screenRect: screenRect)
        switch node.role?.lowercased() {
        case "textfield", "textview", "searchfield", "switch", "slider", "segmentedcontrol", "pagecontrol":
            return 1
        case "button", "link", "cell":
            return hasSpecificText ? 1 : 3
        case "collectionview", "tableview", "scrollview", "window", "navigationbar":
            return 5
        default:
            break
        }

        if hasSpecificText {
            return 2
        }

        if isLikelyAggregateTextNode(node, screenRect: screenRect) {
            return 6
        }

        return 4
    }

    private static func visualSurfaceOrder(
        _ lhs: (node: LoupeNode, note: String),
        _ rhs: (node: LoupeNode, note: String)
    ) -> Bool {
        visualSurfaceNodeOrder(lhs.node, rhs.node)
    }

    private static func visualSurfaceNodeOrder(_ lhs: LoupeNode, _ rhs: LoupeNode) -> Bool {
        let lhsArea = lhs.frame.map(area) ?? 0
        let rhsArea = rhs.frame.map(area) ?? 0
        if abs(lhsArea - rhsArea) > 1 {
            return lhsArea > rhsArea
        }
        return visualOrder(lhs, rhs)
    }

    private static func visualSurfaceNote(
        for node: LoupeNode,
        in snapshot: LoupeSnapshot,
        screenRect: LoupeRect
    ) -> String? {
        guard isLargeVisibleTextlessView(node, screenRect: screenRect) else {
            return nil
        }

        if isWebContentSurface(node) {
            return "WebKit content surface; DOM-rendered content may not appear in UIKit tree evidence"
        }

        if isSwiftUIHostingSurface(node), !hasVisibleTextDescendant(node, in: snapshot, screenRect: screenRect) {
            return "SwiftUI hosting surface; rendered content may not appear in UIKit tree evidence"
        }

        guard !hasVisibleChildren(node, in: snapshot, screenRect: screenRect) else {
            return nil
        }
        guard isCustomRuntimeView(node) else {
            return nil
        }
        return "large custom leaf view; drawn pixels may not appear in text/tree evidence"
    }

    private static func isLargeVisibleTextlessView(
        _ node: LoupeNode,
        screenRect: LoupeRect
    ) -> Bool {
        guard node.kind == .view, let frame = node.frame, node.isVisible else {
            return false
        }
        guard displayText(for: node) == nil else {
            return false
        }

        let visibleArea = frame.intersectionArea(with: screenRect)
        let screenArea = area(screenRect)
        guard screenArea > 0 else {
            return false
        }
        return visibleArea / screenArea >= 0.08
    }

    private static func hasVisibleTextDescendant(
        _ node: LoupeNode,
        in snapshot: LoupeSnapshot,
        screenRect: LoupeRect
    ) -> Bool {
        node.children.contains { ref in
            guard let child = snapshot.nodes[ref], child.isVisible, let frame = child.frame else {
                return false
            }
            guard frame.intersects(screenRect) else {
                return false
            }
            if displayText(for: child) != nil {
                return true
            }
            return hasVisibleTextDescendant(child, in: snapshot, screenRect: screenRect)
        }
    }

    private static func hasVisibleChildren(
        _ node: LoupeNode,
        in snapshot: LoupeSnapshot,
        screenRect: LoupeRect
    ) -> Bool {
        node.children.contains { ref in
            guard let child = snapshot.nodes[ref], child.isVisible, let frame = child.frame else {
                return false
            }
            return frame.intersects(screenRect)
        }
    }

    private static func isCustomRuntimeView(_ node: LoupeNode) -> Bool {
        guard let framework = node.runtime?.frameworkBundleIdentifier else {
            return false
        }
        return !framework.hasPrefix("com.apple.")
    }

    private static func visibleTextOrder(
        _ lhs: LoupeNode,
        _ rhs: LoupeNode,
        screenRect: LoupeRect
    ) -> Bool {
        let lhsAggregateRank = aggregateTextRank(lhs, screenRect: screenRect)
        let rhsAggregateRank = aggregateTextRank(rhs, screenRect: screenRect)
        if lhsAggregateRank != rhsAggregateRank {
            return lhsAggregateRank < rhsAggregateRank
        }

        return visualOrder(lhs, rhs)
    }

    private static func aggregateTextRank(_ node: LoupeNode, screenRect: LoupeRect) -> Int {
        isLikelyAggregateTextNode(node, screenRect: screenRect) ? 1 : 0
    }

    private static func isLikelyAggregateTextNode(_ node: LoupeNode, screenRect: LoupeRect) -> Bool {
        guard node.testID == nil, node.role == nil, !node.children.isEmpty else {
            return false
        }

        guard let frame = node.frame else {
            return false
        }
        let screenArea = area(screenRect)
        guard screenArea > 0 else {
            return false
        }
        return area(frame) / screenArea >= 0.5
    }

    private static func preservesAggregateTextTarget(_ node: LoupeNode) -> Bool {
        node.testID != nil && node.role != nil
    }

    private static func suppressesInteractiveAggregateText(_ node: LoupeNode, screenRect: LoupeRect) -> Bool {
        switch node.role?.lowercased() {
        case "collectionview", "tableview", "scrollview", "window", "navigationbar":
            return true
        default:
            break
        }

        return isLikelyAggregateTextNode(node, screenRect: screenRect)
    }

    private static func isWebContentSurface(_ node: LoupeNode) -> Bool {
        node.role == "webView"
            || node.platform?.webView != nil
            || node.runtime?.frameworkBundleIdentifier == "com.apple.WebKit"
    }

    private static func isSwiftUIHostingSurface(_ node: LoupeNode) -> Bool {
        node.swiftui?.origin == "host"
            || node.runtime?.frameworkBundleIdentifier == "com.apple.SwiftUI"
    }

    private static func suppressesSystemChromeSemanticDuplicateText(
        _ node: LoupeNode,
        text: String,
        in snapshot: LoupeSnapshot,
        screenRect: LoupeRect
    ) -> Bool {
        guard isRolelessAppleSystemChromeAggregate(node, in: snapshot),
              isSemanticOnlyDisplayText(node) else {
            return false
        }
        return hasSpecificVisibleTextMatch(text, excluding: node.ref, in: snapshot, screenRect: screenRect)
    }

    private static func suppressesRolelessAppleSystemAggregateText(
        _ node: LoupeNode,
        in snapshot: LoupeSnapshot,
        screenRect: LoupeRect
    ) -> Bool {
        guard isRolelessAppleSystemAggregateCandidate(node),
              isSemanticOnlyDisplayText(node),
              isLargeScreenOverlay(node, screenRect: screenRect) else {
            return false
        }
        return !hasVisibleTextDescendant(node, in: snapshot, screenRect: screenRect)
    }

    private static func isRolelessAppleSystemChromeAggregate(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard isRolelessAppleSystemAggregateCandidate(node) else {
            return false
        }
        return isSystemChromeDescendant(node, in: snapshot)
    }

    private static func isRolelessAppleSystemBackdrop(_ node: LoupeNode, screenRect: LoupeRect) -> Bool {
        guard isRolelessAppleSystemAggregateCandidate(node),
              !isPublicInteractiveControl(node),
              displayText(for: node) == nil else {
            return false
        }
        return isLargeScreenOverlay(node, screenRect: screenRect)
    }

    private static func isRolelessAppleSystemAggregateContainer(_ node: LoupeNode, screenRect: LoupeRect) -> Bool {
        guard isRolelessAppleSystemAggregateCandidate(node),
              !isPublicInteractiveControl(node),
              !node.children.isEmpty else {
            return false
        }
        return isLargeScreenOverlay(node, screenRect: screenRect)
    }

    private static func isRolelessAppleSystemAggregateCandidate(_ node: LoupeNode) -> Bool {
        node.runtime?.frameworkBundleIdentifier?.hasPrefix("com.apple.") == true
            && node.testID == nil
            && node.role == nil
            && node.accessibility?.isElement != true
    }

    private static func isRootContextNode(_ node: LoupeNode) -> Bool {
        node.kind == .application || node.kind == .scene || node.kind == .window
    }

    private static func isPublicInteractiveControl(_ node: LoupeNode) -> Bool {
        if node.platform?.button != nil
            || node.platform?.switchControl != nil
            || node.platform?.slider != nil
            || node.platform?.stepper != nil
            || node.platform?.segmentedControl != nil
            || node.platform?.textField != nil
            || node.platform?.textView != nil {
            return true
        }
        return node.role == "cell"
    }

    private static func isSystemOwnedCellAccessory(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard node.runtime?.frameworkBundleIdentifier?.hasPrefix("com.apple.") == true,
              node.testID == nil,
              node.role == "button",
              node.accessibility?.isElement != true,
              displayText(for: node) == nil,
              node.platform?.userInteractionEnabled == false,
              hasAncestorRole("cell", node, in: snapshot),
              hasImageDescendant(node, in: snapshot) else {
            return false
        }
        return true
    }

    private static func hasAncestorRole(_ role: String, _ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        var parentRef = node.parentRef
        while let ref = parentRef, let parent = snapshot.nodes[ref] {
            if parent.role == role {
                return true
            }
            parentRef = parent.parentRef
        }
        return false
    }

    private static func hasImageDescendant(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        node.children.contains { ref in
            guard let child = snapshot.nodes[ref] else {
                return false
            }
            if (child.role == "image" || child.platform?.imageView != nil), displayText(for: child) == nil {
                return true
            }
            return hasImageDescendant(child, in: snapshot)
        }
    }

    private static func isLargeScreenOverlay(_ node: LoupeNode, screenRect: LoupeRect) -> Bool {
        guard let frame = node.frame else {
            return false
        }
        let screenArea = area(screenRect)
        guard screenArea > 0 else {
            return false
        }
        return frame.intersectionArea(with: screenRect) / screenArea >= 0.5
    }

    private static func isSystemChromeDescendant(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        if isSystemChromeRole(node.role) {
            return true
        }
        var currentRef = node.parentRef
        while let ref = currentRef, let current = snapshot.nodes[ref] {
            if isSystemChromeRole(current.role) {
                return true
            }
            currentRef = current.parentRef
        }
        return false
    }

    private static func isSystemChromeRole(_ role: String?) -> Bool {
        role == "navigationBar" || role == "tabBar" || role == "toolbar"
    }

    private static func isSemanticOnlyDisplayText(_ node: LoupeNode) -> Bool {
        nonEmpty(node.semanticText) != nil
            && nonEmpty(node.text) == nil
            && nonEmpty(node.renderedText) == nil
            && nonEmpty(node.label) == nil
            && nonEmpty(node.value) == nil
            && nonEmpty(node.placeholder) == nil
    }

    private static func hasSpecificVisibleTextMatch(
        _ text: String,
        excluding ref: String,
        in snapshot: LoupeSnapshot,
        screenRect: LoupeRect
    ) -> Bool {
        snapshot.nodes.values.contains { candidate in
            guard candidate.ref != ref,
                  candidate.isVisible,
                  let frame = candidate.frame,
                  frame.intersects(screenRect),
                  displayText(for: candidate) == text else {
                return false
            }
            return isSpecificTextNode(candidate)
        }
    }

    private static func isSpecificTextNode(_ node: LoupeNode) -> Bool {
        node.testID != nil
            || node.role != nil
            || node.accessibility?.isElement == true
            || !isSemanticOnlyDisplayText(node)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func area(_ rect: LoupeRect) -> Double {
        max(0, rect.width) * max(0, rect.height)
    }
}
