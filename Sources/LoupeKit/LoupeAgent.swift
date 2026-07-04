import Foundation
import LoupeCore

#if canImport(UIKit) && !os(watchOS)
import UIKit
#if canImport(WebKit)
import WebKit
#endif

@MainActor
public final class LoupeAgent {
    fileprivate static var mutatedConstraints: [String: NSLayoutConstraint] = [:]

    private let runtime: LoupeRuntime
    private var nextRef = 0
    private var nextNativeAccessibilityRef = 0

    public init() {
        runtime = .shared
    }

    init(runtime: LoupeRuntime) {
        self.runtime = runtime
    }

    public func captureSnapshot() -> LoupeSnapshot {
        captureSnapshotWithViewRefs().snapshot
    }

    public func captureAccessibilityTree() -> LoupeAccessibilityTree {
        let capture = captureSnapshotWithViewRefs()
        guard ProcessInfo.processInfo.environment["LOUPE_NATIVE_ACCESSIBILITY"] == "1" else {
            return LoupeAccessibilityTree.build(from: LoupeSnapshotContext(snapshot: capture.snapshot))
        }
        return captureNativeAccessibilityTree(snapshot: capture.snapshot, viewRefs: capture.viewRefs)
    }

    func captureSnapshotWithViewRefs() -> CapturedSnapshot {
        nextRef = 0

        var nodes: [String: LoupeNode] = [:]
        var viewRefs: [ObjectIdentifier: String] = [:]
        var viewsByRef: [String: UIView] = [:]
        #if os(visionOS)
        let screenBounds = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.coordinateSpace.bounds }
            .first ?? .zero
        let screenScale: CGFloat = 1
        #else
        let screen = UIScreen.main
        let screenBounds = screen.bounds
        let screenScale = screen.scale
        #endif
        let interfaceStyle = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.traitCollection.userInterfaceStyle }
            .first
            .map(interfaceStyleName)

        let screenInfo = LoupeScreen(
            size: LoupeSize(
                width: finiteDouble(screenBounds.width.doubleValue) ?? 0,
                height: finiteDouble(screenBounds.height.doubleValue) ?? 0
            ),
            scale: finiteDouble(screenScale.doubleValue) ?? 1,
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

        let materializedProbeIDs = Set(nodes.values.compactMap { node -> String? in
            guard node.isVisible,
                  let testID = node.testID ?? stringMetadata("id", from: node.custom) else {
                return nil
            }
            return testID
        })

        let registeredProbeRefs: [String] = runtime.registeredProbes().compactMap { probe in
            guard !materializedProbeIDs.contains(probe.id) else {
                return nil
            }
            let ref = makeRef()
            nodes[ref] = loupeRegisteredProbeNode(
                probe,
                ref: ref,
                parentRef: appRef,
                runtimeMetadata: runtime.metadata(forTestID: probe.id)
            )
            return ref
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
            children: sceneRefs + registeredProbeRefs
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

    public func hitTest(point: LoupePoint) -> LoupeHitTestReport {
        let capture = captureSnapshotWithViewRefs()
        let cgPoint = CGPoint(x: point.x, y: point.y)

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows.reversed() {
                let pointInWindow = window.convert(cgPoint, from: nil)
                guard let view = window.hitTest(pointInWindow, with: nil) else {
                    continue
                }

                let ref = capture.viewRefs[ObjectIdentifier(view)]
                let node = ref.flatMap { capture.snapshot.nodes[$0] }
                return LoupeHitTestReport(
                    point: point,
                    hitRef: ref,
                    hitTestID: node?.testID,
                    hitTypeName: node?.platform?.className ?? node?.typeName ?? typeName(of: view),
                    responderChain: buildResponderChain(from: view, capture: capture)
                )
            }
        }

        return LoupeHitTestReport(point: point)
    }

    public func responderChain(selector: LoupeSelector) -> LoupeHitTestReport? {
        let capture = captureSnapshotWithViewRefs()
        let context = LoupeSnapshotContext(snapshot: capture.snapshot)
        guard let match = LoupeSnapshotQuery.find(
            selector,
            in: context,
            options: LoupeQueryOptions(includeHidden: true, includeDisabled: true, maxResults: 1)
        ).first else {
            return nil
        }

        if let view = capture.viewsByRef[match.ref] {
            let node = capture.snapshot.nodes[match.ref]
            return LoupeHitTestReport(
                point: match.frame?.center ?? LoupePoint(x: 0, y: 0),
                hitRef: match.ref,
                hitTestID: match.testID,
                hitTypeName: node?.platform?.className ?? node?.typeName ?? typeName(of: view),
                responderChain: buildResponderChain(from: view, capture: capture)
            )
        }

        guard let frame = match.frame else {
            return nil
        }
        return hitTest(point: frame.center)
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
            uikit: uiKitProperties(for: window),
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
        let testID = view.accessibilityIdentifier ?? stringMetadata("id", from: view.loupeMetadata)
        let customMetadata = mergedMetadata(view.loupeMetadata, with: runtime.metadata(forTestID: testID))
        let directlyVisible = view.isHidden == false
            && view.alpha > 0.01
            && view.bounds.width > 0
            && view.bounds.height > 0
        let visible = directlyVisible
            && (inheritedVisible || isAppAuthoredProbe(customMetadata))

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

        let accessibility = accessibility(for: view)
        let runtimeProperties = runtimeProperties(for: view)
        let uiKitProperties = uiKitProperties(for: view)
        let swiftUIProperties = loupeSwiftUIProperties(
            backingTypeName: typeName(of: view),
            frameworkBundleIdentifier: runtimeProperties.frameworkBundleIdentifier,
            viewController: uiKitProperties.viewController,
            customMetadata: customMetadata,
            privateSummary: loupeSwiftUIPrivateSummary(from: view)
        )

        if let swiftUIProperties {
            childRefs.append(
                contentsOf: captureSwiftUISemanticChildren(
                    in: view,
                    parentRef: ref,
                    hostProperties: swiftUIProperties,
                    inheritedVisible: visible,
                    nodes: &nodes
                )
            )
        }

        nodes[ref] = LoupeNode(
            ref: ref,
            parentRef: parentRef,
            kind: .view,
            typeName: typeName(of: view),
            role: role(for: view),
            testID: testID,
            label: accessibility.label,
            value: accessibility.value,
            placeholder: placeholder(for: view),
            text: text(for: view),
            renderedText: renderedText(for: view),
            semanticText: semanticText(for: view),
            frame: frameInScreen(for: view),
            isVisible: visible,
            isEnabled: isEnabled(view),
            isInteractive: isInteractive(view),
            style: style(for: view),
            accessibility: accessibility,
            runtime: runtimeProperties,
            uikit: uiKitProperties,
            swiftui: swiftUIProperties,
            custom: customMetadata,
            children: childRefs
        )

        return ref
    }

    private func captureSwiftUISemanticChildren(
        in view: UIView,
        parentRef: String,
        hostProperties: LoupeSwiftUIProperties,
        inheritedVisible: Bool,
        nodes: inout [String: LoupeNode]
    ) -> [String] {
        var visitedContainers = Set<ObjectIdentifier>()
        var signatures = Set<String>()
        var refs: [String] = []

        for element in nativeAccessibilityElements(in: view, visitedContainers: &visitedContainers) {
            if element is UIView {
                continue
            }
            guard let node = swiftUISemanticNode(
                for: element,
                parentRef: parentRef,
                hostProperties: hostProperties,
                inheritedVisible: inheritedVisible
            ) else {
                continue
            }
            let signature = loupeSwiftUISemanticSignature(for: node)
            guard signatures.insert(signature).inserted else {
                continue
            }
            nodes[node.ref] = node
            refs.append(node.ref)
        }

        return refs
    }

    private func swiftUISemanticNode(
        for element: NSObject,
        parentRef: String,
        hostProperties: LoupeSwiftUIProperties,
        inheritedVisible: Bool
    ) -> LoupeNode? {
        let testID = accessibilityIdentifier(for: element)
        let label = nonEmpty(element.accessibilityLabel)
        let value = nonEmpty(element.accessibilityValue)
        let hint = nonEmpty(element.accessibilityHint)
        let traits = accessibilityTraits(element.accessibilityTraits)
        let role = accessibilityRole(forTraits: traits)
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

        let isVisible = inheritedVisible
            && !element.accessibilityElementsHidden
            && !frame.isEmpty
        let isInteractive = isInteractiveAccessibilityTraits(traits)

        return LoupeNode(
            ref: makeRef(),
            parentRef: parentRef,
            kind: .view,
            typeName: loupeSwiftUISemanticTypeName(role: role, traits: traits),
            role: role,
            testID: testID,
            label: label,
            value: value,
            text: label ?? value,
            semanticText: label ?? value,
            frame: frame,
            isVisible: isVisible,
            isEnabled: !traits.contains("notEnabled"),
            isInteractive: isInteractive,
            accessibility: LoupeAccessibility(
                identifier: testID,
                label: label,
                value: value,
                hint: hint,
                traits: traits,
                frame: frame,
                activationPoint: activationPoint,
                isElement: true
            ),
            runtime: LoupeNodeRuntimeProperties(frameworkBundleIdentifier: "com.apple.SwiftUI"),
            swiftui: loupeSwiftUISemanticProperties(
                backingTypeName: loupeSwiftUISemanticTypeName(role: role, traits: traits),
                hostTypeName: hostProperties.backingTypeName,
                viewController: hostProperties.viewController
            ),
            custom: [
                "synthetic": .bool(true),
                "observationBackend": .string("native-accessibility"),
                "sourceRef": .string(parentRef),
            ]
        )
    }

    private func captureNativeAccessibilityTree(
        snapshot: LoupeSnapshot,
        viewRefs: [ObjectIdentifier: String]
    ) -> LoupeAccessibilityTree {
        nextNativeAccessibilityRef = 0

        let context = LoupeSnapshotContext(snapshot: snapshot)
        var tree = LoupeAccessibilityTree.build(from: context)
        var signatures = Set(tree.nodes.values.map(nativeAccessibilitySignature(for:)))
        let accessibilityVisibleRefs = context.occlusionVisibleRefs

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                appendNativeAccessibilityElements(
                    in: window,
                    snapshot: snapshot,
                    viewRefs: viewRefs,
                    accessibilityVisibleRefs: accessibilityVisibleRefs,
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
        accessibilityVisibleRefs: Set<String>,
        tree: inout LoupeAccessibilityTree,
        signatures: inout Set<String>
    ) {
        guard let sourceRef = viewRefs[ObjectIdentifier(view)] else {
            view.subviews.forEach {
                appendNativeAccessibilityElements(
                    in: $0,
                    snapshot: snapshot,
                    viewRefs: viewRefs,
                    accessibilityVisibleRefs: accessibilityVisibleRefs,
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
                accessibilityVisibleRefs: accessibilityVisibleRefs,
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
                accessibilityVisibleRefs: accessibilityVisibleRefs,
                tree: &tree,
                signatures: &signatures
            )
        }
    }

    private func nativeAccessibilityNode(
        for element: NSObject,
        sourceRef: String,
        snapshot: LoupeSnapshot,
        accessibilityVisibleRefs: Set<String>,
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

        let sourceSurfaceVisible = snapshot.nodes[sourceRef].map {
            $0.isVisible && accessibilityVisibleRefs.contains($0.ref)
        } ?? true
        let isVisible = sourceSurfaceVisible
            && !element.accessibilityElementsHidden
            && !frame.isEmpty

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
        } else if let synthesized = synthesizedAccessibilityElements(of: container) {
            directElements = synthesized
        } else {
            let count = container.accessibilityElementCount()
            // SwiftUI views such as CGDrawingView return NSNotFound here; (0..<NSNotFound)
            // would iterate ~2^63 times and hang. Treat NSNotFound/non-positive as no elements.
            guard count > 0, count != NSNotFound else {
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

    // `accessibilityElement(at:)` re-synthesizes the whole `_accessibilityElements`
    // array on every call, making per-index enumeration O(N^2) and hanging large
    // SwiftUI hosting containers. Read the synthesized array once to stay O(N).
    private func synthesizedAccessibilityElements(of container: NSObject) -> [NSObject]? {
        let selector = NSSelectorFromString("_accessibilityElements")
        guard container.responds(to: selector),
              let elements = container.perform(selector)?.takeUnretainedValue() as? [Any],
              !elements.isEmpty else {
            return nil
        }
        return elements.compactMap { $0 as? NSObject }
    }

    func makeRef() -> String {
        nextRef += 1
        return "n\(nextRef)"
    }

    private func makeNativeAccessibilityRef(sourceRef: String) -> String {
        nextNativeAccessibilityRef += 1
        return "ax-native-\(sourceRef)-\(nextNativeAccessibilityRef)"
    }
}

struct CapturedSnapshot {
    var snapshot: LoupeSnapshot
    var viewRefs: [ObjectIdentifier: String]
    var viewsByRef: [String: UIView]
}

@MainActor
private func buildResponderChain(from view: UIView, capture: CapturedSnapshot) -> [LoupeResponderEntry] {
    var entries: [LoupeResponderEntry] = []
    var responder: UIResponder? = view

    while let current = responder {
        if let view = current as? UIView {
            let ref = capture.viewRefs[ObjectIdentifier(view)]
            let node = ref.flatMap { capture.snapshot.nodes[$0] }
            entries.append(
                LoupeResponderEntry(
                    typeName: typeName(of: view),
                    ref: ref,
                    testID: node?.testID ?? view.accessibilityIdentifier,
                    frame: node?.frame ?? frameInScreen(for: view)
                )
            )
        } else {
            entries.append(LoupeResponderEntry(typeName: typeName(of: current)))
        }

        responder = current.next
    }

    return entries
}

@MainActor
func frameInScreen(for view: UIView) -> LoupeRect? {
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
    #if !os(tvOS)
    if view is UISwitch { return "switch" }
    if view is UISlider { return "slider" }
    if view is UIStepper { return "stepper" }
    #endif
    if view is UISegmentedControl { return "segmentedControl" }
    #if !os(tvOS)
    if view is UIDatePicker { return "datePicker" }
    #endif
    if view is UIPageControl { return "pageControl" }
    if view is UIProgressView { return "progress" }
    if view is UIActivityIndicatorView { return "activityIndicator" }
    if view is UICollectionView { return "collectionView" }
    if view is UITableView { return "tableView" }
    #if !os(tvOS)
    if view is UIPickerView { return "pickerView" }
    #endif
    if view is UITabBar { return "tabBar" }
    #if !os(tvOS)
    if view is UIToolbar { return "toolbar" }
    #endif
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
func text(for view: UIView) -> String? {
    if let label = view as? UILabel {
        return label.text
    }

    if let button = view as? UIButton {
        return button.title(for: button.state) ?? button.currentTitle
    }

    if let textField = view as? UITextField {
        if textField.isSecureTextEntry {
            return redactedSecureText(for: textField.text)
        }
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

private func redactedSecureText(for text: String?) -> String? {
    guard nonEmpty(text) != nil else {
        return nil
    }
    return "••••••••"
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
        tintColor: capturedTintColor(for: view).flatMap { loupeColor(from: $0, traitCollection: view.traitCollection) },
        cornerRadius: finiteDouble(view.layer.cornerRadius.doubleValue),
        fontName: font(for: view)?.fontName,
        fontSize: font(for: view).flatMap { finiteDouble($0.pointSize.doubleValue) },
        textColor: loupeColor(from: textColor(for: view), traitCollection: view.traitCollection),
        borderColor: loupeColor(from: borderColor(for: view), traitCollection: view.traitCollection),
        borderWidth: finiteDouble(view.layer.borderWidth.doubleValue),
        shadowColor: capturedShadowColor(for: view).flatMap { loupeColor(from: $0, traitCollection: view.traitCollection) },
        shadowOpacity: capturedShadowOpacity(for: view),
        shadowRadius: capturedShadowRadius(for: view),
        shadowOffset: capturedShadowOffset(for: view)
    )
}

@MainActor
private func capturedTintColor(for view: UIView) -> UIColor? {
    #if os(tvOS)
    let usesOwnTint = view is UIControl
        || view is UIImageView
        || view is UINavigationBar
        || view is UITabBar
        || view.tintColorDiffersFromSuperview
    #else
    let usesOwnTint = view is UIControl
        || view is UIImageView
        || view is UINavigationBar
        || view is UIToolbar
        || view is UITabBar
        || view.tintColorDiffersFromSuperview
    #endif
    guard usesOwnTint else {
        return nil
    }
    return view.tintColor
}

private extension UIView {
    var tintColorDiffersFromSuperview: Bool {
        guard let superview else {
            return false
        }
        return !tintColor.isEqual(superview.tintColor)
    }
}

@MainActor
private func capturedShadowColor(for view: UIView) -> UIColor? {
    guard layerHasVisibleShadow(view.layer), let cgColor = view.layer.shadowColor else {
        return nil
    }
    return UIColor(cgColor: cgColor)
}

@MainActor
private func capturedShadowOpacity(for view: UIView) -> Double? {
    guard layerHasVisibleShadow(view.layer) else {
        return nil
    }
    return finiteDouble(Double(view.layer.shadowOpacity))
}

@MainActor
private func capturedShadowRadius(for view: UIView) -> Double? {
    guard layerHasVisibleShadow(view.layer) else {
        return nil
    }
    return finiteDouble(view.layer.shadowRadius.doubleValue)
}

@MainActor
private func capturedShadowOffset(for view: UIView) -> LoupeSize? {
    guard layerHasVisibleShadow(view.layer) else {
        return nil
    }
    return LoupeSize(
        width: finiteDouble(view.layer.shadowOffset.width.doubleValue) ?? 0,
        height: finiteDouble(view.layer.shadowOffset.height.doubleValue) ?? 0
    )
}

private func layerHasVisibleShadow(_ layer: CALayer) -> Bool {
    layer.shadowOpacity > 0
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

func finiteDouble(_ value: Double) -> Double? {
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

private func boolMetadata(
    _ key: String,
    from metadata: [String: LoupeMetadataValue]
) -> Bool {
    guard case let .bool(value) = metadata[key] else {
        return false
    }
    return value
}

private func isAppAuthoredProbe(_ metadata: [String: LoupeMetadataValue]) -> Bool {
    boolMetadata("loupe.probe", from: metadata)
        || boolMetadata("loupe.swiftUI", from: metadata)
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

@MainActor
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

func typeName(of value: AnyObject) -> String {
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
    let value: String?
    if let textField = view as? UITextField, textField.isSecureTextEntry {
        value = redactedSecureText(for: textField.accessibilityValue ?? textField.text)
    } else {
        value = view.accessibilityValue
    }

    return LoupeAccessibility(
        identifier: view.accessibilityIdentifier,
        label: view.accessibilityLabel,
        value: value,
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
        viewControllerRole: owningViewControllerRole(for: view),
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
        isFocused: view.isFocused,
        canBecomeFocused: view.canBecomeFocused,
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
        collectionView: collectionViewProperties(for: view),
        tableView: tableViewProperties(for: view),
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
        isAmbiguousLayout: view.hasAmbiguousLayout,
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
func layoutConstraintProperties(_ constraint: NSLayoutConstraint) -> LoupeUILayoutConstraintProperties {
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
func constraintID(_ constraint: NSLayoutConstraint) -> String {
    let raw = String(describing: ObjectIdentifier(constraint))
    let value = raw
        .replacingOccurrences(of: "ObjectIdentifier(", with: "")
        .replacingOccurrences(of: ")", with: "")
    return "c\(value)"
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
func controlProperties(for view: UIView) -> LoupeUIControlProperties? {
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
func buttonProperties(for view: UIView) -> LoupeUIButtonProperties? {
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
        borderStyle: borderStyleName(textField.borderStyle),
        isSecureTextEntry: textField.isSecureTextEntry
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
        contentInset: loupeInsets(from: scrollView.contentInset),
        adjustedContentInset: LoupeInsets(
            top: finiteDouble(scrollView.adjustedContentInset.top.doubleValue) ?? 0,
            left: finiteDouble(scrollView.adjustedContentInset.left.doubleValue) ?? 0,
            bottom: finiteDouble(scrollView.adjustedContentInset.bottom.doubleValue) ?? 0,
            right: finiteDouble(scrollView.adjustedContentInset.right.doubleValue) ?? 0
        ),
        scrollIndicatorInsets: scrollIndicatorInsets(for: scrollView),
        isScrollEnabled: scrollView.isScrollEnabled,
        isPagingEnabled: scrollViewIsPagingEnabled(scrollView),
        bounces: scrollView.bounces,
        alwaysBounceVertical: scrollView.alwaysBounceVertical,
        alwaysBounceHorizontal: scrollView.alwaysBounceHorizontal,
        showsVerticalScrollIndicator: scrollView.showsVerticalScrollIndicator,
        showsHorizontalScrollIndicator: scrollView.showsHorizontalScrollIndicator
    )
}

@MainActor
private func scrollViewIsPagingEnabled(_ scrollView: UIScrollView) -> Bool {
    #if os(tvOS)
    return false
    #else
    return scrollView.isPagingEnabled
    #endif
}

@MainActor
private func scrollIndicatorInsets(for scrollView: UIScrollView) -> LoupeInsets {
    #if os(tvOS)
    return LoupeInsets(top: 0, left: 0, bottom: 0, right: 0)
    #else
    let verticalInsets = scrollView.verticalScrollIndicatorInsets
    let horizontalInsets = scrollView.horizontalScrollIndicatorInsets
    return LoupeInsets(
        top: finiteDouble(verticalInsets.top.doubleValue) ?? 0,
        left: finiteDouble(horizontalInsets.left.doubleValue) ?? 0,
        bottom: finiteDouble(verticalInsets.bottom.doubleValue) ?? 0,
        right: finiteDouble(horizontalInsets.right.doubleValue) ?? 0
    )
    #endif
}

@MainActor
private func collectionViewProperties(for view: UIView) -> LoupeUICollectionViewProperties? {
    guard let collectionView = view as? UICollectionView else {
        return nil
    }

    let layout = collectionView.collectionViewLayout
    let flowLayout = layout as? UICollectionViewFlowLayout
    return LoupeUICollectionViewProperties(
        selfSizingInvalidation: collectionViewSelfSizingInvalidationName(collectionView),
        layoutClassName: typeName(of: layout),
        delegateRespondsToSizeForItemAt: collectionViewDelegateRespondsToSizeForItemAt(collectionView),
        flowLayout: flowLayout.map(collectionViewFlowLayoutProperties)
    )
}

@MainActor
private func collectionViewFlowLayoutProperties(_ layout: UICollectionViewFlowLayout) -> LoupeUICollectionFlowLayoutProperties {
    LoupeUICollectionFlowLayoutProperties(
        itemSize: loupeSize(from: layout.itemSize),
        estimatedItemSize: loupeSize(from: layout.estimatedItemSize),
        usesEstimatedItemSize: layout.estimatedItemSize != .zero,
        usesAutomaticItemSize: layout.itemSize == UICollectionViewFlowLayout.automaticSize
    )
}

@MainActor
private func tableViewProperties(for view: UIView) -> LoupeUITableViewProperties? {
    guard let tableView = view as? UITableView else {
        return nil
    }
    return LoupeUITableViewProperties(
        selfSizingInvalidation: tableViewSelfSizingInvalidationName(tableView),
        rowHeight: finiteDouble(Double(tableView.rowHeight)) ?? 0,
        estimatedRowHeight: finiteDouble(Double(tableView.estimatedRowHeight)) ?? 0,
        usesAutomaticRowHeight: tableView.rowHeight == UITableView.automaticDimension,
        usesEstimatedRowHeight: tableView.estimatedRowHeight > 0,
        delegateRespondsToHeightForRowAt: tableViewDelegateResponds(tableView, selector: #selector(UITableViewDelegate.tableView(_:heightForRowAt:))),
        delegateRespondsToEstimatedHeightForRowAt: tableViewDelegateResponds(tableView, selector: #selector(UITableViewDelegate.tableView(_:estimatedHeightForRowAt:)))
    )
}

@MainActor
func collectionViewSelfSizingInvalidationName(_ collectionView: UICollectionView) -> String? {
    if #available(iOS 16.0, tvOS 16.0, visionOS 1.0, *) {
        return collectionViewSelfSizingInvalidationName(collectionView.selfSizingInvalidation)
    }
    return nil
}

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, *)
private func collectionViewSelfSizingInvalidationName(_ value: UICollectionView.SelfSizingInvalidation) -> String {
    switch value {
    case .disabled:
        return "disabled"
    case .enabled:
        return "enabled"
    case .enabledIncludingConstraints:
        return "enabledIncludingConstraints"
    @unknown default:
        return "unknown"
    }
}

@MainActor
func tableViewSelfSizingInvalidationName(_ tableView: UITableView) -> String? {
    if #available(iOS 16.0, tvOS 16.0, visionOS 1.0, *) {
        return tableViewSelfSizingInvalidationName(tableView.selfSizingInvalidation)
    }
    return nil
}

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, *)
private func tableViewSelfSizingInvalidationName(_ value: UITableView.SelfSizingInvalidation) -> String {
    switch value {
    case .disabled:
        return "disabled"
    case .enabled:
        return "enabled"
    case .enabledIncludingConstraints:
        return "enabledIncludingConstraints"
    @unknown default:
        return "unknown"
    }
}

@MainActor
func collectionViewDelegateRespondsToSizeForItemAt(_ collectionView: UICollectionView) -> Bool {
    collectionView.delegate?.responds(
        to: #selector(UICollectionViewDelegateFlowLayout.collectionView(_:layout:sizeForItemAt:))
    ) ?? false
}

@MainActor
func tableViewDelegateResponds(_ tableView: UITableView, selector: Selector) -> Bool {
    tableView.delegate?.responds(to: selector) ?? false
}

private func loupeSize(from size: CGSize) -> LoupeSize {
    LoupeSize(
        width: finiteDouble(Double(size.width)) ?? 0,
        height: finiteDouble(Double(size.height)) ?? 0
    )
}

private func loupeInsets(from insets: UIEdgeInsets) -> LoupeInsets {
    LoupeInsets(
        top: finiteDouble(insets.top.doubleValue) ?? 0,
        left: finiteDouble(insets.left.doubleValue) ?? 0,
        bottom: finiteDouble(insets.bottom.doubleValue) ?? 0,
        right: finiteDouble(insets.right.doubleValue) ?? 0
    )
}

#if !os(tvOS)
@MainActor
private func switchProperties(for view: UIView) -> LoupeUISwitchProperties? {
    guard let switchView = view as? UISwitch else {
        return nil
    }
    return LoupeUISwitchProperties(isOn: switchView.isOn)
}
#else
@MainActor
private func switchProperties(for view: UIView) -> LoupeUISwitchProperties? { nil }
#endif

#if !os(tvOS)
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
#else
@MainActor
private func sliderProperties(for view: UIView) -> LoupeUISliderProperties? { nil }
#endif

#if !os(tvOS)
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
#else
@MainActor
private func stepperProperties(for view: UIView) -> LoupeUIStepperProperties? { nil }
#endif

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

#if !os(tvOS)
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
#else
@MainActor
private func datePickerProperties(for view: UIView) -> LoupeUIDatePickerProperties? { nil }
#endif

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

#if !os(tvOS)
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
#else
@MainActor
private func pickerViewProperties(for view: UIView) -> LoupeUIPickerViewProperties? { nil }
#endif

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
private func owningViewControllerName(for view: UIView) -> String? {
    owningViewController(for: view).map(typeName(of:))
}

@MainActor
private func owningViewControllerRole(for view: UIView) -> String? {
    guard let viewController = owningViewController(for: view) else {
        return nil
    }
    if viewController is UIAlertController { return "alert" }
    if viewController is UINavigationController { return "navigationController" }
    if viewController is UITabBarController { return "tabBarController" }
    if viewController is UISplitViewController { return "splitViewController" }
    if viewController is UIPageViewController { return "pageViewController" }
    return nil
}

@MainActor
private func owningViewController(for view: UIView) -> UIViewController? {
    var responder: UIResponder? = view.next
    while let current = responder {
        if let viewController = current as? UIViewController {
            return viewController
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

func contentModeName(_ mode: UIView.ContentMode) -> String {
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

#if !os(tvOS)
@MainActor
private func pickerSelectedRows(for view: UIView) -> [Int] {
    guard let pickerView = view as? UIPickerView else {
        return []
    }
    return (0..<pickerView.numberOfComponents).map { pickerView.selectedRow(inComponent: $0) }
}
#endif

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

#if !os(tvOS)
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
#endif

private func activityIndicatorStyleName(_ style: UIActivityIndicatorView.Style) -> String {
    switch style {
    case .medium: return "medium"
    case .large: return "large"
    case .white: return "white"
    case .whiteLarge: return "whiteLarge"
    #if !os(tvOS)
    case .gray: return "gray"
    #endif
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

extension CGFloat {
    var doubleValue: Double { Double(self) }
}

#endif
