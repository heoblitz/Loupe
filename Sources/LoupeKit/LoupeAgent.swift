import Foundation
import LoupeCore

#if canImport(UIKit)
import ObjectiveC
import UIKit
#if canImport(WebKit)
import WebKit
#endif

private nonisolated(unsafe) var loupeMetadataKey: UInt8 = 0

public extension UIView {
    var loupeMetadata: [String: LoupeMetadataValue] {
        get {
            objc_getAssociatedObject(self, &loupeMetadataKey) as? [String: LoupeMetadataValue] ?? [:]
        }
        set {
            objc_setAssociatedObject(
                self,
                &loupeMetadataKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func testID(_ id: String) {
        accessibilityIdentifier = id
        loupeMetadata["id"] = .string(id)
    }

    func testProperty(_ key: String, _ value: String) {
        loupeMetadata[key] = .string(value)
    }

    func testProperty(_ key: String, _ value: Bool) {
        loupeMetadata[key] = .bool(value)
    }

    func testProperty(_ key: String, _ value: Int) {
        loupeMetadata[key] = .int(value)
    }

    func testProperty(_ key: String, _ value: Double) {
        loupeMetadata[key] = .double(value)
    }
}

@MainActor
public final class LoupeAgent {
    private var nextRef = 0
    private var nextNativeAccessibilityRef = 0

    public init() {}

    public func captureSnapshot() -> LoupeSnapshot {
        captureSnapshotWithViewRefs().snapshot
    }

    public func captureAccessibilityTree() -> LoupeAccessibilityTree {
        let capture = captureSnapshotWithViewRefs()
        guard ProcessInfo.processInfo.environment["LOUPE_NATIVE_ACCESSIBILITY"] == "1" else {
            return LoupeAccessibilityTree.build(from: capture.snapshot)
        }
        return captureNativeAccessibilityTree(snapshot: capture.snapshot, viewRefs: capture.viewRefs)
    }

    private func captureSnapshotWithViewRefs() -> CapturedSnapshot {
        nextRef = 0

        var nodes: [String: LoupeNode] = [:]
        var viewRefs: [ObjectIdentifier: String] = [:]
        var viewsByRef: [String: UIView] = [:]
        let screen = UIScreen.main
        let screenBounds = screen.bounds
        let interfaceStyle = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.traitCollection.userInterfaceStyle }
            .first
            .map(interfaceStyleName)

        let screenInfo = LoupeScreen(
            size: LoupeSize(
                width: finiteDouble(screenBounds.width.doubleValue) ?? 0,
                height: finiteDouble(screenBounds.height.doubleValue) ?? 0
            ),
            scale: finiteDouble(screen.scale.doubleValue) ?? 1,
            interfaceStyle: interfaceStyle
        )

        let appRef = makeRef()
        var sceneRefs: [String] = []

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            let sceneRef = makeRef()
            var windowRefs: [String] = []

            for window in scene.windows {
                let windowRef = captureWindow(
                    window,
                    parentRef: sceneRef,
                    nodes: &nodes,
                    viewRefs: &viewRefs,
                    viewsByRef: &viewsByRef
                )
                windowRefs.append(windowRef)
            }

            nodes[sceneRef] = LoupeNode(
                ref: sceneRef,
                parentRef: appRef,
                kind: .scene,
                typeName: "UIWindowScene",
                role: "scene",
                frame: nil,
                isVisible: scene.activationState == .foregroundActive,
                isEnabled: true,
                isInteractive: false,
                custom: [
                    "activationState": .string(sceneActivationStateName(scene.activationState))
                ],
                children: windowRefs
            )
            sceneRefs.append(sceneRef)
        }

        nodes[appRef] = LoupeNode(
            ref: appRef,
            parentRef: nil,
            kind: .application,
            typeName: "UIApplication",
            role: "application",
            frame: LoupeRect(
                x: 0,
                y: 0,
                width: finiteDouble(screenBounds.width.doubleValue) ?? 0,
                height: finiteDouble(screenBounds.height.doubleValue) ?? 0
            ),
            isVisible: true,
            isEnabled: true,
            isInteractive: false,
            children: sceneRefs
        )

        let snapshot = LoupeSnapshot(
            id: UUID().uuidString,
            capturedAt: Date(),
            screen: screenInfo,
            rootRefs: [appRef],
            nodes: nodes
        )

        return CapturedSnapshot(snapshot: snapshot, viewRefs: viewRefs, viewsByRef: viewsByRef)
    }

    public func captureCompactObservation(
        options: LoupeObservationOptions = LoupeObservationOptions()
    ) -> LoupeCompactObservation {
        LoupeObservationCompactor.compact(captureSnapshot(), options: options)
    }

    public func mutate(_ request: LoupeMutationRequest) throws -> LoupeMutationResponse {
        let beforeCapture = captureSnapshotWithViewRefs()
        let selector = loupeSelector(from: request.selector)
        let matches = LoupeSnapshotQuery.find(
            selector,
            in: beforeCapture.snapshot,
            options: LoupeQueryOptions(includeHidden: true, includeDisabled: true, maxResults: 8)
        )

        guard matches.count == 1, let target = matches.first else {
            if matches.isEmpty {
                throw LoupeMutationError(status: 404, code: "node_not_found", message: "No view node matched selector.")
            }
            throw LoupeMutationError(
                code: "ambiguous_selector",
                message: "Selector matched multiple view nodes: \(matches.map { $0.ref }.joined(separator: ", "))"
            )
        }

        guard let beforeNode = beforeCapture.snapshot.nodes[target.ref] else {
            throw LoupeMutationError(status: 404, code: "node_not_found", message: "Matched node disappeared before mutation.")
        }
        guard let view = beforeCapture.viewsByRef[target.ref] else {
            throw LoupeMutationError(
                code: "unsupported_target",
                message: "Matched node \(target.ref) is synthetic or not backed by a UIView."
            )
        }

        try applyMutation(
            property: request.property,
            value: request.value,
            to: view,
            layout: request.layout,
            animation: request.animation
        )

        LoupeRuntime.shared.log(
            level: "info",
            "mutation_applied",
            metadata: [
                "property": .string(request.property),
                "ref": .string(target.ref)
            ]
        )

        let afterCapture = captureSnapshotWithViewRefs()
        guard let afterNode = afterCapture.snapshot.nodes[target.ref] else {
            throw LoupeMutationError(status: 404, code: "node_not_found", message: "Mutated node disappeared after mutation.")
        }
        let effective = mutationPropertyValue(request.property, in: afterNode)
        let changed = effective.map { mutationValuesApproximatelyEqual(request.value, $0) }
        let warning = mutationWarning(
            request: request,
            targetRef: target.ref,
            changed: changed,
            snapshot: afterCapture.snapshot
        )

        return LoupeMutationResponse(
            property: request.property,
            selector: request.selector,
            value: request.value,
            target: target,
            before: beforeNode,
            after: afterNode,
            hierarchy: mutationHierarchyContext(targetRef: target.ref, snapshot: afterCapture.snapshot),
            requested: request.value,
            effective: effective,
            changed: changed,
            animation: request.animation,
            warning: warning,
            snapshotID: afterCapture.snapshot.id
        )
    }

    public func mutateConstraint(_ request: LoupeConstraintMutationRequest) throws -> LoupeConstraintMutationResponse {
        guard request.constant != nil || request.priority != nil || request.isActive != nil else {
            throw LoupeMutationError(code: "missing_constraint_mutation", message: "Constraint mutation requires constant, priority, or isActive.")
        }
        guard let constraint = runtimeConstraints().first(where: { constraintID($0) == request.id }) else {
            throw LoupeMutationError(status: 404, code: "constraint_not_found", message: "No runtime constraint matched id \(request.id).")
        }

        let before = layoutConstraintProperties(constraint)
        if let constant = request.constant {
            constraint.constant = CGFloat(constant)
        }
        if let priority = request.priority {
            guard priority >= 1, priority <= 1000 else {
                throw LoupeMutationError(code: "invalid_value", message: "Constraint priority must be between 1 and 1000.")
            }
            constraint.priority = UILayoutPriority(Float(priority))
        }
        if let isActive = request.isActive {
            constraint.isActive = isActive
        }

        if request.layout {
            layoutRuntimeWindows()
        }

        let after = layoutConstraintProperties(constraint)
        let changed = constraintMutationMatches(request, after)
        let warning = changed ? nil : "Constraint mutation applied, but the effective constraint does not match the requested value. A layout owner may have restored it."
        let snapshot = captureSnapshot()

        return LoupeConstraintMutationResponse(
            id: request.id,
            before: before,
            after: after,
            requested: request,
            changed: changed,
            warning: warning,
            snapshotID: snapshot.id
        )
    }

    public func mutationCapabilities() -> [LoupeMutationCapability] {
        mutationDescriptors
            .map { descriptor in
                LoupeMutationCapability(
                    property: descriptor.property,
                    aliases: descriptor.aliases.sorted()
                )
            }
            .sorted { $0.property < $1.property }
    }

    public func encodedSnapshot() throws -> Data {
        try encodedSnapshot(encoder: makeLoupeJSONEncoder())
    }

    public func encodedSnapshot(encoder: JSONEncoder) throws -> Data {
        try encoder.encode(captureSnapshot())
    }

    private func captureWindow(
        _ window: UIWindow,
        parentRef: String,
        nodes: inout [String: LoupeNode],
        viewRefs: inout [ObjectIdentifier: String],
        viewsByRef: inout [String: UIView]
    ) -> String {
        let ref = makeRef()
        viewRefs[ObjectIdentifier(window)] = ref
        viewsByRef[ref] = window
        var childRefs: [String] = []

        for subview in window.subviews {
            let childRef = captureView(
                subview,
                parentRef: ref,
                inheritedVisible: window.isHidden == false && window.alpha > 0.01,
                nodes: &nodes,
                viewRefs: &viewRefs,
                viewsByRef: &viewsByRef
            )
            childRefs.append(childRef)
        }

        nodes[ref] = LoupeNode(
            ref: ref,
            parentRef: parentRef,
            kind: .window,
            typeName: typeName(of: window),
            role: "window",
            frame: loupeRect(from: window.frame),
            isVisible: window.isHidden == false && window.alpha > 0.01,
            isEnabled: true,
            isInteractive: true,
            style: style(for: window),
            accessibility: accessibility(for: window),
            runtime: runtimeProperties(for: window),
            uiKit: uiKitProperties(for: window),
            custom: window.loupeMetadata,
            children: childRefs
        )

        return ref
    }

    private func captureView(
        _ view: UIView,
        parentRef: String,
        inheritedVisible: Bool,
        nodes: inout [String: LoupeNode],
        viewRefs: inout [ObjectIdentifier: String],
        viewsByRef: inout [String: UIView]
    ) -> String {
        let ref = makeRef()
        viewRefs[ObjectIdentifier(view)] = ref
        viewsByRef[ref] = view
        let visible = inheritedVisible
            && view.isHidden == false
            && view.alpha > 0.01
            && view.bounds.width > 0
            && view.bounds.height > 0

        var childRefs: [String] = []
        for subview in view.subviews {
            let childRef = captureView(
                subview,
                parentRef: ref,
                inheritedVisible: visible,
                nodes: &nodes,
                viewRefs: &viewRefs,
                viewsByRef: &viewsByRef
            )
            childRefs.append(childRef)
        }
        childRefs.append(
            contentsOf: captureSyntheticBarButtonItems(
                in: view,
                parentRef: ref,
                inheritedVisible: visible,
                nodes: &nodes
            )
        )
        childRefs.append(
            contentsOf: captureSyntheticTabBarItems(
                in: view,
                parentRef: ref,
                inheritedVisible: visible,
                nodes: &nodes
            )
        )

        let testID = view.accessibilityIdentifier ?? stringMetadata("id", from: view.loupeMetadata)
        let customMetadata = mergedMetadata(view.loupeMetadata, with: LoupeRuntime.shared.metadata(forTestID: testID))

        nodes[ref] = LoupeNode(
            ref: ref,
            parentRef: parentRef,
            kind: .view,
            typeName: typeName(of: view),
            role: role(for: view),
            testID: testID,
            label: view.accessibilityLabel,
            value: view.accessibilityValue,
            placeholder: placeholder(for: view),
            text: text(for: view),
            renderedText: renderedText(for: view),
            semanticText: semanticText(for: view),
            frame: frameInScreen(for: view),
            isVisible: visible,
            isEnabled: isEnabled(view),
            isInteractive: isInteractive(view),
            style: style(for: view),
            accessibility: accessibility(for: view),
            runtime: runtimeProperties(for: view),
            uiKit: uiKitProperties(for: view),
            custom: customMetadata,
            children: childRefs
        )

        return ref
    }

    private func captureSyntheticBarButtonItems(
        in view: UIView,
        parentRef: String,
        inheritedVisible: Bool,
        nodes: inout [String: LoupeNode]
    ) -> [String] {
        guard let navigationBar = view as? UINavigationBar, let item = navigationBar.topItem else {
            return []
        }

        let leftItems = item.leftBarButtonItems ?? item.leftBarButtonItem.map { [$0] } ?? []
        let rightItems = item.rightBarButtonItems ?? item.rightBarButtonItem.map { [$0] } ?? []
        let candidates = barButtonCandidateViews(in: navigationBar)
        var consumedCandidateIDs = Set<ObjectIdentifier>()
        var refs: [String] = []

        for (index, barButtonItem) in leftItems.enumerated() {
            let ref = makeRef()
            let match = matchedBarButtonView(
                for: barButtonItem,
                position: "left",
                index: index,
                candidates: candidates,
                consumedCandidateIDs: &consumedCandidateIDs
            )
            nodes[ref] = syntheticBarButtonNode(
                barButtonItem,
                ref: ref,
                parentRef: parentRef,
                position: "left",
                index: index,
                matchedView: match,
                inheritedVisible: inheritedVisible
            )
            refs.append(ref)
        }

        for (index, barButtonItem) in rightItems.enumerated() {
            let ref = makeRef()
            let match = matchedBarButtonView(
                for: barButtonItem,
                position: "right",
                index: index,
                candidates: candidates,
                consumedCandidateIDs: &consumedCandidateIDs
            )
            nodes[ref] = syntheticBarButtonNode(
                barButtonItem,
                ref: ref,
                parentRef: parentRef,
                position: "right",
                index: index,
                matchedView: match,
                inheritedVisible: inheritedVisible
            )
            refs.append(ref)
        }

        return refs
    }

    private func captureSyntheticTabBarItems(
        in view: UIView,
        parentRef: String,
        inheritedVisible: Bool,
        nodes: inout [String: LoupeNode]
    ) -> [String] {
        guard let tabBar = view as? UITabBar, let items = tabBar.items, !items.isEmpty else {
            return []
        }

        let candidates = tabBarItemCandidateViews(in: tabBar)
        var consumedCandidateIDs = Set<ObjectIdentifier>()
        var refs: [String] = []

        for (index, tabBarItem) in items.enumerated() {
            let ref = makeRef()
            let match = matchedTabBarItemView(
                for: tabBarItem,
                candidates: candidates,
                consumedCandidateIDs: &consumedCandidateIDs
            )
            nodes[ref] = syntheticTabBarItemNode(
                tabBarItem,
                ref: ref,
                parentRef: parentRef,
                index: index,
                selected: tabBar.selectedItem === tabBarItem,
                matchedView: match,
                inheritedVisible: inheritedVisible
            )
            refs.append(ref)
        }

        return refs
    }

    private func captureNativeAccessibilityTree(
        snapshot: LoupeSnapshot,
        viewRefs: [ObjectIdentifier: String]
    ) -> LoupeAccessibilityTree {
        nextNativeAccessibilityRef = 0

        var tree = LoupeAccessibilityTree.build(from: snapshot)
        var signatures = Set(tree.nodes.values.map(nativeAccessibilitySignature(for:)))

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                appendNativeAccessibilityElements(
                    in: window,
                    snapshot: snapshot,
                    viewRefs: viewRefs,
                    tree: &tree,
                    signatures: &signatures
                )
            }
        }

        return tree
    }

    private func appendNativeAccessibilityElements(
        in view: UIView,
        snapshot: LoupeSnapshot,
        viewRefs: [ObjectIdentifier: String],
        tree: inout LoupeAccessibilityTree,
        signatures: inout Set<String>
    ) {
        guard let sourceRef = viewRefs[ObjectIdentifier(view)] else {
            view.subviews.forEach {
                appendNativeAccessibilityElements(
                    in: $0,
                    snapshot: snapshot,
                    viewRefs: viewRefs,
                    tree: &tree,
                    signatures: &signatures
                )
            }
            return
        }

        var visitedContainers = Set<ObjectIdentifier>()
        for element in nativeAccessibilityElements(in: view, visitedContainers: &visitedContainers) {
            if element is UIView {
                continue
            }

            guard let node = nativeAccessibilityNode(
                for: element,
                sourceRef: sourceRef,
                snapshot: snapshot,
                tree: tree
            ) else {
                continue
            }

            let signature = nativeAccessibilitySignature(for: node)
            guard !signatures.contains(signature) else {
                continue
            }

            signatures.insert(signature)
            tree.nodes[node.ref] = node
            if let parentRef = node.parentRef, var parent = tree.nodes[parentRef] {
                parent.children.append(node.ref)
                parent.children.sort { lhs, rhs in
                    accessibilityVisualOrder(tree.nodes[lhs], tree.nodes[rhs])
                }
                tree.nodes[parentRef] = parent
            } else {
                tree.rootRefs.append(node.ref)
                tree.rootRefs.sort { lhs, rhs in
                    accessibilityVisualOrder(tree.nodes[lhs], tree.nodes[rhs])
                }
            }
        }

        view.subviews.forEach {
            appendNativeAccessibilityElements(
                in: $0,
                snapshot: snapshot,
                viewRefs: viewRefs,
                tree: &tree,
                signatures: &signatures
            )
        }
    }

    private func nativeAccessibilityNode(
        for element: NSObject,
        sourceRef: String,
        snapshot: LoupeSnapshot,
        tree: LoupeAccessibilityTree
    ) -> LoupeAccessibilityNode? {
        let testID = accessibilityIdentifier(for: element)
        let label = nonEmpty(element.accessibilityLabel)
        let value = nonEmpty(element.accessibilityValue)
        let hint = nonEmpty(element.accessibilityHint)
        let traits = accessibilityTraits(element.accessibilityTraits)
        let frame = loupeRect(from: element.accessibilityFrame)
        let activationPoint = validActivationPoint(
            LoupePoint(
                x: finiteDouble(Double(element.accessibilityActivationPoint.x)) ?? 0,
                y: finiteDouble(Double(element.accessibilityActivationPoint.y)) ?? 0
            ),
            frame: frame
        )

        guard testID != nil || label != nil || value != nil || hint != nil || !traits.isEmpty else {
            return nil
        }

        let isVisible = !element.accessibilityElementsHidden
            && !frame.isEmpty
            && intersectsScreen(frame, screen: snapshot.screen.size)

        return LoupeAccessibilityNode(
            ref: makeNativeAccessibilityRef(sourceRef: sourceRef),
            sourceRef: sourceRef,
            parentRef: treeParentRef(for: sourceRef, tree: tree),
            role: accessibilityRole(forTraits: traits),
            label: label,
            value: value,
            hint: hint,
            testID: testID,
            traits: traits,
            frame: frame,
            activationPoint: activationPoint,
            isVisible: isVisible,
            isEnabled: !traits.contains("notEnabled"),
            isInteractive: isInteractiveAccessibilityTraits(traits),
            children: []
        )
    }

    private func nativeAccessibilityElements(
        in container: NSObject,
        visitedContainers: inout Set<ObjectIdentifier>,
        depth: Int = 0
    ) -> [NSObject] {
        guard depth < 8 else {
            return []
        }

        let containerID = ObjectIdentifier(container)
        guard !visitedContainers.contains(containerID) else {
            return []
        }
        visitedContainers.insert(containerID)

        let directElements: [NSObject]
        if let elements = container.accessibilityElements, !elements.isEmpty {
            directElements = elements.compactMap { $0 as? NSObject }
        } else {
            let count = container.accessibilityElementCount()
            guard count > 0 else {
                return []
            }
            directElements = (0..<count).compactMap { container.accessibilityElement(at: $0) as? NSObject }
        }

        var elements: [NSObject] = []
        for element in directElements {
            elements.append(element)
            if element is UIView {
                continue
            }

            elements.append(
                contentsOf: nativeAccessibilityElements(
                    in: element,
                    visitedContainers: &visitedContainers,
                    depth: depth + 1
                )
            )
        }

        return elements
    }

    private func makeRef() -> String {
        nextRef += 1
        return "n\(nextRef)"
    }

    private func makeNativeAccessibilityRef(sourceRef: String) -> String {
        nextNativeAccessibilityRef += 1
        return "ax-native-\(sourceRef)-\(nextNativeAccessibilityRef)"
    }
}

private struct CapturedSnapshot {
    var snapshot: LoupeSnapshot
    var viewRefs: [ObjectIdentifier: String]
    var viewsByRef: [String: UIView]
}

@MainActor
private func loupeSelector(from selector: LoupeMutationSelector) -> LoupeSelector {
    switch selector.kind {
    case .testID:
        return .testID(selector.value)
    case .ref:
        return .ref(selector.value)
    case .role:
        return .role(selector.value)
    case .text:
        return .text(selector.value, exact: selector.exact)
    case .roleAndText:
        return .roleAndText(role: selector.role ?? "", text: selector.value, exact: selector.exact)
    }
}

@MainActor
private func mutationHierarchyContext(targetRef: String, snapshot: LoupeSnapshot) -> LoupeMutationHierarchyContext? {
    guard let target = snapshot.nodes[targetRef] else {
        return nil
    }
    let parentNode = target.parentRef.flatMap { snapshot.nodes[$0] }
    let parent = parentNode.map(mutationNodeSummary)
    let siblings = parentNode?.children
        .filter { $0 != targetRef }
        .compactMap { snapshot.nodes[$0].map(mutationNodeSummary) } ?? []
    let children = target.children.compactMap { snapshot.nodes[$0].map(mutationNodeSummary) }

    return LoupeMutationHierarchyContext(
        target: mutationNodeSummary(target),
        parent: parent,
        siblings: siblings,
        children: children
    )
}

private func mutationWarning(
    request: LoupeMutationRequest,
    targetRef: String,
    changed: Bool?,
    snapshot: LoupeSnapshot
) -> String? {
    var warnings: [String] = []
    if changed == false {
        warnings.append("Mutation applied, but the effective snapshot value does not match the requested value. A layout pass or UIKit owner may have restored it.")
    }
    if normalizedMutationProperty(request.property) == "backgroundcolor",
       let coverageWarning = backgroundPaintCoverageWarning(targetRef: targetRef, snapshot: snapshot) {
        warnings.append(coverageWarning)
    }
    return warnings.isEmpty ? nil : warnings.joined(separator: " ")
}

private func backgroundPaintCoverageWarning(targetRef: String, snapshot: LoupeSnapshot) -> String? {
    guard let target = snapshot.nodes[targetRef], let targetFrame = target.frame else {
        return nil
    }
    guard let coveringChild = target.children.compactMap({ snapshot.nodes[$0] }).first(where: { child in
        guard child.isVisible, let childFrame = child.frame else {
            return false
        }
        return framesApproximatelyEqual(targetFrame, childFrame)
    }) else {
        return nil
    }
    let typeName = coveringChild.uiKit?.className ?? coveringChild.typeName
    return "backgroundColor changed, but same-frame child \(coveringChild.ref) (\(typeName)) may cover it. Try mutating \(coveringChild.ref) backgroundColor instead."
}

private func framesApproximatelyEqual(_ lhs: LoupeRect, _ rhs: LoupeRect, tolerance: Double = 0.5) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance
        && abs(lhs.y - rhs.y) <= tolerance
        && abs(lhs.width - rhs.width) <= tolerance
        && abs(lhs.height - rhs.height) <= tolerance
}

@MainActor
private func mutationNodeSummary(_ node: LoupeNode) -> LoupeMutationNodeSummary {
    LoupeMutationNodeSummary(
        ref: node.ref,
        typeName: node.uiKit?.className ?? node.typeName,
        role: node.role,
        testID: node.testID,
        text: LoupeObservationCompactor.displayText(for: node),
        frame: node.frame
    )
}

@MainActor
private func applyMutation(
    property: String,
    value: LoupeMutationValue,
    to view: UIView,
    layout: Bool,
    animation: LoupeMutationAnimation?
) throws {
    let property = normalizedMutationProperty(property)
    guard let descriptor = mutationDescriptors.first(where: { $0.aliases.contains(property) }) else {
        throw unsupportedProperty(property, view: view)
    }

    let changes = {
        do {
            LoupeMutationAnimationErrorBox.clear()
            try descriptor.apply(view, value)
            view.setNeedsDisplay()
            if layout {
                view.setNeedsLayout()
                view.superview?.setNeedsLayout()
                view.layoutIfNeeded()
                view.superview?.layoutIfNeeded()
            }
        } catch {
            LoupeMutationAnimationErrorBox.current = error
        }
    }

    guard let animation else {
        LoupeMutationAnimationErrorBox.clear()
        changes()
        if let error = LoupeMutationAnimationErrorBox.take() {
            throw error
        }
        return
    }

    UIView.animate(
        withDuration: animation.duration,
        delay: animation.delay,
        options: animationOptions(animation.curve),
        animations: changes
    )
    if let error = LoupeMutationAnimationErrorBox.take() {
        throw error
    }
}

@MainActor
private enum LoupeMutationAnimationErrorBox {
    static var current: Error?

    static func take() -> Error? {
        let error = current
        current = nil
        return error
    }

    static func clear() {
        current = nil
    }
}

private func animationOptions(_ curve: String) -> UIView.AnimationOptions {
    switch curve.lowercased() {
    case "linear":
        return [.curveLinear, .beginFromCurrentState]
    case "easein":
        return [.curveEaseIn, .beginFromCurrentState]
    case "easeout":
        return [.curveEaseOut, .beginFromCurrentState]
    default:
        return [.curveEaseInOut, .beginFromCurrentState]
    }
}

private func mutationPropertyValue(_ property: String, in node: LoupeNode) -> LoupeMutationValue? {
    switch normalizedMutationProperty(property) {
    case "frame":
        return node.frame.map(LoupeMutationValue.rect)
    case "alpha", "style.alpha", "uikit.alpha":
        return node.style?.alpha.map(LoupeMutationValue.double)
    case "hidden", "ishidden", "uikit.ishidden":
        return .bool(!node.isVisible)
    case "backgroundcolor", "style.backgroundcolor":
        return node.style?.backgroundColor.map(LoupeMutationValue.color)
    case "text", "label.text", "textfield.text", "textview.text", "uikit.text":
        return node.text.map(LoupeMutationValue.string)
    case "placeholder", "textfield.placeholder", "searchbar.placeholder":
        return node.placeholder.map(LoupeMutationValue.string)
    case "accessibility.label", "accessibilitylabel", "label":
        return node.accessibility?.label.map(LoupeMutationValue.string) ?? node.label.map(LoupeMutationValue.string)
    case "accessibility.value", "accessibilityvalue":
        return node.accessibility?.value.map(LoupeMutationValue.string) ?? node.value.map(LoupeMutationValue.string)
    case "accessibility.hint", "accessibilityhint":
        return node.accessibility?.hint.map(LoupeMutationValue.string)
    case "accessibility.identifier", "accessibilityidentifier", "testid":
        return node.accessibility?.identifier.map(LoupeMutationValue.string) ?? node.testID.map(LoupeMutationValue.string)
    case "layout.translatesautoresizingmaskintoconstraints", "translatesautoresizingmaskintoconstraints":
        return node.uiKit?.layout.map { .bool($0.translatesAutoresizingMaskIntoConstraints) }
    case "layout.hugging.horizontal":
        return node.uiKit?.layout.map { .double($0.hugging.horizontal) }
    case "layout.hugging.vertical":
        return node.uiKit?.layout.map { .double($0.hugging.vertical) }
    case "layout.compressionresistance.horizontal":
        return node.uiKit?.layout.map { .double($0.compressionResistance.horizontal) }
    case "layout.compressionresistance.vertical":
        return node.uiKit?.layout.map { .double($0.compressionResistance.vertical) }
    case "stack.axis", "stackview.axis":
        return node.uiKit?.stackView.map { .string($0.axis) }
    case "stack.alignment", "stackview.alignment":
        return node.uiKit?.stackView.map { .string($0.alignment) }
    case "stack.distribution", "stackview.distribution":
        return node.uiKit?.stackView.map { .string($0.distribution) }
    case "stack.spacing", "stackview.spacing":
        return node.uiKit?.stackView.map { .double($0.spacing) }
    case "stack.layoutmarginsrelativearrangement", "stackview.layoutmarginsrelativearrangement":
        return node.uiKit?.stackView.map { .bool($0.isLayoutMarginsRelativeArrangement) }
    default:
        return nil
    }
}

private func mutationValuesApproximatelyEqual(_ requested: LoupeMutationValue, _ effective: LoupeMutationValue) -> Bool {
    switch (requested, effective) {
    case let (.bool(lhs), .bool(rhs)):
        return lhs == rhs
    case let (.int(lhs), .int(rhs)):
        return lhs == rhs
    case let (.double(lhs), .double(rhs)):
        return abs(lhs - rhs) < 0.5
    case let (.string(lhs), .string(rhs)):
        return lhs == rhs
    case let (.color(lhs), .color(rhs)):
        return abs(lhs.red - rhs.red) < 0.01
            && abs(lhs.green - rhs.green) < 0.01
            && abs(lhs.blue - rhs.blue) < 0.01
            && abs(lhs.alpha - rhs.alpha) < 0.01
    case let (.point(lhs), .point(rhs)):
        return abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    case let (.size(lhs), .size(rhs)):
        return abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
    case let (.rect(lhs), .rect(rhs)):
        return abs(lhs.x - rhs.x) < 0.5
            && abs(lhs.y - rhs.y) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    default:
        return false
    }
}

private struct LoupeMutationDescriptor {
    var property: String
    var aliases: Set<String>
    var apply: @MainActor (UIView, LoupeMutationValue) throws -> Void
}

@MainActor
private var mutationDescriptors: [LoupeMutationDescriptor] {
    viewMutationDescriptors
        + layerMutationDescriptors
        + accessibilityMutationDescriptors
        + textMutationDescriptors
        + controlMutationDescriptors
        + scrollMutationDescriptors
        + stackMutationDescriptors
}

private func mutation(
    _ aliases: [String],
    apply: @escaping @MainActor (UIView, LoupeMutationValue) throws -> Void
) -> LoupeMutationDescriptor {
    let normalizedAliases = aliases.map(normalizedMutationProperty)
    return LoupeMutationDescriptor(
        property: normalizedAliases.first ?? "",
        aliases: Set(normalizedAliases),
        apply: apply
    )
}

@MainActor
private var viewMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["frame"]) { view, value in
            view.frame = try frameInSuperview(try rectValue(value), for: view)
        },
        mutation(["bounds"]) { view, value in
            view.bounds = cgRect(try rectValue(value))
        },
        mutation(["center"]) { view, value in
            view.center = try pointInSuperview(try pointValue(value), for: view)
        },
        mutation(["alpha", "style.alpha", "uiKit.alpha"]) { view, value in
            view.alpha = CGFloat(try doubleValue(value))
        },
        mutation(["hidden", "isHidden", "uiKit.isHidden"]) { view, value in
            view.isHidden = try boolValue(value)
        },
        mutation(["opaque", "isOpaque", "uiKit.isOpaque"]) { view, value in
            view.isOpaque = try boolValue(value)
        },
        mutation(["clipsToBounds", "masksToBounds", "uiKit.clipsToBounds"]) { view, value in
            let bool = try boolValue(value)
            view.clipsToBounds = bool
            view.layer.masksToBounds = bool
        },
        mutation(["userInteractionEnabled", "isUserInteractionEnabled", "uiKit.userInteractionEnabled"]) { view, value in
            view.isUserInteractionEnabled = try boolValue(value)
        },
        mutation(["backgroundColor", "style.backgroundColor"]) { view, value in
            view.backgroundColor = try uiColor(value)
        },
        mutation(["tintColor"]) { view, value in
            view.tintColor = try uiColor(value)
        },
        mutation(["contentMode", "uiKit.contentMode"]) { view, value in
            view.contentMode = try contentMode(try stringValue(value))
        },
        mutation(["tag", "uiKit.tag"]) { view, value in
            view.tag = try intValue(value)
        },
        mutation(["layout.translatesAutoresizingMaskIntoConstraints", "translatesAutoresizingMaskIntoConstraints"]) { view, value in
            view.translatesAutoresizingMaskIntoConstraints = try boolValue(value)
        },
        mutation(["layout.hugging.horizontal"]) { view, value in
            view.setContentHuggingPriority(UILayoutPriority(Float(try doubleValue(value))), for: .horizontal)
        },
        mutation(["layout.hugging.vertical"]) { view, value in
            view.setContentHuggingPriority(UILayoutPriority(Float(try doubleValue(value))), for: .vertical)
        },
        mutation(["layout.compressionResistance.horizontal"]) { view, value in
            view.setContentCompressionResistancePriority(UILayoutPriority(Float(try doubleValue(value))), for: .horizontal)
        },
        mutation(["layout.compressionResistance.vertical"]) { view, value in
            view.setContentCompressionResistancePriority(UILayoutPriority(Float(try doubleValue(value))), for: .vertical)
        }
    ]
}

@MainActor
private var layerMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["borderColor", "layer.borderColor", "style.borderColor"]) { view, value in
            view.layer.borderColor = try uiColor(value).cgColor
        },
        mutation(["borderWidth", "layer.borderWidth", "style.borderWidth"]) { view, value in
            view.layer.borderWidth = CGFloat(try doubleValue(value))
        },
        mutation(["cornerRadius", "layer.cornerRadius", "style.cornerRadius"]) { view, value in
            view.layer.cornerRadius = CGFloat(try doubleValue(value))
        },
        mutation(["shadowColor", "layer.shadowColor"]) { view, value in
            view.layer.shadowColor = try uiColor(value).cgColor
        },
        mutation(["shadowOpacity", "layer.shadowOpacity"]) { view, value in
            view.layer.shadowOpacity = Float(try doubleValue(value))
        },
        mutation(["shadowRadius", "layer.shadowRadius"]) { view, value in
            view.layer.shadowRadius = CGFloat(try doubleValue(value))
        },
        mutation(["shadowOffset", "layer.shadowOffset"]) { view, value in
            let size = try sizeValue(value)
            view.layer.shadowOffset = CGSize(width: size.width, height: size.height)
        },
        mutation(["layer.opacity"]) { view, value in
            view.layer.opacity = Float(try doubleValue(value))
        },
        mutation(["layer.zPosition", "zPosition"]) { view, value in
            view.layer.zPosition = CGFloat(try doubleValue(value))
        }
    ]
}

@MainActor
private var accessibilityMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["accessibility.identifier", "accessibilityIdentifier", "testID"]) { view, value in
            view.accessibilityIdentifier = try stringValue(value)
        },
        mutation(["accessibility.label", "accessibilityLabel", "label"]) { view, value in
            view.accessibilityLabel = try stringValue(value)
        },
        mutation(["accessibility.value", "accessibilityValue"]) { view, value in
            view.accessibilityValue = try stringValue(value)
        },
        mutation(["accessibility.hint", "accessibilityHint"]) { view, value in
            view.accessibilityHint = try stringValue(value)
        },
        mutation(["accessibility.isElement", "isAccessibilityElement"]) { view, value in
            view.isAccessibilityElement = try boolValue(value)
        }
    ]
}

@MainActor
private var textMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["text", "label.text", "textField.text", "textView.text", "uiKit.text"]) { view, value in
            try setText(try stringValue(value), on: view)
        },
        mutation(["placeholder", "textField.placeholder", "searchBar.placeholder"]) { view, value in
            if let textField = view as? UITextField {
                textField.placeholder = try stringValue(value)
            } else if let searchBar = view as? UISearchBar {
                searchBar.placeholder = try stringValue(value)
            } else {
                throw unsupportedProperty("placeholder", view: view)
            }
        },
        mutation(["title", "button.title"]) { view, value in
            guard let button = view as? UIButton else {
                throw unsupportedProperty("title", view: view)
            }
            button.setTitle(try stringValue(value), for: .normal)
        },
        mutation(["textColor", "style.textColor"]) { view, value in
            try setTextColor(try uiColor(value), on: view)
        },
        mutation(["fontSize", "font.size", "style.fontSize"]) { view, value in
            try setFontSize(CGFloat(try doubleValue(value)), on: view)
        },
        mutation(["textAlignment", "label.textAlignment", "textField.textAlignment", "textView.textAlignment"]) { view, value in
            try setTextAlignment(try stringValue(value), on: view)
        },
        mutation(["numberOfLines", "label.numberOfLines"]) { view, value in
            guard let label = view as? UILabel else {
                throw unsupportedProperty("numberOfLines", view: view)
            }
            label.numberOfLines = try intValue(value)
        },
        mutation(["lineBreakMode", "label.lineBreakMode", "button.lineBreakMode"]) { view, value in
            try setLineBreakMode(try stringValue(value), on: view)
        },
        mutation(["adjustsFontSizeToFitWidth", "label.adjustsFontSizeToFitWidth", "textField.adjustsFontSizeToFitWidth"]) { view, value in
            if let label = view as? UILabel {
                label.adjustsFontSizeToFitWidth = try boolValue(value)
            } else if let textField = view as? UITextField {
                textField.adjustsFontSizeToFitWidth = try boolValue(value)
            } else {
                throw unsupportedProperty("adjustsFontSizeToFitWidth", view: view)
            }
        },
        mutation(["minimumScaleFactor", "label.minimumScaleFactor"]) { view, value in
            guard let label = view as? UILabel else {
                throw unsupportedProperty("minimumScaleFactor", view: view)
            }
            label.minimumScaleFactor = CGFloat(try doubleValue(value))
        },
        mutation(["secureTextEntry", "textField.isSecureTextEntry"]) { view, value in
            guard let textField = view as? UITextField else {
                throw unsupportedProperty("secureTextEntry", view: view)
            }
            textField.isSecureTextEntry = try boolValue(value)
        }
    ]
}

@MainActor
private var controlMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["enabled", "isEnabled", "control.enabled"]) { view, value in
            guard let control = view as? UIControl else {
                throw unsupportedProperty("enabled", view: view)
            }
            control.isEnabled = try boolValue(value)
        },
        mutation(["selected", "isSelected", "control.selected"]) { view, value in
            guard let control = view as? UIControl else {
                throw unsupportedProperty("selected", view: view)
            }
            control.isSelected = try boolValue(value)
        },
        mutation(["highlighted", "isHighlighted", "control.highlighted"]) { view, value in
            guard let control = view as? UIControl else {
                throw unsupportedProperty("highlighted", view: view)
            }
            control.isHighlighted = try boolValue(value)
        },
        mutation(["switch.isOn", "switchControl.isOn", "uiKit.switch.isOn", "uiKit.switchControl.isOn"]) { view, value in
            guard let control = view as? UISwitch else {
                throw unsupportedProperty("switch.isOn", view: view)
            }
            control.setOn(try boolValue(value), animated: false)
            control.sendActions(for: .valueChanged)
        },
        mutation(["slider.value", "uiKit.slider.value"]) { view, value in
            guard let control = view as? UISlider else {
                throw unsupportedProperty("slider.value", view: view)
            }
            control.value = Float(try doubleValue(value))
            control.sendActions(for: .valueChanged)
        },
        mutation(["slider.minimumValue"]) { view, value in
            guard let control = view as? UISlider else {
                throw unsupportedProperty("slider.minimumValue", view: view)
            }
            control.minimumValue = Float(try doubleValue(value))
        },
        mutation(["slider.maximumValue"]) { view, value in
            guard let control = view as? UISlider else {
                throw unsupportedProperty("slider.maximumValue", view: view)
            }
            control.maximumValue = Float(try doubleValue(value))
        },
        mutation(["stepper.value", "uiKit.stepper.value"]) { view, value in
            guard let control = view as? UIStepper else {
                throw unsupportedProperty("stepper.value", view: view)
            }
            control.value = try doubleValue(value)
            control.sendActions(for: .valueChanged)
        },
        mutation(["stepper.minimumValue"]) { view, value in
            guard let control = view as? UIStepper else {
                throw unsupportedProperty("stepper.minimumValue", view: view)
            }
            control.minimumValue = try doubleValue(value)
        },
        mutation(["stepper.maximumValue"]) { view, value in
            guard let control = view as? UIStepper else {
                throw unsupportedProperty("stepper.maximumValue", view: view)
            }
            control.maximumValue = try doubleValue(value)
        },
        mutation(["stepper.stepValue"]) { view, value in
            guard let control = view as? UIStepper else {
                throw unsupportedProperty("stepper.stepValue", view: view)
            }
            control.stepValue = try doubleValue(value)
        },
        mutation(["segmentedControl.selectedSegmentIndex", "uiKit.segmentedControl.selectedSegmentIndex"]) { view, value in
            guard let control = view as? UISegmentedControl else {
                throw unsupportedProperty("segmentedControl.selectedSegmentIndex", view: view)
            }
            let index = try intValue(value)
            guard index == UISegmentedControl.noSegment || (index >= 0 && index < control.numberOfSegments) else {
                throw LoupeMutationError(code: "invalid_value", message: "Segment index \(index) is outside available segments.")
            }
            control.selectedSegmentIndex = index
            control.sendActions(for: .valueChanged)
        },
        mutation(["pageControl.currentPage", "uiKit.pageControl.currentPage"]) { view, value in
            guard let control = view as? UIPageControl else {
                throw unsupportedProperty("pageControl.currentPage", view: view)
            }
            control.currentPage = try intValue(value)
            control.sendActions(for: .valueChanged)
        },
        mutation(["pageControl.numberOfPages"]) { view, value in
            guard let control = view as? UIPageControl else {
                throw unsupportedProperty("pageControl.numberOfPages", view: view)
            }
            control.numberOfPages = try intValue(value)
        },
        mutation(["progressView.progress", "progressView.value", "uiKit.progress.progress", "uiKit.progressView.value"]) { view, value in
            guard let progressView = view as? UIProgressView else {
                throw unsupportedProperty("progressView.progress", view: view)
            }
            progressView.progress = Float(try doubleValue(value))
        },
        mutation(["datePicker.date"]) { view, value in
            guard let datePicker = view as? UIDatePicker else {
                throw unsupportedProperty("datePicker.date", view: view)
            }
            datePicker.date = try dateValue(value)
            datePicker.sendActions(for: .valueChanged)
        },
        mutation(["datePicker.countDownDuration"]) { view, value in
            guard let datePicker = view as? UIDatePicker else {
                throw unsupportedProperty("datePicker.countDownDuration", view: view)
            }
            datePicker.countDownDuration = try doubleValue(value)
            datePicker.sendActions(for: .valueChanged)
        },
        mutation(["activityIndicator.animating", "activityIndicator.isAnimating"]) { view, value in
            guard let activityIndicator = view as? UIActivityIndicatorView else {
                throw unsupportedProperty("activityIndicator.animating", view: view)
            }
            if try boolValue(value) {
                activityIndicator.startAnimating()
            } else {
                activityIndicator.stopAnimating()
            }
        },
        mutation(["pickerView.selectedRow"]) { view, value in
            guard let pickerView = view as? UIPickerView else {
                throw unsupportedProperty("pickerView.selectedRow", view: view)
            }
            let point = try pointValue(value)
            pickerView.selectRow(Int(point.y), inComponent: Int(point.x), animated: false)
        }
    ]
}

@MainActor
private var scrollMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["contentOffset", "scrollView.contentOffset"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("contentOffset", view: view)
            }
            let point = try pointValue(value)
            scrollView.setContentOffset(CGPoint(x: point.x, y: point.y), animated: false)
        },
        mutation(["contentSize", "scrollView.contentSize"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("contentSize", view: view)
            }
            let size = try sizeValue(value)
            scrollView.contentSize = CGSize(width: size.width, height: size.height)
        },
        mutation(["contentInset", "scrollView.contentInset"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("contentInset", view: view)
            }
            scrollView.contentInset = try edgeInsetsValue(value)
        },
        mutation(["scrollIndicatorInsets", "scrollView.scrollIndicatorInsets"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("scrollIndicatorInsets", view: view)
            }
            scrollView.scrollIndicatorInsets = try edgeInsetsValue(value)
        },
        mutation(["scrollEnabled", "isScrollEnabled", "scrollView.isScrollEnabled"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("scrollEnabled", view: view)
            }
            scrollView.isScrollEnabled = try boolValue(value)
        },
        mutation(["pagingEnabled", "isPagingEnabled", "scrollView.isPagingEnabled"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("pagingEnabled", view: view)
            }
            scrollView.isPagingEnabled = try boolValue(value)
        },
        mutation(["showsHorizontalScrollIndicator"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("showsHorizontalScrollIndicator", view: view)
            }
            scrollView.showsHorizontalScrollIndicator = try boolValue(value)
        },
        mutation(["showsVerticalScrollIndicator"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("showsVerticalScrollIndicator", view: view)
            }
            scrollView.showsVerticalScrollIndicator = try boolValue(value)
        }
    ]
}

@MainActor
private var stackMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["stack.axis", "stackView.axis"]) { view, value in
            guard let stackView = view as? UIStackView else {
                throw unsupportedProperty("stack.axis", view: view)
            }
            stackView.axis = try layoutConstraintAxis(try stringValue(value))
        },
        mutation(["stack.alignment", "stackView.alignment"]) { view, value in
            guard let stackView = view as? UIStackView else {
                throw unsupportedProperty("stack.alignment", view: view)
            }
            stackView.alignment = try stackAlignment(try stringValue(value))
        },
        mutation(["stack.distribution", "stackView.distribution"]) { view, value in
            guard let stackView = view as? UIStackView else {
                throw unsupportedProperty("stack.distribution", view: view)
            }
            stackView.distribution = try stackDistribution(try stringValue(value))
        },
        mutation(["stack.spacing", "stackView.spacing"]) { view, value in
            guard let stackView = view as? UIStackView else {
                throw unsupportedProperty("stack.spacing", view: view)
            }
            stackView.spacing = CGFloat(try doubleValue(value))
        },
        mutation(["stack.layoutMarginsRelativeArrangement", "stackView.layoutMarginsRelativeArrangement"]) { view, value in
            guard let stackView = view as? UIStackView else {
                throw unsupportedProperty("stack.layoutMarginsRelativeArrangement", view: view)
            }
            stackView.isLayoutMarginsRelativeArrangement = try boolValue(value)
        }
    ]
}

private func normalizedMutationProperty(_ property: String) -> String {
    property
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "uiKit.", with: "uikit.")
        .lowercased()
}

@MainActor
private func unsupportedProperty(_ property: String, view: UIView) -> LoupeMutationError {
    LoupeMutationError(
        code: "unsupported_property",
        message: "Property '\(property)' is not supported for \(typeName(of: view))."
    )
}

private func boolValue(_ value: LoupeMutationValue) throws -> Bool {
    switch value {
    case let .bool(value):
        return value
    case let .int(value):
        return value != 0
    case let .double(value):
        return value != 0
    case let .string(value):
        if ["true", "yes", "1"].contains(value.lowercased()) { return true }
        if ["false", "no", "0"].contains(value.lowercased()) { return false }
        throw LoupeMutationError(code: "invalid_value", message: "Expected a boolean value.")
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Expected a boolean value.")
    }
}

private func intValue(_ value: LoupeMutationValue) throws -> Int {
    switch value {
    case let .int(value):
        return value
    case let .double(value):
        return Int(value)
    case let .string(value):
        guard let int = Int(value) else {
            throw LoupeMutationError(code: "invalid_value", message: "Expected an integer value.")
        }
        return int
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Expected an integer value.")
    }
}

private func doubleValue(_ value: LoupeMutationValue) throws -> Double {
    switch value {
    case let .double(value):
        guard value.isFinite else { break }
        return value
    case let .int(value):
        return Double(value)
    case let .string(value):
        guard let double = Double(value), double.isFinite else { break }
        return double
    default:
        break
    }
    throw LoupeMutationError(code: "invalid_value", message: "Expected a numeric value.")
}

private func stringValue(_ value: LoupeMutationValue) throws -> String {
    switch value {
    case let .string(value):
        return value
    case let .bool(value):
        return value ? "true" : "false"
    case let .int(value):
        return String(value)
    case let .double(value):
        return String(value)
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Expected a string value.")
    }
}

private func rectValue(_ value: LoupeMutationValue) throws -> LoupeRect {
    guard case let .rect(rect) = value else {
        throw LoupeMutationError(code: "invalid_value", message: "Expected a rect value.")
    }
    return rect
}

private func pointValue(_ value: LoupeMutationValue) throws -> LoupePoint {
    guard case let .point(point) = value else {
        throw LoupeMutationError(code: "invalid_value", message: "Expected a point value.")
    }
    return point
}

private func sizeValue(_ value: LoupeMutationValue) throws -> LoupeSize {
    guard case let .size(size) = value else {
        throw LoupeMutationError(code: "invalid_value", message: "Expected a size value.")
    }
    return size
}

private func uiColor(_ value: LoupeMutationValue) throws -> UIColor {
    guard case let .color(color) = value else {
        throw LoupeMutationError(code: "invalid_value", message: "Expected a color value.")
    }
    return UIColor(
        red: CGFloat(color.red),
        green: CGFloat(color.green),
        blue: CGFloat(color.blue),
        alpha: CGFloat(color.alpha)
    )
}

@MainActor
private func setText(_ text: String, on view: UIView) throws {
    if let label = view as? UILabel {
        label.text = text
    } else if let textField = view as? UITextField {
        textField.text = text
        textField.sendActions(for: .editingChanged)
    } else if let textView = view as? UITextView {
        textView.text = text
    } else if let button = view as? UIButton {
        button.setTitle(text, for: .normal)
    } else if let searchBar = view as? UISearchBar {
        searchBar.text = text
    } else {
        throw unsupportedProperty("text", view: view)
    }
}

@MainActor
private func setTextColor(_ color: UIColor, on view: UIView) throws {
    if let label = view as? UILabel {
        label.textColor = color
    } else if let textField = view as? UITextField {
        textField.textColor = color
    } else if let textView = view as? UITextView {
        textView.textColor = color
    } else if let button = view as? UIButton {
        button.setTitleColor(color, for: .normal)
    } else {
        throw unsupportedProperty("textColor", view: view)
    }
}

@MainActor
private func setFontSize(_ size: CGFloat, on view: UIView) throws {
    if let label = view as? UILabel {
        label.font = label.font.withSize(size)
    } else if let textField = view as? UITextField, let font = textField.font {
        textField.font = font.withSize(size)
    } else if let textView = view as? UITextView {
        textView.font = textView.font?.withSize(size) ?? UIFont.systemFont(ofSize: size)
    } else if let button = view as? UIButton, let font = button.titleLabel?.font {
        button.titleLabel?.font = font.withSize(size)
    } else {
        throw unsupportedProperty("fontSize", view: view)
    }
}

@MainActor
private func setTextAlignment(_ rawValue: String, on view: UIView) throws {
    let alignment = try textAlignment(rawValue)
    if let label = view as? UILabel {
        label.textAlignment = alignment
    } else if let textField = view as? UITextField {
        textField.textAlignment = alignment
    } else if let textView = view as? UITextView {
        textView.textAlignment = alignment
    } else {
        throw unsupportedProperty("textAlignment", view: view)
    }
}

@MainActor
private func setLineBreakMode(_ rawValue: String, on view: UIView) throws {
    let mode = try lineBreakMode(rawValue)
    if let label = view as? UILabel {
        label.lineBreakMode = mode
    } else if let button = view as? UIButton {
        button.titleLabel?.lineBreakMode = mode
    } else {
        throw unsupportedProperty("lineBreakMode", view: view)
    }
}

@MainActor
private func frameInSuperview(_ rect: LoupeRect, for view: UIView) -> CGRect {
    let screenRect = cgRect(rect)
    guard let superview = view.superview, view.window != nil else {
        return screenRect
    }
    return superview.convert(screenRect, from: nil)
}

@MainActor
private func pointInSuperview(_ point: LoupePoint, for view: UIView) -> CGPoint {
    let screenPoint = CGPoint(x: point.x, y: point.y)
    guard let superview = view.superview, view.window != nil else {
        return screenPoint
    }
    return superview.convert(screenPoint, from: nil)
}

private func cgRect(_ rect: LoupeRect) -> CGRect {
    CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
}

private func contentMode(_ rawValue: String) throws -> UIView.ContentMode {
    switch rawValue.lowercased() {
    case "scaletofill": return .scaleToFill
    case "scaleaspectfit": return .scaleAspectFit
    case "scaleaspectfill": return .scaleAspectFill
    case "redraw": return .redraw
    case "center": return .center
    case "top": return .top
    case "bottom": return .bottom
    case "left": return .left
    case "right": return .right
    case "topleft": return .topLeft
    case "topright": return .topRight
    case "bottomleft": return .bottomLeft
    case "bottomright": return .bottomRight
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Unsupported contentMode: \(rawValue)")
    }
}

private func textAlignment(_ rawValue: String) throws -> NSTextAlignment {
    switch rawValue.lowercased() {
    case "left": return .left
    case "center": return .center
    case "right": return .right
    case "justified": return .justified
    case "natural": return .natural
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Unsupported textAlignment: \(rawValue)")
    }
}

private func lineBreakMode(_ rawValue: String) throws -> NSLineBreakMode {
    switch rawValue.lowercased() {
    case "bywordwrapping", "word": return .byWordWrapping
    case "bycharwrapping", "char": return .byCharWrapping
    case "byclipping", "clip": return .byClipping
    case "bytruncatinghead", "head": return .byTruncatingHead
    case "bytruncatingtail", "tail": return .byTruncatingTail
    case "bytruncatingmiddle", "middle": return .byTruncatingMiddle
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Unsupported lineBreakMode: \(rawValue)")
    }
}

private func dateValue(_ value: LoupeMutationValue) throws -> Date {
    switch value {
    case let .double(value):
        return Date(timeIntervalSince1970: value)
    case let .int(value):
        return Date(timeIntervalSince1970: TimeInterval(value))
    case let .string(value):
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else {
            throw LoupeMutationError(code: "invalid_value", message: "Expected an ISO-8601 date or Unix timestamp.")
        }
        return date
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Expected an ISO-8601 date or Unix timestamp.")
    }
}

private func edgeInsetsValue(_ value: LoupeMutationValue) throws -> UIEdgeInsets {
    let rect = try rectValue(value)
    return UIEdgeInsets(top: rect.x, left: rect.y, bottom: rect.width, right: rect.height)
}

private func layoutConstraintAxis(_ rawValue: String) throws -> NSLayoutConstraint.Axis {
    switch rawValue.lowercased() {
    case "horizontal", "h": return .horizontal
    case "vertical", "v": return .vertical
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Unsupported stack axis: \(rawValue)")
    }
}

private func stackAlignment(_ rawValue: String) throws -> UIStackView.Alignment {
    switch rawValue.lowercased() {
    case "fill": return .fill
    case "leading", "top": return .leading
    case "firstbaseline", "firstBaseline": return .firstBaseline
    case "center": return .center
    case "trailing", "bottom": return .trailing
    case "lastbaseline", "lastBaseline": return .lastBaseline
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Unsupported stack alignment: \(rawValue)")
    }
}

private func stackDistribution(_ rawValue: String) throws -> UIStackView.Distribution {
    switch rawValue.lowercased() {
    case "fill": return .fill
    case "fillequally", "fillEqually": return .fillEqually
    case "fillproportionally", "fillProportionally": return .fillProportionally
    case "equalspacing", "equalSpacing": return .equalSpacing
    case "equalcentering", "equalCentering": return .equalCentering
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Unsupported stack distribution: \(rawValue)")
    }
}

func makeLoupeJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

@MainActor
private func frameInScreen(for view: UIView) -> LoupeRect? {
    guard view.window != nil else { return nil }
    return loupeRect(from: view.convert(view.bounds, to: nil))
}

private func loupeRect(from rect: CGRect) -> LoupeRect {
    LoupeRect(
        x: finiteDouble(rect.origin.x.doubleValue) ?? 0,
        y: finiteDouble(rect.origin.y.doubleValue) ?? 0,
        width: finiteDouble(rect.size.width.doubleValue) ?? 0,
        height: finiteDouble(rect.size.height.doubleValue) ?? 0
    )
}

@MainActor
private func role(for view: UIView) -> String? {
    if view is UIButton { return "button" }
    if view is UITextField { return "textField" }
    if view is UITextView { return "textView" }
    if view is UISwitch { return "switch" }
    if view is UISlider { return "slider" }
    if view is UIStepper { return "stepper" }
    if view is UISegmentedControl { return "segmentedControl" }
    if view is UIDatePicker { return "datePicker" }
    if view is UIPageControl { return "pageControl" }
    if view is UIProgressView { return "progress" }
    if view is UIActivityIndicatorView { return "activityIndicator" }
    if view is UICollectionView { return "collectionView" }
    if view is UITableView { return "tableView" }
    if view is UIPickerView { return "pickerView" }
    if view is UITabBar { return "tabBar" }
    if view is UIToolbar { return "toolbar" }
    if view is UINavigationBar { return "navigationBar" }
    #if canImport(WebKit)
    if view is WKWebView { return "webView" }
    #endif
    if view is UITableViewCell || view is UICollectionViewCell { return "cell" }
    if view is UIImageView { return "image" }
    if view is UILabel { return "staticText" }
    if view is UIScrollView { return "scrollView" }

    if view.accessibilityTraits.contains(.button) { return "button" }
    if view.accessibilityTraits.contains(.link) { return "link" }
    if view.accessibilityTraits.contains(.image) { return "image" }
    if view.accessibilityTraits.contains(.staticText) { return "staticText" }
    if view.accessibilityTraits.contains(.searchField) { return "searchField" }

    return nil
}

@MainActor
private func text(for view: UIView) -> String? {
    if let label = view as? UILabel {
        return label.text
    }

    if let button = view as? UIButton {
        return button.title(for: button.state) ?? button.currentTitle
    }

    if let textField = view as? UITextField {
        return textField.text
    }

    if let textView = view as? UITextView {
        return textView.text
    }

    if let segmentedControl = view as? UISegmentedControl {
        return (0..<segmentedControl.numberOfSegments)
            .compactMap { segmentedControl.titleForSegment(at: $0) }
            .joined(separator: " ")
    }

    return nil
}

@MainActor
private func renderedText(for view: UIView) -> String? {
    text(for: view)
}

@MainActor
private func semanticText(for view: UIView) -> String? {
    let candidates = [
        text(for: view),
        view.accessibilityLabel,
        view.accessibilityValue,
        descendantText(in: view),
    ]
    return candidates
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
}

@MainActor
private func placeholder(for view: UIView) -> String? {
    (view as? UITextField)?.placeholder
}

@MainActor
private func isEnabled(_ view: UIView) -> Bool {
    if let control = view as? UIControl {
        return control.isEnabled
    }
    return true
}

@MainActor
private func isInteractive(_ view: UIView) -> Bool {
    if view is UIControl { return true }
    if let recognizers = view.gestureRecognizers, !recognizers.isEmpty {
        return true
    }
    if view.accessibilityTraits.contains(.button)
        || view.accessibilityTraits.contains(.link)
        || view.accessibilityTraits.contains(.adjustable)
        || view.accessibilityTraits.contains(.keyboardKey) {
        return true
    }
    return false
}

@MainActor
private func style(for view: UIView) -> LoupeStyle {
    LoupeStyle(
        alpha: finiteDouble(view.alpha.doubleValue),
        backgroundColor: loupeColor(from: view.backgroundColor, traitCollection: view.traitCollection),
        cornerRadius: finiteDouble(view.layer.cornerRadius.doubleValue),
        fontName: font(for: view)?.fontName,
        fontSize: font(for: view).flatMap { finiteDouble($0.pointSize.doubleValue) },
        textColor: loupeColor(from: textColor(for: view), traitCollection: view.traitCollection),
        borderColor: loupeColor(from: borderColor(for: view), traitCollection: view.traitCollection),
        borderWidth: finiteDouble(view.layer.borderWidth.doubleValue)
    )
}

@MainActor
private func font(for view: UIView) -> UIFont? {
    if let label = view as? UILabel {
        return label.font
    }
    if let button = view as? UIButton {
        return button.titleLabel?.font
    }
    if let textField = view as? UITextField {
        return textField.font
    }
    if let textView = view as? UITextView {
        return textView.font
    }
    return nil
}

@MainActor
private func textColor(for view: UIView) -> UIColor? {
    if let label = view as? UILabel {
        return label.textColor
    }
    if let button = view as? UIButton {
        return button.titleColor(for: button.state) ?? button.currentTitleColor
    }
    if let textField = view as? UITextField {
        return textField.textColor
    }
    if let textView = view as? UITextView {
        return textView.textColor
    }
    return nil
}

@MainActor
private func borderColor(for view: UIView) -> UIColor? {
    guard let cgColor = view.layer.borderColor else {
        return nil
    }
    return UIColor(cgColor: cgColor)
}

@MainActor
private func loupeColor(from color: UIColor?, traitCollection: UITraitCollection) -> LoupeColor? {
    guard let color else { return nil }

    let resolved = color.resolvedColor(with: traitCollection)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
        return nil
    }

    return LoupeColor(
        red: finiteDouble(red.doubleValue) ?? 0,
        green: finiteDouble(green.doubleValue) ?? 0,
        blue: finiteDouble(blue.doubleValue) ?? 0,
        alpha: finiteDouble(alpha.doubleValue) ?? 0
    )
}

private func finiteDouble(_ value: Double) -> Double? {
    value.isFinite ? value : nil
}

private func stringMetadata(
    _ key: String,
    from metadata: [String: LoupeMetadataValue]
) -> String? {
    guard case let .string(value) = metadata[key] else {
        return nil
    }
    return value
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func mergedMetadata(
    _ base: [String: LoupeMetadataValue],
    with overlay: [String: LoupeMetadataValue]
) -> [String: LoupeMetadataValue] {
    var result = base
    result.merge(overlay) { _, new in new }
    return result
}

private func accessibilityIdentifier(for element: NSObject) -> String? {
    if let identifier = (element as? UIAccessibilityIdentification)?.accessibilityIdentifier {
        return nonEmpty(identifier)
    }

    let selector = NSSelectorFromString("accessibilityIdentifier")
    guard element.responds(to: selector) else {
        return nil
    }

    return nonEmpty(element.perform(selector)?.takeUnretainedValue() as? String)
}

private func treeParentRef(for sourceRef: String, tree: LoupeAccessibilityTree) -> String? {
    let parentRef = "ax-\(sourceRef)"
    if tree.nodes[parentRef] != nil {
        return parentRef
    }
    return nil
}

private func validActivationPoint(_ point: LoupePoint?, frame: LoupeRect?) -> LoupePoint? {
    guard let point, let frame, !frame.isEmpty else {
        return nil
    }

    guard point.x >= frame.x, point.x <= frame.maxX, point.y >= frame.y, point.y <= frame.maxY else {
        return nil
    }

    return point
}

private func intersectsScreen(_ frame: LoupeRect, screen: LoupeSize) -> Bool {
    frame.maxX > 0 && frame.maxY > 0 && frame.x < screen.width && frame.y < screen.height
}

private func accessibilityRole(forTraits traits: [String]) -> String? {
    if traits.contains("button") { return "button" }
    if traits.contains("link") { return "link" }
    if traits.contains("image") { return "image" }
    if traits.contains("searchField") { return "searchField" }
    if traits.contains("keyboardKey") { return "keyboardKey" }
    if traits.contains("staticText") { return "staticText" }
    if traits.contains("adjustable") { return "adjustable" }
    return nil
}

private func isInteractiveAccessibilityTraits(_ traits: [String]) -> Bool {
    traits.contains("button")
        || traits.contains("link")
        || traits.contains("adjustable")
        || traits.contains("keyboardKey")
        || traits.contains("allowsDirectInteraction")
}

private func nativeAccessibilitySignature(for node: LoupeAccessibilityNode) -> String {
    let frame = node.frame.map {
        "\(Int($0.x.rounded())):\(Int($0.y.rounded())):\(Int($0.width.rounded())):\(Int($0.height.rounded()))"
    } ?? "nil"
    return [
        node.testID ?? "",
        node.label ?? "",
        node.value ?? "",
        node.role ?? "",
        frame
    ].joined(separator: "|")
}

private func accessibilityVisualOrder(
    _ lhs: LoupeAccessibilityNode?,
    _ rhs: LoupeAccessibilityNode?
) -> Bool {
    guard let lhsFrame = lhs?.frame else { return false }
    guard let rhsFrame = rhs?.frame else { return true }

    if abs(lhsFrame.y - rhsFrame.y) > 1 {
        return lhsFrame.y < rhsFrame.y
    }

    return lhsFrame.x < rhsFrame.x
}

private func typeName(of value: AnyObject) -> String {
    String(describing: type(of: value))
}

private func interfaceStyleName(_ style: UIUserInterfaceStyle) -> String {
    switch style {
    case .dark:
        return "dark"
    case .light:
        return "light"
    case .unspecified:
        return "unspecified"
    @unknown default:
        return "unknown"
    }
}

@MainActor
private func accessibility(for view: UIView) -> LoupeAccessibility {
    LoupeAccessibility(
        identifier: view.accessibilityIdentifier,
        label: view.accessibilityLabel,
        value: view.accessibilityValue,
        hint: view.accessibilityHint,
        traits: accessibilityTraits(view.accessibilityTraits),
        frame: frameInScreen(for: view),
        activationPoint: activationPoint(for: view),
        isElement: view.isAccessibilityElement
    )
}

@MainActor
private func runtimeProperties(for view: UIView) -> LoupeNodeRuntimeProperties {
    LoupeNodeRuntimeProperties(
        frameworkBundleIdentifier: Bundle(for: type(of: view)).bundleIdentifier
    )
}

@MainActor
private func activationPoint(for view: UIView) -> LoupePoint? {
    guard view.window != nil else {
        return nil
    }

    let point = view.accessibilityActivationPoint
    return LoupePoint(x: finiteDouble(Double(point.x)) ?? 0, y: finiteDouble(Double(point.y)) ?? 0)
}

@MainActor
private func uiKitProperties(for view: UIView) -> LoupeUIKitProperties {
    LoupeUIKitProperties(
        viewController: owningViewControllerName(for: view),
        className: typeName(of: view),
        tag: view.tag,
        alpha: finiteDouble(view.alpha.doubleValue) ?? 0,
        isHidden: view.isHidden,
        isOpaque: view.isOpaque,
        clipsToBounds: view.clipsToBounds,
        contentMode: contentModeName(view.contentMode),
        userInteractionEnabled: view.isUserInteractionEnabled,
        gestureRecognizers: view.gestureRecognizers?.map { typeName(of: $0) } ?? [],
        isFirstResponder: view.isFirstResponder,
        windowLevel: (view as? UIWindow).flatMap { finiteDouble($0.windowLevel.rawValue.doubleValue) },
        layout: layoutProperties(for: view),
        stackView: stackViewProperties(for: view),
        control: controlProperties(for: view),
        label: labelProperties(for: view),
        button: buttonProperties(for: view),
        textField: textFieldProperties(for: view),
        textView: textViewProperties(for: view),
        scrollView: scrollViewProperties(for: view),
        switchControl: switchProperties(for: view),
        slider: sliderProperties(for: view),
        stepper: stepperProperties(for: view),
        segmentedControl: segmentedControlProperties(for: view),
        datePicker: datePickerProperties(for: view),
        pageControl: pageControlProperties(for: view),
        progressView: progressViewProperties(for: view),
        activityIndicator: activityIndicatorProperties(for: view),
        imageView: imageViewProperties(for: view),
        pickerView: pickerViewProperties(for: view),
        tabBar: tabBarProperties(for: view),
        webView: webViewProperties(for: view)
    )
}

@MainActor
private func layoutProperties(for view: UIView) -> LoupeUILayoutProperties {
    LoupeUILayoutProperties(
        translatesAutoresizingMaskIntoConstraints: view.translatesAutoresizingMaskIntoConstraints,
        hugging: LoupeUILayoutPriorities(
            horizontal: finiteDouble(Double(view.contentHuggingPriority(for: .horizontal).rawValue)) ?? 0,
            vertical: finiteDouble(Double(view.contentHuggingPriority(for: .vertical).rawValue)) ?? 0
        ),
        compressionResistance: LoupeUILayoutPriorities(
            horizontal: finiteDouble(Double(view.contentCompressionResistancePriority(for: .horizontal).rawValue)) ?? 0,
            vertical: finiteDouble(Double(view.contentCompressionResistancePriority(for: .vertical).rawValue)) ?? 0
        ),
        constraints: view.constraints.prefix(20).map(layoutConstraintProperties),
        affectingHorizontalConstraints: view.constraintsAffectingLayout(for: .horizontal)
            .prefix(20)
            .map(layoutConstraintProperties),
        affectingVerticalConstraints: view.constraintsAffectingLayout(for: .vertical)
            .prefix(20)
            .map(layoutConstraintProperties)
    )
}

@MainActor
private func stackViewProperties(for view: UIView) -> LoupeUIStackViewProperties? {
    guard let stackView = view as? UIStackView else {
        return nil
    }
    return LoupeUIStackViewProperties(
        axis: layoutConstraintAxisName(stackView.axis),
        alignment: stackAlignmentName(stackView.alignment),
        distribution: stackDistributionName(stackView.distribution),
        spacing: finiteDouble(Double(stackView.spacing)) ?? 0,
        isBaselineRelativeArrangement: stackView.isBaselineRelativeArrangement,
        isLayoutMarginsRelativeArrangement: stackView.isLayoutMarginsRelativeArrangement,
        arrangedSubviewCount: stackView.arrangedSubviews.count
    )
}

@MainActor
private func layoutConstraintProperties(_ constraint: NSLayoutConstraint) -> LoupeUILayoutConstraintProperties {
    LoupeUILayoutConstraintProperties(
        id: constraintID(constraint),
        identifier: constraint.identifier,
        firstItem: layoutItemDescription(constraint.firstItem),
        firstAttribute: layoutAttributeName(constraint.firstAttribute),
        relation: layoutRelationName(constraint.relation),
        secondItem: layoutItemDescription(constraint.secondItem),
        secondAttribute: layoutAttributeName(constraint.secondAttribute),
        multiplier: finiteDouble(Double(constraint.multiplier)) ?? 0,
        constant: finiteDouble(Double(constraint.constant)) ?? 0,
        priority: finiteDouble(Double(constraint.priority.rawValue)) ?? 0,
        isActive: constraint.isActive
    )
}

@MainActor
private func constraintID(_ constraint: NSLayoutConstraint) -> String {
    let raw = String(describing: ObjectIdentifier(constraint))
    let value = raw
        .replacingOccurrences(of: "ObjectIdentifier(", with: "")
        .replacingOccurrences(of: ")", with: "")
    return "c\(value)"
}

@MainActor
private func runtimeConstraints() -> [NSLayoutConstraint] {
    var constraints: [NSLayoutConstraint] = []
    var seen = Set<ObjectIdentifier>()

    func append(_ constraint: NSLayoutConstraint) {
        let id = ObjectIdentifier(constraint)
        guard !seen.contains(id) else {
            return
        }
        seen.insert(id)
        constraints.append(constraint)
    }

    func visit(_ view: UIView) {
        view.constraints.forEach(append)
        view.constraintsAffectingLayout(for: .horizontal).forEach(append)
        view.constraintsAffectingLayout(for: .vertical).forEach(append)
        view.subviews.forEach(visit)
    }

    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        for window in scene.windows {
            visit(window)
        }
    }
    return constraints
}

@MainActor
private func layoutRuntimeWindows() {
    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
        for window in scene.windows {
            window.setNeedsLayout()
            window.layoutIfNeeded()
        }
    }
}

private func constraintMutationMatches(
    _ request: LoupeConstraintMutationRequest,
    _ effective: LoupeUILayoutConstraintProperties
) -> Bool {
    if let constant = request.constant, abs(effective.constant - constant) >= 0.5 {
        return false
    }
    if let priority = request.priority, abs(effective.priority - priority) >= 0.5 {
        return false
    }
    if let isActive = request.isActive, effective.isActive != isActive {
        return false
    }
    return true
}

@MainActor
private func layoutItemDescription(_ item: Any?) -> String? {
    guard let item else {
        return nil
    }
    let object = item as AnyObject
    if let view = object as? UIView {
        if let identifier = view.accessibilityIdentifier, !identifier.isEmpty {
            return "\(typeName(of: view))#\(identifier)"
        }
        return typeName(of: view)
    }
    if let guide = object as? UILayoutGuide {
        if !guide.identifier.isEmpty {
            return "\(typeName(of: guide))#\(guide.identifier)"
        }
        return typeName(of: guide)
    }
    return typeName(of: object)
}

@MainActor
private func controlProperties(for view: UIView) -> LoupeUIControlProperties? {
    guard let control = view as? UIControl else {
        return nil
    }
    return LoupeUIControlProperties(
        controlState: controlStateName(control.state),
        controlEvents: controlEventNames(control.allControlEvents)
    )
}

@MainActor
private func labelProperties(for view: UIView) -> LoupeUILabelProperties? {
    guard let label = view as? UILabel else {
        return nil
    }
    return LoupeUILabelProperties(
        textAlignment: textAlignmentName(label.textAlignment),
        numberOfLines: label.numberOfLines,
        lineBreakMode: lineBreakModeName(label.lineBreakMode)
    )
}

@MainActor
private func buttonProperties(for view: UIView) -> LoupeUIButtonProperties? {
    guard let button = view as? UIButton else {
        return nil
    }
    return LoupeUIButtonProperties(
        lineBreakMode: button.titleLabel.map { lineBreakModeName($0.lineBreakMode) }
    )
}

@MainActor
private func textFieldProperties(for view: UIView) -> LoupeUITextFieldProperties? {
    guard let textField = view as? UITextField else {
        return nil
    }
    return LoupeUITextFieldProperties(
        textAlignment: textAlignmentName(textField.textAlignment),
        borderStyle: borderStyleName(textField.borderStyle)
    )
}

@MainActor
private func textViewProperties(for view: UIView) -> LoupeUITextViewProperties? {
    guard let textView = view as? UITextView else {
        return nil
    }
    return LoupeUITextViewProperties(textAlignment: textAlignmentName(textView.textAlignment))
}

@MainActor
private func scrollViewProperties(for view: UIView) -> LoupeUIScrollViewProperties? {
    guard let scrollView = view as? UIScrollView else {
        return nil
    }
    return LoupeUIScrollViewProperties(
        contentOffset: LoupePoint(
            x: finiteDouble(scrollView.contentOffset.x.doubleValue) ?? 0,
            y: finiteDouble(scrollView.contentOffset.y.doubleValue) ?? 0
        ),
        contentSize: LoupeSize(
            width: finiteDouble(scrollView.contentSize.width.doubleValue) ?? 0,
            height: finiteDouble(scrollView.contentSize.height.doubleValue) ?? 0
        ),
        adjustedContentInset: LoupeInsets(
            top: finiteDouble(scrollView.adjustedContentInset.top.doubleValue) ?? 0,
            left: finiteDouble(scrollView.adjustedContentInset.left.doubleValue) ?? 0,
            bottom: finiteDouble(scrollView.adjustedContentInset.bottom.doubleValue) ?? 0,
            right: finiteDouble(scrollView.adjustedContentInset.right.doubleValue) ?? 0
        ),
        isScrollEnabled: scrollView.isScrollEnabled,
        alwaysBounceVertical: scrollView.alwaysBounceVertical,
        alwaysBounceHorizontal: scrollView.alwaysBounceHorizontal
    )
}

@MainActor
private func switchProperties(for view: UIView) -> LoupeUISwitchProperties? {
    guard let switchView = view as? UISwitch else {
        return nil
    }
    return LoupeUISwitchProperties(isOn: switchView.isOn)
}

@MainActor
private func sliderProperties(for view: UIView) -> LoupeUISliderProperties? {
    guard let slider = view as? UISlider else {
        return nil
    }
    return LoupeUISliderProperties(
        value: finiteDouble(Double(slider.value)),
        minimumValue: finiteDouble(Double(slider.minimumValue)),
        maximumValue: finiteDouble(Double(slider.maximumValue))
    )
}

@MainActor
private func stepperProperties(for view: UIView) -> LoupeUIStepperProperties? {
    guard let stepper = view as? UIStepper else {
        return nil
    }
    return LoupeUIStepperProperties(
        value: finiteDouble(stepper.value),
        minimumValue: finiteDouble(stepper.minimumValue),
        maximumValue: finiteDouble(stepper.maximumValue),
        stepValue: finiteDouble(stepper.stepValue)
    )
}

@MainActor
private func segmentedControlProperties(for view: UIView) -> LoupeUISegmentedControlProperties? {
    guard let segmentedControl = view as? UISegmentedControl else {
        return nil
    }
    return LoupeUISegmentedControlProperties(
        selectedSegmentIndex: segmentedControl.selectedSegmentIndex,
        segments: segmentTitles(for: view)
    )
}

@MainActor
private func datePickerProperties(for view: UIView) -> LoupeUIDatePickerProperties? {
    guard let datePicker = view as? UIDatePicker else {
        return nil
    }
    return LoupeUIDatePickerProperties(
        mode: datePickerModeName(datePicker.datePickerMode),
        date: datePicker.date,
        minimumDate: datePicker.minimumDate,
        maximumDate: datePicker.maximumDate
    )
}

@MainActor
private func pageControlProperties(for view: UIView) -> LoupeUIPageControlProperties? {
    guard let pageControl = view as? UIPageControl else {
        return nil
    }
    return LoupeUIPageControlProperties(
        currentPage: pageControl.currentPage,
        numberOfPages: pageControl.numberOfPages
    )
}

@MainActor
private func progressViewProperties(for view: UIView) -> LoupeUIProgressViewProperties? {
    guard let progressView = view as? UIProgressView else {
        return nil
    }
    return LoupeUIProgressViewProperties(value: finiteDouble(Double(progressView.progress)))
}

@MainActor
private func activityIndicatorProperties(for view: UIView) -> LoupeUIActivityIndicatorProperties? {
    guard let activityIndicator = view as? UIActivityIndicatorView else {
        return nil
    }
    return LoupeUIActivityIndicatorProperties(
        isAnimating: activityIndicator.isAnimating,
        style: activityIndicatorStyleName(activityIndicator.style)
    )
}

@MainActor
private func imageViewProperties(for view: UIView) -> LoupeUIImageViewProperties? {
    guard view is UIImageView else {
        return nil
    }
    return LoupeUIImageViewProperties(imageSize: imageSize(for: view))
}

@MainActor
private func pickerViewProperties(for view: UIView) -> LoupeUIPickerViewProperties? {
    guard let pickerView = view as? UIPickerView else {
        return nil
    }
    return LoupeUIPickerViewProperties(
        numberOfComponents: pickerView.numberOfComponents,
        selectedRows: pickerSelectedRows(for: view)
    )
}

@MainActor
private func tabBarProperties(for view: UIView) -> LoupeUITabBarProperties? {
    guard let tabBar = view as? UITabBar else {
        return nil
    }
    return LoupeUITabBarProperties(
        items: tabBarItemTitles(for: view),
        selectedItem: tabBar.selectedItem?.title
    )
}

@MainActor
private func webViewProperties(for view: UIView) -> LoupeWKWebViewProperties? {
    #if canImport(WebKit)
    guard view is WKWebView else {
        return nil
    }
    return LoupeWKWebViewProperties(
        url: webViewURL(for: view),
        title: webViewTitle(for: view)
    )
    #else
    return nil
    #endif
}

@MainActor
private func syntheticBarButtonNode(
    _ item: UIBarButtonItem,
    ref: String,
    parentRef: String,
    position: String,
    index: Int,
    matchedView: UIView?,
    inheritedVisible: Bool
) -> LoupeNode {
    let frame = matchedView.flatMap(frameInScreen(for:))
    let visible = inheritedVisible && item.isEnabled && frame.map(frameIntersectsScreen) == true
    var custom: [String: LoupeMetadataValue] = [
        "synthetic": .bool(true),
        "source": .string("UIBarButtonItem"),
        "barPosition": .string(position),
        "barIndex": .int(index)
    ]
    if let title = item.title {
        custom["title"] = .string(title)
    }

    let className = matchedView.map(typeName(of:)) ?? "UIBarButtonItem"
    return LoupeNode(
        ref: ref,
        parentRef: parentRef,
        kind: .view,
        typeName: "UIBarButtonItem",
        role: "button",
        testID: item.accessibilityIdentifier,
        label: item.accessibilityLabel ?? item.title,
        value: item.accessibilityValue,
        text: item.title,
        frame: frame,
        isVisible: visible,
        isEnabled: item.isEnabled,
        isInteractive: item.isEnabled,
        accessibility: LoupeAccessibility(
            identifier: item.accessibilityIdentifier,
            label: item.accessibilityLabel ?? item.title,
            value: item.accessibilityValue,
            hint: item.accessibilityHint,
            traits: ["button"],
            frame: frame,
            activationPoint: frame.map { LoupePoint(x: $0.x + $0.width / 2, y: $0.y + $0.height / 2) },
            isElement: true
        ),
        uiKit: LoupeUIKitProperties(
            className: className,
            tag: matchedView?.tag ?? 0,
            alpha: matchedView.flatMap { finiteDouble($0.alpha.doubleValue) } ?? 1,
            isHidden: matchedView?.isHidden ?? false,
            isOpaque: matchedView?.isOpaque ?? false,
            clipsToBounds: matchedView?.clipsToBounds ?? false,
            contentMode: matchedView.map { contentModeName($0.contentMode) },
            userInteractionEnabled: matchedView?.isUserInteractionEnabled ?? true,
            gestureRecognizers: matchedView?.gestureRecognizers?.map { typeName(of: $0) } ?? [],
            isFirstResponder: matchedView?.isFirstResponder ?? false,
            control: matchedView.flatMap(controlProperties(for:)),
            button: matchedView.flatMap(buttonProperties(for:))
        ),
        custom: custom
    )
}

@MainActor
private func syntheticTabBarItemNode(
    _ item: UITabBarItem,
    ref: String,
    parentRef: String,
    index: Int,
    selected: Bool,
    matchedView: UIView?,
    inheritedVisible: Bool
) -> LoupeNode {
    let frame = matchedView.flatMap(frameInScreen(for:))
    let visible = inheritedVisible && item.isEnabled && frame != nil
    var custom: [String: LoupeMetadataValue] = [
        "synthetic": .bool(true),
        "source": .string("UITabBarItem"),
        "tabIndex": .int(index),
        "tabTag": .int(item.tag),
        "selected": .bool(selected)
    ]
    if let title = item.title {
        custom["title"] = .string(title)
    }

    let className = matchedView.map(typeName(of:)) ?? "UITabBarItem"
    return LoupeNode(
        ref: ref,
        parentRef: parentRef,
        kind: .view,
        typeName: "UITabBarItem",
        role: "button",
        testID: item.accessibilityIdentifier,
        label: item.accessibilityLabel ?? item.title,
        value: item.accessibilityValue,
        text: item.title,
        frame: frame,
        isVisible: visible,
        isEnabled: item.isEnabled,
        isInteractive: item.isEnabled,
        accessibility: LoupeAccessibility(
            identifier: item.accessibilityIdentifier,
            label: item.accessibilityLabel ?? item.title,
            value: item.accessibilityValue,
            hint: item.accessibilityHint,
            traits: selected ? ["button", "selected"] : ["button"],
            frame: frame,
            activationPoint: frame.map { LoupePoint(x: $0.x + $0.width / 2, y: $0.y + $0.height / 2) },
            isElement: true
        ),
        uiKit: LoupeUIKitProperties(
            className: className,
            tag: matchedView?.tag ?? item.tag,
            alpha: matchedView.flatMap { finiteDouble($0.alpha.doubleValue) } ?? 1,
            isHidden: matchedView?.isHidden ?? false,
            isOpaque: matchedView?.isOpaque ?? false,
            clipsToBounds: matchedView?.clipsToBounds ?? false,
            contentMode: matchedView.map { contentModeName($0.contentMode) },
            userInteractionEnabled: matchedView?.isUserInteractionEnabled ?? true,
            gestureRecognizers: matchedView?.gestureRecognizers?.map { typeName(of: $0) } ?? [],
            isFirstResponder: matchedView?.isFirstResponder ?? false,
            control: matchedView.flatMap(controlProperties(for:)),
            button: matchedView.flatMap(buttonProperties(for:))
        ),
        custom: custom
    )
}

@MainActor
private func matchedBarButtonView(
    for item: UIBarButtonItem,
    position: String,
    index: Int,
    candidates: [UIView],
    consumedCandidateIDs: inout Set<ObjectIdentifier>
) -> UIView? {
    if let customView = item.customView {
        let id = ObjectIdentifier(customView)
        guard !consumedCandidateIDs.contains(id) else {
            return nil
        }
        consumedCandidateIDs.insert(id)
        return customView
    }

    let searchableTexts = [item.title, item.accessibilityLabel, item.accessibilityIdentifier]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !searchableTexts.isEmpty else {
        return nil
    }

    for candidate in candidates where !consumedCandidateIDs.contains(ObjectIdentifier(candidate)) {
        let text = descendantText(in: candidate)
        let identifier = candidate.accessibilityIdentifier ?? ""
        if searchableTexts.contains(where: { text.contains($0) || identifier == $0 }) {
            consumedCandidateIDs.insert(ObjectIdentifier(candidate))
            return candidate
        }
    }

    let positionedCandidates = candidates
        .filter { !consumedCandidateIDs.contains(ObjectIdentifier($0)) }
        .filter { candidate in
            guard let frame = frameInScreen(for: candidate) else {
                return false
            }
            return frameIntersectsScreen(frame)
        }
        .sorted { lhs, rhs in
            let lhsFrame = frameInScreen(for: lhs)
            let rhsFrame = frameInScreen(for: rhs)
            switch position {
            case "right":
                return (lhsFrame?.maxX ?? 0) > (rhsFrame?.maxX ?? 0)
            default:
                return (lhsFrame?.x ?? 0) < (rhsFrame?.x ?? 0)
            }
        }

    guard positionedCandidates.indices.contains(index) else {
        return nil
    }

    let fallback = positionedCandidates[index]
    consumedCandidateIDs.insert(ObjectIdentifier(fallback))
    return fallback
}

@MainActor
private func barButtonCandidateViews(in view: UIView) -> [UIView] {
    var result: [UIView] = []

    func walk(_ current: UIView) {
        if current is UIControl {
            result.append(current)
        }
        current.subviews.forEach(walk)
    }

    view.subviews.forEach(walk)
    return result.sorted { lhs, rhs in
        barButtonCandidateArea(lhs) > barButtonCandidateArea(rhs)
    }
}

@MainActor
private func matchedTabBarItemView(
    for item: UITabBarItem,
    candidates: [UIView],
    consumedCandidateIDs: inout Set<ObjectIdentifier>
) -> UIView? {
    let searchableTexts = [item.title, item.accessibilityLabel, item.accessibilityIdentifier]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !searchableTexts.isEmpty else {
        return nil
    }

    for candidate in candidates where !consumedCandidateIDs.contains(ObjectIdentifier(candidate)) {
        let text = descendantText(in: candidate)
        let identifier = candidate.accessibilityIdentifier ?? ""
        if searchableTexts.contains(where: { text.contains($0) || identifier == $0 }) {
            consumedCandidateIDs.insert(ObjectIdentifier(candidate))
            return candidate
        }
    }

    return nil
}

@MainActor
private func frameIntersectsScreen(_ frame: LoupeRect) -> Bool {
    let bounds = UIScreen.main.bounds
    let screenFrame = LoupeRect(
        x: bounds.origin.x.doubleValue,
        y: bounds.origin.y.doubleValue,
        width: bounds.width.doubleValue,
        height: bounds.height.doubleValue
    )
    return frame.intersects(screenFrame)
}

@MainActor
private func tabBarItemCandidateViews(in view: UIView) -> [UIView] {
    var result: [UIView] = []

    func walk(_ current: UIView) {
        if current is UIControl {
            result.append(current)
        }
        current.subviews.forEach(walk)
    }

    view.subviews.forEach(walk)
    return result.sorted {
        let lhsFrame = frameInScreen(for: $0)
        let rhsFrame = frameInScreen(for: $1)
        return (lhsFrame?.x ?? 0) < (rhsFrame?.x ?? 0)
    }
}

@MainActor
private func barButtonCandidateArea(_ view: UIView) -> Double {
    guard let frame = frameInScreen(for: view) else {
        return 0
    }
    return frame.width * frame.height
}

@MainActor
private func descendantText(in view: UIView) -> String {
    var parts: [String] = []

    func walk(_ current: UIView) {
        if let value = text(for: current), !value.isEmpty {
            parts.append(value)
        }
        if let label = current.accessibilityLabel, !label.isEmpty {
            parts.append(label)
        }
        current.subviews.forEach(walk)
    }

    walk(view)
    return parts.joined(separator: " ")
}

@MainActor
private func owningViewControllerName(for view: UIView) -> String? {
    var responder: UIResponder? = view.next
    while let current = responder {
        if let viewController = current as? UIViewController {
            return typeName(of: viewController)
        }
        responder = current.next
    }
    return nil
}

private func accessibilityTraits(_ traits: UIAccessibilityTraits) -> [String] {
    var names: [String] = []
    let known: [(UIAccessibilityTraits, String)] = [
        (.button, "button"),
        (.link, "link"),
        (.header, "header"),
        (.searchField, "searchField"),
        (.image, "image"),
        (.selected, "selected"),
        (.playsSound, "playsSound"),
        (.keyboardKey, "keyboardKey"),
        (.staticText, "staticText"),
        (.summaryElement, "summaryElement"),
        (.notEnabled, "notEnabled"),
        (.updatesFrequently, "updatesFrequently"),
        (.startsMediaSession, "startsMediaSession"),
        (.adjustable, "adjustable"),
        (.allowsDirectInteraction, "allowsDirectInteraction"),
        (.causesPageTurn, "causesPageTurn")
    ]

    for (trait, name) in known where traits.contains(trait) {
        names.append(name)
    }
    return names
}

private func contentModeName(_ mode: UIView.ContentMode) -> String {
    switch mode {
    case .scaleToFill: return "scaleToFill"
    case .scaleAspectFit: return "scaleAspectFit"
    case .scaleAspectFill: return "scaleAspectFill"
    case .redraw: return "redraw"
    case .center: return "center"
    case .top: return "top"
    case .bottom: return "bottom"
    case .left: return "left"
    case .right: return "right"
    case .topLeft: return "topLeft"
    case .topRight: return "topRight"
    case .bottomLeft: return "bottomLeft"
    case .bottomRight: return "bottomRight"
    @unknown default: return "unknown"
    }
}

@MainActor
private func textAlignment(for view: UIView) -> String? {
    if let label = view as? UILabel {
        return textAlignmentName(label.textAlignment)
    }
    if let textField = view as? UITextField {
        return textAlignmentName(textField.textAlignment)
    }
    if let textView = view as? UITextView {
        return textAlignmentName(textView.textAlignment)
    }
    return nil
}

@MainActor
private func lineBreakMode(for view: UIView) -> String? {
    if let label = view as? UILabel {
        return lineBreakModeName(label.lineBreakMode)
    }
    if let button = view as? UIButton, let label = button.titleLabel {
        return lineBreakModeName(label.lineBreakMode)
    }
    return nil
}

@MainActor
private func segmentTitles(for view: UIView) -> [String] {
    guard let segmentedControl = view as? UISegmentedControl else {
        return []
    }
    return (0..<segmentedControl.numberOfSegments)
        .map { segmentedControl.titleForSegment(at: $0) ?? "" }
}

@MainActor
private func imageSize(for view: UIView) -> LoupeSize? {
    guard let image = (view as? UIImageView)?.image else {
        return nil
    }
    return LoupeSize(
        width: finiteDouble(image.size.width.doubleValue) ?? 0,
        height: finiteDouble(image.size.height.doubleValue) ?? 0
    )
}

@MainActor
private func pickerSelectedRows(for view: UIView) -> [Int] {
    guard let pickerView = view as? UIPickerView else {
        return []
    }
    return (0..<pickerView.numberOfComponents).map { pickerView.selectedRow(inComponent: $0) }
}

@MainActor
private func tabBarItemTitles(for view: UIView) -> [String] {
    guard let tabBar = view as? UITabBar else {
        return []
    }
    return tabBar.items?.map { $0.title ?? "" } ?? []
}

@MainActor
private func webViewURL(for view: UIView) -> String? {
    #if canImport(WebKit)
    return (view as? WKWebView)?.url?.absoluteString
    #else
    return nil
    #endif
}

@MainActor
private func webViewTitle(for view: UIView) -> String? {
    #if canImport(WebKit)
    return (view as? WKWebView)?.title
    #else
    return nil
    #endif
}

private func datePickerModeName(_ mode: UIDatePicker.Mode) -> String {
    switch mode {
    case .time: return "time"
    case .date: return "date"
    case .dateAndTime: return "dateAndTime"
    case .countDownTimer: return "countDownTimer"
    case .yearAndMonth: return "yearAndMonth"
    @unknown default: return "unknown"
    }
}

private func activityIndicatorStyleName(_ style: UIActivityIndicatorView.Style) -> String {
    switch style {
    case .medium: return "medium"
    case .large: return "large"
    case .white: return "white"
    case .whiteLarge: return "whiteLarge"
    case .gray: return "gray"
    @unknown default: return "unknown"
    }
}

private func textAlignmentName(_ alignment: NSTextAlignment) -> String {
    switch alignment {
    case .left: return "left"
    case .center: return "center"
    case .right: return "right"
    case .justified: return "justified"
    case .natural: return "natural"
    @unknown default: return "unknown"
    }
}

private func lineBreakModeName(_ mode: NSLineBreakMode) -> String {
    switch mode {
    case .byWordWrapping: return "byWordWrapping"
    case .byCharWrapping: return "byCharWrapping"
    case .byClipping: return "byClipping"
    case .byTruncatingHead: return "byTruncatingHead"
    case .byTruncatingTail: return "byTruncatingTail"
    case .byTruncatingMiddle: return "byTruncatingMiddle"
    @unknown default: return "unknown"
    }
}

private func borderStyleName(_ style: UITextField.BorderStyle) -> String {
    switch style {
    case .none: return "none"
    case .line: return "line"
    case .bezel: return "bezel"
    case .roundedRect: return "roundedRect"
    @unknown default: return "unknown"
    }
}

private func layoutConstraintAxisName(_ axis: NSLayoutConstraint.Axis) -> String {
    switch axis {
    case .horizontal: return "horizontal"
    case .vertical: return "vertical"
    @unknown default: return "unknown"
    }
}

private func layoutAttributeName(_ attribute: NSLayoutConstraint.Attribute) -> String {
    switch attribute {
    case .left: return "left"
    case .right: return "right"
    case .top: return "top"
    case .bottom: return "bottom"
    case .leading: return "leading"
    case .trailing: return "trailing"
    case .width: return "width"
    case .height: return "height"
    case .centerX: return "centerX"
    case .centerY: return "centerY"
    case .lastBaseline: return "lastBaseline"
    case .firstBaseline: return "firstBaseline"
    case .leftMargin: return "leftMargin"
    case .rightMargin: return "rightMargin"
    case .topMargin: return "topMargin"
    case .bottomMargin: return "bottomMargin"
    case .leadingMargin: return "leadingMargin"
    case .trailingMargin: return "trailingMargin"
    case .centerXWithinMargins: return "centerXWithinMargins"
    case .centerYWithinMargins: return "centerYWithinMargins"
    case .notAnAttribute: return "notAnAttribute"
    @unknown default: return "unknown"
    }
}

private func layoutRelationName(_ relation: NSLayoutConstraint.Relation) -> String {
    switch relation {
    case .lessThanOrEqual: return "lessThanOrEqual"
    case .equal: return "equal"
    case .greaterThanOrEqual: return "greaterThanOrEqual"
    @unknown default: return "unknown"
    }
}

private func stackAlignmentName(_ alignment: UIStackView.Alignment) -> String {
    switch alignment {
    case .fill: return "fill"
    case .leading: return "leading"
    case .firstBaseline: return "firstBaseline"
    case .center: return "center"
    case .trailing: return "trailing"
    case .lastBaseline: return "lastBaseline"
    @unknown default: return "unknown"
    }
}

private func stackDistributionName(_ distribution: UIStackView.Distribution) -> String {
    switch distribution {
    case .fill: return "fill"
    case .fillEqually: return "fillEqually"
    case .fillProportionally: return "fillProportionally"
    case .equalSpacing: return "equalSpacing"
    case .equalCentering: return "equalCentering"
    @unknown default: return "unknown"
    }
}

private func controlStateName(_ state: UIControl.State) -> String {
    var names: [String] = []
    if state.contains(.normal) { names.append("normal") }
    if state.contains(.highlighted) { names.append("highlighted") }
    if state.contains(.disabled) { names.append("disabled") }
    if state.contains(.selected) { names.append("selected") }
    if state.contains(.focused) { names.append("focused") }
    if state.contains(.application) { names.append("application") }
    if state.contains(.reserved) { names.append("reserved") }
    return names.isEmpty ? "unknown" : names.joined(separator: ",")
}

private func controlEventNames(_ events: UIControl.Event) -> [String] {
    var names: [String] = []
    let known: [(UIControl.Event, String)] = [
        (.touchDown, "touchDown"),
        (.touchDownRepeat, "touchDownRepeat"),
        (.touchDragInside, "touchDragInside"),
        (.touchDragOutside, "touchDragOutside"),
        (.touchDragEnter, "touchDragEnter"),
        (.touchDragExit, "touchDragExit"),
        (.touchUpInside, "touchUpInside"),
        (.touchUpOutside, "touchUpOutside"),
        (.touchCancel, "touchCancel"),
        (.valueChanged, "valueChanged"),
        (.primaryActionTriggered, "primaryActionTriggered"),
        (.editingDidBegin, "editingDidBegin"),
        (.editingChanged, "editingChanged"),
        (.editingDidEnd, "editingDidEnd"),
        (.editingDidEndOnExit, "editingDidEndOnExit")
    ]

    for (event, name) in known where events.contains(event) {
        names.append(name)
    }
    return names
}

private func sceneActivationStateName(_ state: UIScene.ActivationState) -> String {
    switch state {
    case .foregroundActive:
        return "foregroundActive"
    case .foregroundInactive:
        return "foregroundInactive"
    case .background:
        return "background"
    case .unattached:
        return "unattached"
    @unknown default:
        return "unknown"
    }
}

private extension CGFloat {
    var doubleValue: Double { Double(self) }
}

#endif
