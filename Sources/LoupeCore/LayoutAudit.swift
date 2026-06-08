import Foundation

public enum LoupeLayoutIssueKind: String, Codable, Equatable, CaseIterable {
    case overlappingSiblings
    case childOutsideParent
    case duplicateTestID
    case missingTestID
    case smallInteractiveTarget
    case lowTextContrast
}

public struct LoupeLayoutIssue: Codable, Equatable {
    public var kind: LoupeLayoutIssueKind
    public var ref: String
    public var otherRef: String?
    public var testID: String?
    public var otherTestID: String?
    public var frame: LoupeRect?
    public var otherFrame: LoupeRect?
    public var overlapArea: Double?
    public var measuredValue: Double?
    public var expectedValue: Double?
    public var message: String

    public init(
        kind: LoupeLayoutIssueKind,
        ref: String,
        otherRef: String? = nil,
        testID: String? = nil,
        otherTestID: String? = nil,
        frame: LoupeRect? = nil,
        otherFrame: LoupeRect? = nil,
        overlapArea: Double? = nil,
        measuredValue: Double? = nil,
        expectedValue: Double? = nil,
        message: String
    ) {
        self.kind = kind
        self.ref = ref
        self.otherRef = otherRef
        self.testID = testID
        self.otherTestID = otherTestID
        self.frame = frame
        self.otherFrame = otherFrame
        self.overlapArea = overlapArea
        self.measuredValue = measuredValue
        self.expectedValue = expectedValue
        self.message = message
    }
}

public struct LoupeLayoutAuditOptions: Equatable {
    public var tolerance: Double
    public var minOverlapArea: Double
    public var minOverlapRatio: Double
    public var minContainmentOverflowRatio: Double
    public var minTouchTarget: Double
    public var minContrastRatio: Double

    public init(
        tolerance: Double = 1,
        minOverlapArea: Double = 16,
        minOverlapRatio: Double = 0.2,
        minContainmentOverflowRatio: Double = 0.1,
        minTouchTarget: Double = 44,
        minContrastRatio: Double = 4.5
    ) {
        self.tolerance = tolerance
        self.minOverlapArea = minOverlapArea
        self.minOverlapRatio = minOverlapRatio
        self.minContainmentOverflowRatio = minContainmentOverflowRatio
        self.minTouchTarget = minTouchTarget
        self.minContrastRatio = minContrastRatio
    }
}

public struct LoupeLayoutAudit: Codable, Equatable {
    public var snapshotID: String
    public var issueCount: Int
    public var issues: [LoupeLayoutIssue]

    public init(snapshotID: String, issues: [LoupeLayoutIssue]) {
        self.snapshotID = snapshotID
        self.issueCount = issues.count
        self.issues = issues
    }
}

public enum LoupeLayoutAuditor {
    public static func audit(
        _ snapshot: LoupeSnapshot,
        options: LoupeLayoutAuditOptions = LoupeLayoutAuditOptions()
    ) -> LoupeLayoutAudit {
        var issues: [LoupeLayoutIssue] = []
        let screenFrame = LoupeRect(
            x: 0,
            y: 0,
            width: snapshot.screen.size.width,
            height: snapshot.screen.size.height
        )
        let activeModalOverlayRefs = activeModalOverlayRefs(in: snapshot, screenFrame: screenFrame)
        issues.append(contentsOf: duplicateTestIDIssues(in: snapshot, screenFrame: screenFrame))
        issues.append(contentsOf: interactiveIssues(
            in: snapshot,
            screenFrame: screenFrame,
            activeModalOverlayRefs: activeModalOverlayRefs,
            options: options
        ))
        issues.append(contentsOf: contrastIssues(
            in: snapshot,
            screenFrame: screenFrame,
            activeModalOverlayRefs: activeModalOverlayRefs,
            options: options
        ))

        for parent in snapshot.nodes.values {
            let visibleChildren = parent.children
                .compactMap { snapshot.nodes[$0] }
                .filter { $0.isVisible && $0.frame != nil && intersectsScreen($0, screenFrame: screenFrame) }

            if let parentFrame = parent.frame {
                for child in visibleChildren {
                    guard let childFrame = child.frame else { continue }
                    guard shouldAuditContainment(parent: parent, child: child, screenFrame: screenFrame) else { continue }
                    guard
                        let clippedParentFrame = clipped(parentFrame, to: screenFrame),
                        let clippedChildFrame = clipped(childFrame, to: screenFrame)
                    else {
                        continue
                    }
                    if containmentOverflowRatio(parent: clippedParentFrame, child: clippedChildFrame, tolerance: options.tolerance)
                        > options.minContainmentOverflowRatio {
                        issues.append(
                            LoupeLayoutIssue(
                                kind: .childOutsideParent,
                                ref: child.ref,
                                otherRef: parent.ref,
                                testID: child.testID,
                                otherTestID: parent.testID,
                                frame: childFrame,
                                otherFrame: parentFrame,
                                message: "\(displayName(child)) is outside parent \(displayName(parent))"
                            )
                        )
                    }
                }
            }

            for index in visibleChildren.indices {
                for otherIndex in visibleChildren.indices.dropFirst(index + 1) {
                    let first = visibleChildren[index]
                    let second = visibleChildren[otherIndex]
                    guard let firstFrame = first.frame, let secondFrame = second.frame else { continue }
                    guard shouldAuditSiblingOverlap(
                        first,
                        second,
                        parent: parent,
                        snapshot: snapshot,
                        screenFrame: screenFrame
                    ) else { continue }
                    guard
                        let clippedFirstFrame = clipped(firstFrame, to: screenFrame),
                        let clippedSecondFrame = clipped(secondFrame, to: screenFrame)
                    else {
                        continue
                    }

                    let overlapArea = clippedFirstFrame.intersectionArea(with: clippedSecondFrame)
                    if overlapArea >= options.minOverlapArea,
                       overlapRatio(clippedFirstFrame, clippedSecondFrame, overlapArea: overlapArea) >= options.minOverlapRatio {
                        issues.append(
                            LoupeLayoutIssue(
                                kind: .overlappingSiblings,
                                ref: first.ref,
                                otherRef: second.ref,
                                testID: first.testID,
                                otherTestID: second.testID,
                                frame: firstFrame,
                                otherFrame: secondFrame,
                                overlapArea: overlapArea,
                                message: "\(displayName(first)) overlaps sibling \(displayName(second))"
                            )
                        )
                    }
                }
            }
        }

        return LoupeLayoutAudit(snapshotID: snapshot.id, issues: issues)
    }

    private static func duplicateTestIDIssues(in snapshot: LoupeSnapshot, screenFrame: LoupeRect) -> [LoupeLayoutIssue] {
        let groups = Dictionary(grouping: snapshot.nodes.values.compactMap { node -> (String, LoupeNode)? in
            guard let testID = node.testID, !testID.isEmpty else { return nil }
            guard node.isVisible, intersectsScreen(node, screenFrame: screenFrame) else { return nil }
            guard shouldAuditDuplicateTestID(node) else { return nil }
            return (testID, node)
        }, by: { $0.0 })

        return groups.values.flatMap { entries -> [LoupeLayoutIssue] in
            let nodes = entries.map(\.1)
            guard nodes.count > 1 else { return [] }
            guard hasAmbiguousDuplicateTargets(nodes) else { return [] }
            return nodes.map { node in
                LoupeLayoutIssue(
                    kind: .duplicateTestID,
                    ref: node.ref,
                    testID: node.testID,
                    frame: node.frame,
                    message: "\(displayName(node)) shares a duplicate testID"
                )
            }
        }
    }

    private static func shouldAuditDuplicateTestID(_ node: LoupeNode) -> Bool {
        if isSystemGeneratedTestID(node.testID) {
            return false
        }
        if node.isInteractive { return true }
        if node.accessibility?.isElement == true { return true }
        if isImageNode(node) {
            return false
        }
        return true
    }

    private static func shouldAuditSiblingOverlap(
        _ first: LoupeNode,
        _ second: LoupeNode,
        parent: LoupeNode,
        snapshot: LoupeSnapshot,
        screenFrame: LoupeRect
    ) -> Bool {
        guard !isDecorativeImageNode(first), !isDecorativeImageNode(second) else {
            return false
        }
        if isLoupeProbe(first), isLoupeProbe(second) {
            return false
        }
        if isSystemTabBarItem(first, in: snapshot), isSystemTabBarItem(second, in: snapshot) {
            return false
        }
        if isPassiveStyledSurface(first) {
            return false
        }
        if isPassiveStyledSurface(second) {
            return isOverlapAuditCandidate(first)
        }
        return isOverlapAuditCandidate(first) && isOverlapAuditCandidate(second)
    }

    private static func shouldAuditContainment(parent: LoupeNode, child: LoupeNode, screenFrame: LoupeRect) -> Bool {
        if isPassiveStyledSurface(child) {
            return false
        }
        if isSystemOwnedImplementationDetail(child) {
            return false
        }
        if isSystemChromeContainmentNode(parent) || isSystemChromeContainmentNode(child) {
            return false
        }
        if isSystemOwnedAggregateContainer(parent, screenFrame: screenFrame)
            || isSystemOwnedAggregateContainer(child, screenFrame: screenFrame) {
            return false
        }
        if parent.role == "cell", isHorizontallyPartiallyOffscreen(parent, screenFrame: screenFrame) {
            return false
        }
        if isScrollContainer(parent) {
            return false
        }
        return true
    }

    private static func isOverlapAuditCandidate(_ node: LoupeNode) -> Bool {
        if node.isInteractive { return true }
        if node.accessibility?.isElement == true { return true }
        if LoupeObservationCompactor.displayText(for: node) != nil { return true }
        if node.testID != nil { return true }
        return false
    }

    private static func isPassiveStyledSurface(_ node: LoupeNode) -> Bool {
        guard !node.isInteractive,
              visualContentText(for: node) == nil,
              let style = node.style else {
            return false
        }
        guard isPassiveSurfaceRole(node.role) else {
            return false
        }
        return hasVisibleSurfaceStyle(style)
    }

    private static func visualContentText(for node: LoupeNode) -> String? {
        [node.text, node.renderedText, node.value, node.placeholder]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func isPassiveSurfaceRole(_ role: String?) -> Bool {
        guard let role = role?.trimmingCharacters(in: .whitespacesAndNewlines),
              !role.isEmpty else {
            return true
        }
        switch role.lowercased() {
        case "unknown", "none":
            return true
        default:
            return false
        }
    }

    private static func hasVisibleSurfaceStyle(_ style: LoupeStyle) -> Bool {
        if let color = style.backgroundColor, color.alpha > 0 {
            return true
        }
        if let borderWidth = style.borderWidth, borderWidth > 0,
           let borderColor = style.borderColor, borderColor.alpha > 0 {
            return true
        }
        if let shadowOpacity = style.shadowOpacity, shadowOpacity > 0,
           let shadowColor = style.shadowColor, shadowColor.alpha > 0 {
            return true
        }
        return false
    }

    private static func isDecorativeImageNode(_ node: LoupeNode) -> Bool {
        isImageNode(node)
            && !node.isInteractive
            && node.accessibility?.isElement != true
            && node.text == nil
            && node.value == nil
    }

    private static func isScrollInsetReservedOverlap(
        _ first: LoupeNode,
        _ second: LoupeNode,
        screenFrame: LoupeRect
    ) -> Bool {
        if isScrollInsetReservedOverlap(scrollNode: first, overlayNode: second, screenFrame: screenFrame) {
            return true
        }
        return isScrollInsetReservedOverlap(scrollNode: second, overlayNode: first, screenFrame: screenFrame)
    }

    private static func isScrollInsetReservedOverlap(
        scrollNode: LoupeNode,
        overlayNode: LoupeNode,
        screenFrame: LoupeRect
    ) -> Bool {
        guard isScrollContainer(scrollNode),
              let scrollView = scrollNode.uiKit?.scrollView,
              let scrollFrame = scrollNode.frame,
              let overlayFrame = overlayNode.frame,
              let clippedScrollFrame = clipped(scrollFrame, to: screenFrame),
              let clippedOverlayFrame = clipped(overlayFrame, to: screenFrame) else {
            return false
        }

        guard let overlap = intersection(clippedScrollFrame, clippedOverlayFrame) else {
            return false
        }

        let tolerance = 1.0
        let horizontalCoverage = overlap.width / max(1, min(clippedScrollFrame.width, clippedOverlayFrame.width))
        let verticalCoverage = overlap.height / max(1, min(clippedScrollFrame.height, clippedOverlayFrame.height))

        if horizontalCoverage >= 0.5 {
            if clippedOverlayFrame.maxY >= clippedScrollFrame.maxY - tolerance,
               overlap.height <= scrollView.adjustedContentInset.bottom + tolerance {
                return true
            }
            if clippedOverlayFrame.y <= clippedScrollFrame.y + tolerance,
               overlap.height <= scrollView.adjustedContentInset.top + tolerance {
                return true
            }
        }

        if verticalCoverage >= 0.5 {
            if clippedOverlayFrame.maxX >= clippedScrollFrame.maxX - tolerance,
               overlap.width <= scrollView.adjustedContentInset.right + tolerance {
                return true
            }
            if clippedOverlayFrame.x <= clippedScrollFrame.x + tolerance,
               overlap.width <= scrollView.adjustedContentInset.left + tolerance {
                return true
            }
        }

        return false
    }

    private static func isImageNode(_ node: LoupeNode) -> Bool {
        node.role == "image" || node.uiKit?.imageView != nil
    }

    private static func isLoupeProbe(_ node: LoupeNode) -> Bool {
        if node.typeName == "LoupeWatchProbe" {
            return true
        }
        if case .bool(true) = node.custom["loupe.probe"] {
            return true
        }
        return false
    }

    private static func interactiveIssues(
        in snapshot: LoupeSnapshot,
        screenFrame: LoupeRect,
        activeModalOverlayRefs: Set<String>,
        options: LoupeLayoutAuditOptions
    ) -> [LoupeLayoutIssue] {
        snapshot.nodes.values.flatMap { node -> [LoupeLayoutIssue] in
            guard node.isVisible, node.isInteractive, let frame = node.frame else {
                return []
            }
            guard intersectsScreen(node, screenFrame: screenFrame) else {
                return []
            }
            guard shouldAuditNodeInModalContext(node, activeModalOverlayRefs: activeModalOverlayRefs, snapshot: snapshot) else {
                return []
            }
            guard !isSystemChromeDescendant(node, in: snapshot) else {
                return []
            }

            var issues: [LoupeLayoutIssue] = []
            if shouldRequireTestID(node, in: snapshot), node.testID == nil {
                issues.append(
                    LoupeLayoutIssue(
                        kind: .missingTestID,
                        ref: node.ref,
                        testID: nil,
                        frame: frame,
                        message: "\(displayName(node)) is interactive but has no testID"
                    )
                )
            }

            let minimumSide = min(frame.width, frame.height)
            if shouldAuditTouchTargetSize(node, in: snapshot), minimumSide < options.minTouchTarget {
                issues.append(
                    LoupeLayoutIssue(
                        kind: .smallInteractiveTarget,
                        ref: node.ref,
                        testID: node.testID,
                        frame: frame,
                        measuredValue: minimumSide,
                        expectedValue: options.minTouchTarget,
                        message: "\(displayName(node)) has touch target side \(minimumSide), below \(options.minTouchTarget)"
                    )
                )
            }
            return issues
        }
    }

    private static func shouldAuditChildContainment(parent: LoupeNode, child: LoupeNode) -> Bool {
        if isLoupeProbe(child) {
            return false
        }
        if isScrollContainer(parent) {
            return false
        }
        if isFocusDecoration(parent) || isFocusDecoration(child) {
            return false
        }
        if isTextEditingImplementation(parent) || isTextEditingImplementation(child) {
            return false
        }
        return true
    }

    private static func isScrollContainer(_ node: LoupeNode) -> Bool {
        if node.uiKit?.scrollView != nil || node.uiKit?.collectionView != nil || node.uiKit?.tableView != nil {
            return true
        }
        switch node.role {
        case "scrollView", "tableView", "collectionView":
            return true
        default:
            return false
        }
    }

    private static func isFocusDecoration(_ node: LoupeNode) -> Bool {
        guard isAppleRuntime(node) else {
            return false
        }
        let className = node.uiKit?.className ?? node.typeName
        return className.hasPrefix("_UIFloatingContent") || className.hasPrefix("_UIFocus")
    }

    private static func isTextEditingImplementation(_ node: LoupeNode) -> Bool {
        guard isAppleRuntime(node) else {
            return false
        }
        let className = node.uiKit?.className ?? node.typeName
        return className.hasPrefix("_UIText")
            || className.hasPrefix("_UICursor")
            || className == "UIStandardTextCursorView"
    }

    private static func shouldAuditTouchTargetSize(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        if isSystemOwnedImplementationDetail(node) {
            return false
        }
        if isSystemOwnedCellAccessory(node, in: snapshot) {
            return false
        }
        if isSyntheticNode(node) {
            return false
        }
        if isScrollContainer(node) {
            return false
        }

        if isSystemTabBarItem(node, in: snapshot) {
            return false
        }
        if node.testID == nil, node.uiKit?.segmentedControl != nil {
            return false
        }
        if node.testID == nil, node.uiKit?.textField != nil {
            return false
        }
        if isPassiveImageElement(node) {
            return false
        }
        return true
    }

    private static func isPassiveImageElement(_ node: LoupeNode) -> Bool {
        let controlEvents = node.uiKit?.control?.controlEvents ?? []
        let gestureRecognizers = node.uiKit?.gestureRecognizers ?? []
        let hasImageSemantics = node.role == "image"
            || node.uiKit?.imageView != nil
            || node.accessibility?.traits.contains("image") == true
        return hasImageSemantics
            && node.testID == nil
            && controlEvents.isEmpty
            && gestureRecognizers.isEmpty
    }

    private static func isSyntheticNode(_ node: LoupeNode) -> Bool {
        if case .bool(true) = node.custom["synthetic"] {
            return true
        }
        return false
    }

    private static func isSystemTabBarItem(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard node.testID == nil else {
            return false
        }

        if hasSyntheticSource("UITabBarItem", node) {
            return true
        }
        if hasAncestorRole("tabBar", node, in: snapshot),
           node.role == "button" || node.uiKit?.control != nil {
            return true
        }
        return false
    }

    private static func hasSyntheticSource(_ source: String, _ node: LoupeNode) -> Bool {
        guard case .bool(true) = node.custom["synthetic"],
              case let .string(nodeSource) = node.custom["source"],
              nodeSource == source else {
            return false
        }
        return true
    }

    private static func contrastIssues(
        in snapshot: LoupeSnapshot,
        screenFrame: LoupeRect,
        activeModalOverlayRefs: Set<String>,
        options: LoupeLayoutAuditOptions
    ) -> [LoupeLayoutIssue] {
        snapshot.nodes.values.compactMap { node in
            guard
                node.isVisible,
                intersectsScreen(node, screenFrame: screenFrame),
                shouldAuditNodeInModalContext(node, activeModalOverlayRefs: activeModalOverlayRefs, snapshot: snapshot),
                shouldAuditTextContrast(node, in: snapshot),
                LoupeObservationCompactor.displayText(for: node) != nil,
                let textColor = node.style?.textColor,
                let backgroundColor = effectiveBackgroundColor(for: node, in: snapshot)
            else {
                return nil
            }

            let ratio = contrastRatio(textColor, backgroundColor)
            guard ratio < options.minContrastRatio else {
                return nil
            }

            return LoupeLayoutIssue(
                kind: .lowTextContrast,
                ref: node.ref,
                testID: node.testID,
                frame: node.frame,
                measuredValue: ratio,
                expectedValue: options.minContrastRatio,
                message: "\(displayName(node)) text contrast \(ratio) is below \(options.minContrastRatio)"
            )
        }
    }

    private static func shouldAuditTextContrast(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        if isTextFieldPlaceholderLabel(node, in: snapshot) {
            return false
        }
        if isButtonImplementationLabelDuplicate(node, in: snapshot) {
            return false
        }
        return true
    }

    private static func isTextFieldPlaceholderLabel(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard node.testID == nil,
              node.role == "staticText",
              node.uiKit?.label != nil else {
            return false
        }

        guard let parentRef = node.parentRef, let parent = snapshot.nodes[parentRef] else {
            return false
        }
        guard parent.role == "textField" || parent.uiKit?.textField != nil else {
            return false
        }

        return LoupeObservationCompactor.displayText(for: parent) == LoupeObservationCompactor.displayText(for: node)
    }

    private static func isButtonImplementationLabelDuplicate(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard isAppleRuntime(node),
              node.testID == nil,
              node.role == "staticText",
              node.uiKit?.label != nil,
              node.accessibility?.isElement != true,
              !node.isInteractive,
              let parentRef = node.parentRef,
              let parent = snapshot.nodes[parentRef],
              isAppleRuntime(parent),
              parent.uiKit?.button != nil,
              let nodeText = LoupeObservationCompactor.displayText(for: node),
              let parentText = LoupeObservationCompactor.displayText(for: parent),
              nodeText == parentText else {
            return false
        }

        guard let parentFrame = parent.frame, let nodeFrame = node.frame else {
            return true
        }
        return parentFrame.contains(nodeFrame, tolerance: 1)
    }

    private static func effectiveBackgroundColor(for node: LoupeNode, in snapshot: LoupeSnapshot) -> LoupeColor? {
        if let color = node.style?.backgroundColor, color.alpha > 0 {
            return color
        }

        if let color = containingSiblingBackgroundColor(for: node, in: snapshot) {
            return color
        }

        var parentRef = node.parentRef
        while let ref = parentRef, let parent = snapshot.nodes[ref] {
            if isRootWindowNode(parent) {
                return nil
            }
            if let color = parent.style?.backgroundColor, color.alpha > 0 {
                return color
            }
            parentRef = parent.parentRef
        }
        return nil
    }

    private static func containingSiblingBackgroundColor(for node: LoupeNode, in snapshot: LoupeSnapshot) -> LoupeColor? {
        guard let nodeFrame = node.frame else { return nil }

        var currentRef = node.ref
        var parentRef = node.parentRef
        var candidates: [(area: Double, color: LoupeColor)] = []

        while let ref = parentRef, let parent = snapshot.nodes[ref] {
            let siblings = siblingRefsBefore(currentRef, in: parent)
            for siblingRef in siblings {
                guard let sibling = snapshot.nodes[siblingRef],
                      let siblingFrame = sibling.frame,
                      siblingFrame.contains(nodeFrame, tolerance: 1),
                      isContrastBackgroundCandidate(sibling),
                      let color = sibling.style?.backgroundColor,
                      color.alpha > 0
                else {
                    continue
                }
                candidates.append((area: area(siblingFrame), color: color))
            }

            currentRef = parent.ref
            parentRef = parent.parentRef
        }

        return candidates.min { $0.area < $1.area }?.color
    }

    private static func siblingRefsBefore(_ ref: String, in parent: LoupeNode) -> ArraySlice<String> {
        guard let index = parent.children.firstIndex(of: ref) else {
            return parent.children[...]
        }
        return parent.children[..<index]
    }

    private static func isContrastBackgroundCandidate(_ node: LoupeNode) -> Bool {
        guard node.isVisible,
              !node.isInteractive,
              node.accessibility?.isElement != true,
              LoupeObservationCompactor.displayText(for: node) == nil,
              let color = node.style?.backgroundColor,
              color.alpha > 0
        else {
            return false
        }
        return true
    }

    private static func isSystemOwnedImplementationDetail(_ node: LoupeNode) -> Bool {
        guard isAppleRuntime(node), node.testID == nil else {
            return false
        }
        return !isPublicInteractiveUIKitElement(node)
    }

    private static func isSystemGeneratedTestID(_ testID: String?) -> Bool {
        guard let testID else { return false }
        return testID.hasPrefix("_")
            || testID.hasPrefix("com.apple.")
            || testID == "inputView"
    }

    private static func hasAmbiguousDuplicateTargets(_ nodes: [LoupeNode]) -> Bool {
        for index in nodes.indices {
            for otherIndex in nodes.indices.dropFirst(index + 1) {
                if !sameActionTarget(nodes[index], nodes[otherIndex]) {
                    return true
                }
            }
        }
        return false
    }

    private static func sameActionTarget(_ first: LoupeNode, _ second: LoupeNode) -> Bool {
        guard let firstFrame = first.frame, let secondFrame = second.frame else {
            return first.frame == nil && second.frame == nil
        }
        return abs(firstFrame.x - secondFrame.x) <= 1
            && abs(firstFrame.y - secondFrame.y) <= 1
            && abs(firstFrame.width - secondFrame.width) <= 1
            && abs(firstFrame.height - secondFrame.height) <= 1
    }

    private static func containmentOverflowRatio(parent: LoupeRect, child: LoupeRect, tolerance: Double) -> Double {
        if parent.contains(child, tolerance: tolerance) {
            return 0
        }

        let childArea = area(child)
        guard childArea > 0 else { return 0 }
        return max(0, childArea - parent.intersectionArea(with: child)) / childArea
    }

    private static func overlapRatio(_ first: LoupeRect, _ second: LoupeRect, overlapArea: Double) -> Double {
        let smallerArea = min(area(first), area(second))
        guard smallerArea > 0 else { return 0 }
        return overlapArea / smallerArea
    }

    private static func area(_ rect: LoupeRect) -> Double {
        max(0, rect.width) * max(0, rect.height)
    }

    private static func intersectsScreen(_ node: LoupeNode, screenFrame: LoupeRect) -> Bool {
        guard let frame = node.frame else { return false }
        return clipped(frame, to: screenFrame) != nil
    }

    private static func clipped(_ rect: LoupeRect, to bounds: LoupeRect) -> LoupeRect? {
        let x = max(rect.x, bounds.x)
        let y = max(rect.y, bounds.y)
        let maxX = min(rect.maxX, bounds.maxX)
        let maxY = min(rect.maxY, bounds.maxY)
        guard maxX > x, maxY > y else { return nil }
        return LoupeRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    private static func intersection(_ first: LoupeRect, _ second: LoupeRect) -> LoupeRect? {
        let x = max(first.x, second.x)
        let y = max(first.y, second.y)
        let maxX = min(first.maxX, second.maxX)
        let maxY = min(first.maxY, second.maxY)
        guard maxX > x, maxY > y else { return nil }
        return LoupeRect(x: x, y: y, width: maxX - x, height: maxY - y)
    }

    private static func isSystemChromeOverlapPair(_ first: LoupeNode, _ second: LoupeNode) -> Bool {
        isSystemChromeOverlapNode(first) || isSystemChromeOverlapNode(second)
    }

    private static func isIntentionalOverlayOverlapPair(
        _ first: LoupeNode,
        _ second: LoupeNode,
        snapshot: LoupeSnapshot,
        screenFrame: LoupeRect
    ) -> Bool {
        if isIntentionalOverlayOverlapNode(first) || isIntentionalOverlayOverlapNode(second) {
            return true
        }
        return (isModalBackdropNode(first, screenFrame: screenFrame)
            && containsActiveModalOverlayDescendant(second, in: snapshot, screenFrame: screenFrame))
            || (isModalBackdropNode(second, screenFrame: screenFrame)
                && containsActiveModalOverlayDescendant(first, in: snapshot, screenFrame: screenFrame))
    }

    private static func isIntentionalOverlayOverlapNode(_ node: LoupeNode) -> Bool {
        node.uiKit?.viewControllerRole == "alert"
    }

    private static func activeModalOverlayRefs(in snapshot: LoupeSnapshot, screenFrame: LoupeRect) -> Set<String> {
        Set(snapshot.nodes.values.compactMap { node in
            guard node.isVisible, intersectsScreen(node, screenFrame: screenFrame) else {
                return nil
            }
            return isActiveModalOverlayNode(node) ? node.ref : nil
        })
    }

    private static func isActiveModalOverlayNode(_ node: LoupeNode) -> Bool {
        node.uiKit?.viewControllerRole == "alert"
    }

    private static func containsActiveModalOverlayDescendant(
        _ node: LoupeNode,
        in snapshot: LoupeSnapshot,
        screenFrame: LoupeRect
    ) -> Bool {
        var refs = [node.ref]
        var seen = Set<String>()
        while let ref = refs.popLast() {
            guard seen.insert(ref).inserted, let current = snapshot.nodes[ref] else {
                continue
            }
            if current.isVisible,
               intersectsScreen(current, screenFrame: screenFrame),
               isActiveModalOverlayNode(current) {
                return true
            }
            refs.append(contentsOf: current.children)
        }
        return false
    }

    private static func isModalBackdropNode(_ node: LoupeNode, screenFrame: LoupeRect) -> Bool {
        guard isAppleRuntime(node),
              node.testID == nil,
              node.role == nil,
              node.accessibility?.isElement != true,
              !isPublicInteractiveUIKitElement(node),
              LoupeObservationCompactor.displayText(for: node) == nil,
              let frame = node.frame,
              let clippedFrame = clipped(frame, to: screenFrame) else {
            return false
        }
        let screenArea = area(screenFrame)
        guard screenArea > 0 else {
            return false
        }
        return area(clippedFrame) / screenArea >= 0.8
    }

    private static func shouldAuditNodeInModalContext(
        _ node: LoupeNode,
        activeModalOverlayRefs: Set<String>,
        snapshot: LoupeSnapshot
    ) -> Bool {
        guard !activeModalOverlayRefs.isEmpty else {
            return true
        }
        if activeModalOverlayRefs.contains(node.ref) {
            return true
        }

        var parentRef = node.parentRef
        while let ref = parentRef {
            if activeModalOverlayRefs.contains(ref) {
                return true
            }
            parentRef = snapshot.nodes[ref]?.parentRef
        }
        return false
    }

    private static func isSystemChromeOverlapNode(_ node: LoupeNode) -> Bool {
        if isRootWindowNode(node) {
            return true
        }
        if node.role == "navigationBar" || node.role == "tabBar" || node.role == "toolbar" {
            return true
        }
        if hasSyntheticSource("UIBarButtonItem", node) || hasSyntheticSource("UITabBarItem", node) {
            return true
        }
        return isSystemOwnedPassiveDecoration(node)
    }

    private static func isSystemChromeContainmentNode(_ node: LoupeNode) -> Bool {
        isSystemOwnedPassiveDecoration(node)
    }

    private static func isSystemOwnedPassiveDecoration(_ node: LoupeNode) -> Bool {
        guard isAppleRuntime(node) else {
            return false
        }
        if node.testID != nil || node.accessibility?.isElement == true {
            return false
        }
        if node.isInteractive || isPublicInteractiveUIKitElement(node) {
            return false
        }
        return LoupeObservationCompactor.displayText(for: node) == nil
    }

    private static func isRootWindowNode(_ node: LoupeNode) -> Bool {
        node.kind == .application || node.kind == .scene || node.kind == .window
    }

    private static func isSystemChromeDescendant(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard isAppleRuntime(node) else {
            return false
        }
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

    private static func isSystemOwnedAggregateContainer(_ node: LoupeNode, screenFrame: LoupeRect) -> Bool {
        guard isAppleRuntime(node),
              node.testID == nil,
              node.role == nil,
              node.accessibility?.isElement != true,
              !node.isInteractive,
              !node.children.isEmpty,
              let frame = node.frame else {
            return false
        }
        let screenArea = area(screenFrame)
        guard screenArea > 0 else {
            return false
        }
        return area(frame) / screenArea >= 0.5
    }

    private static func shouldRequireTestID(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        if isSystemOwnedImplementationDetail(node) {
            return false
        }
        if isSystemOwnedCellAccessory(node, in: snapshot) {
            return false
        }

        return isPublicInteractiveUIKitElement(node)
    }

    private static func isSystemOwnedCellAccessory(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard isAppleRuntime(node),
              node.testID == nil,
              node.role == "button",
              node.accessibility?.isElement != true,
              LoupeObservationCompactor.displayText(for: node) == nil,
              node.uiKit?.userInteractionEnabled == false,
              hasAncestorRole("cell", node, in: snapshot),
              hasImageDescendant(node, in: snapshot) else {
            return false
        }
        return true
    }

    private static func isPublicInteractiveUIKitElement(_ node: LoupeNode) -> Bool {
        if node.uiKit?.button != nil
            || node.uiKit?.switchControl != nil
            || node.uiKit?.slider != nil
            || node.uiKit?.stepper != nil
            || node.uiKit?.segmentedControl != nil
            || node.uiKit?.textField != nil
            || node.uiKit?.textView != nil {
            return true
        }
        return node.role == "cell"
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
            if isImageNode(child), LoupeObservationCompactor.displayText(for: child) == nil {
                return true
            }
            return hasImageDescendant(child, in: snapshot)
        }
    }

    private static func isAppleRuntime(_ node: LoupeNode) -> Bool {
        node.runtime?.frameworkBundleIdentifier?.hasPrefix("com.apple.") == true
    }

    private static func hasHorizontallyDisplacedCellAncestor(
        _ node: LoupeNode,
        in snapshot: LoupeSnapshot,
        screenFrame: LoupeRect
    ) -> Bool {
        var current: LoupeNode? = node
        while let candidate = current {
            if candidate.role == "cell", isHorizontallyPartiallyOffscreen(candidate, screenFrame: screenFrame) {
                return true
            }
            current = candidate.parentRef.flatMap { snapshot.nodes[$0] }
        }
        return false
    }

    private static func isHorizontallyPartiallyOffscreen(_ node: LoupeNode, screenFrame: LoupeRect) -> Bool {
        guard let frame = node.frame, frame.intersects(screenFrame) else {
            return false
        }
        return frame.x < screenFrame.x - 1 || frame.maxX > screenFrame.maxX + 1
    }

    private static func contrastRatio(_ lhs: LoupeColor, _ rhs: LoupeColor) -> Double {
        let first = relativeLuminance(lhs)
        let second = relativeLuminance(rhs)
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ color: LoupeColor) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private static func displayName(_ node: LoupeNode) -> String {
        node.testID ?? node.typeName
    }
}
