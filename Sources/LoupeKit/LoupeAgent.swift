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
                    viewRefs: &viewRefs
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

        return CapturedSnapshot(snapshot: snapshot, viewRefs: viewRefs)
    }

    public func captureCompactObservation(
        options: LoupeObservationOptions = LoupeObservationOptions()
    ) -> LoupeCompactObservation {
        LoupeObservationCompactor.compact(captureSnapshot(), options: options)
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
        viewRefs: inout [ObjectIdentifier: String]
    ) -> String {
        let ref = makeRef()
        viewRefs[ObjectIdentifier(window)] = ref
        var childRefs: [String] = []

        for subview in window.subviews {
            let childRef = captureView(
                subview,
                parentRef: ref,
                inheritedVisible: window.isHidden == false && window.alpha > 0.01,
                nodes: &nodes,
                viewRefs: &viewRefs
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
        viewRefs: inout [ObjectIdentifier: String]
    ) -> String {
        let ref = makeRef()
        viewRefs[ObjectIdentifier(view)] = ref
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
                viewRefs: &viewRefs
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
        control: controlProperties(for: view),
        label: labelProperties(for: view),
        button: buttonProperties(for: view),
        textField: textFieldProperties(for: view),
        textView: textViewProperties(for: view),
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
