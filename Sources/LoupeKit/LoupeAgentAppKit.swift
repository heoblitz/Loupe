import Foundation
import LoupeCore

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import ObjectiveC
import Security

private nonisolated(unsafe) var loupeMetadataKey: UInt8 = 0

public extension NSView {
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
        identifier = NSUserInterfaceItemIdentifier(id)
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
        return captureNativeAccessibilityTree(snapshot: capture.snapshot, viewRefs: capture.viewRefs)
    }

    public func captureCompactObservation(
        options: LoupeObservationOptions = LoupeObservationOptions()
    ) -> LoupeCompactObservation {
        LoupeObservationCompactor.compact(captureSnapshot(), options: options)
    }

    public func defaultsEntry(key: String) -> LoupeStateEntry {
        LoupeStateEntry(key: key, value: metadataValue(fromDefault: UserDefaults.standard.object(forKey: key)))
    }

    public func setDefault(_ request: LoupeStateMutationRequest) -> LoupeStateMutationResponse {
        let before = metadataValue(fromDefault: UserDefaults.standard.object(forKey: request.key))
        if let value = request.value {
            UserDefaults.standard.set(defaultObject(from: value), forKey: request.key)
        } else {
            UserDefaults.standard.removeObject(forKey: request.key)
        }
        let after = metadataValue(fromDefault: UserDefaults.standard.object(forKey: request.key))
        return LoupeStateMutationResponse(key: request.key, before: before, after: after)
    }

    public func keychainItems() -> [LoupeKeychainItem] {
        queryKeychainItems(itemClass: kSecClassGenericPassword as String)
            + queryKeychainItems(itemClass: kSecClassInternetPassword as String)
    }

    public func setEnvironment(_ request: LoupeEnvironmentMutationRequest) throws -> LoupeEnvironmentMutationResponse {
        if let appearance = request.appearance {
            let appearanceName = appearance.lowercased()
            switch appearanceName {
            case "light":
                NSApp.appearance = NSAppearance(named: .aqua)
            case "dark":
                NSApp.appearance = NSAppearance(named: .darkAqua)
            case "unspecified", "system":
                NSApp.appearance = nil
            default:
                throw LoupeDiagnosticError(message: "Unknown appearance: \(appearance)")
            }
        }
        return currentEnvironment()
    }

    public func currentEnvironment() -> LoupeEnvironmentMutationResponse {
        LoupeEnvironmentMutationResponse(appearance: currentAppearance())
    }

    public func hitTest(point: LoupePoint) -> LoupeHitTestReport {
        let capture = captureSnapshotWithViewRefs()
        let screenPoint = appKitScreenPoint(from: point)

        for window in NSApp.orderedWindows where window.isVisible {
            guard let contentView = window.contentView else { continue }
            guard window.frame.contains(screenPoint) else { continue }
            let pointInWindow = window.convertPoint(fromScreen: screenPoint)
            let pointInView = contentView.convert(pointInWindow, from: nil)
            guard let view = contentView.hitTest(pointInView) else { continue }
            let ref = capture.viewRefs[ObjectIdentifier(view)]
            let node = ref.flatMap { capture.snapshot.nodes[$0] }
            return LoupeHitTestReport(
                point: point,
                hitRef: ref,
                hitTestID: node?.testID,
                hitTypeName: node?.typeName ?? typeName(of: view),
                responderChain: buildResponderChain(from: view, capture: capture)
            )
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

        guard let view = capture.viewsByRef[match.ref] else {
            guard let frame = match.frame else { return nil }
            return hitTest(point: frame.center)
        }

        return LoupeHitTestReport(
            point: match.frame?.center ?? LoupePoint(x: 0, y: 0),
            hitRef: match.ref,
            hitTestID: match.testID,
            hitTypeName: capture.snapshot.nodes[match.ref]?.typeName ?? typeName(of: view),
            responderChain: buildResponderChain(from: view, capture: capture)
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

    public func activate(_ request: LoupeActivationRequest) throws -> LoupeActivationResponse {
        let beforeCapture = captureSnapshotWithViewRefs()
        let beforeContext = LoupeSnapshotContext(snapshot: beforeCapture.snapshot)
        let selector = loupeSelector(from: request.selector)
        let matches = LoupeSnapshotQuery.preferPlatformBackedMatches(
            LoupeSnapshotQuery.find(
                selector,
                in: beforeContext,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: false, maxResults: 8)
            ),
            in: beforeCapture.snapshot
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
            throw LoupeMutationError(status: 404, code: "node_not_found", message: "Matched node disappeared before activation.")
        }
        guard let view = beforeCapture.viewsByRef[target.ref] else {
            throw LoupeMutationError(
                code: "unsupported_target",
                message: "Matched node \(target.ref) is synthetic or not backed by an NSView."
            )
        }

        let startedAt = Date()
        try activateView(view)
        view.layoutSubtreeIfNeeded()
        view.superview?.layoutSubtreeIfNeeded()
        let elapsed = Date().timeIntervalSince(startedAt)

        runtime.log(
            level: "info",
            "activation_applied",
            metadata: [
                "ref": .string(target.ref),
                "testID": target.testID.map(LoupeMetadataValue.string) ?? .string("")
            ]
        )

        let afterCapture = captureSnapshotWithViewRefs()
        return LoupeActivationResponse(
            selector: request.selector,
            target: target,
            before: beforeNode,
            after: afterCapture.snapshot.nodes[target.ref],
            actionElapsed: elapsed,
            snapshotID: afterCapture.snapshot.id
        )
    }

    public func mutate(_ request: LoupeMutationRequest) throws -> LoupeMutationResponse {
        let beforeCapture = captureSnapshotWithViewRefs()
        let beforeContext = LoupeSnapshotContext(snapshot: beforeCapture.snapshot)
        let selector = loupeSelector(from: request.selector)
        let includeHidden = request.includeHidden || request.selector.kind == .ref
        let matches = LoupeSnapshotQuery.preferPlatformBackedMatches(
            LoupeSnapshotQuery.find(
                selector,
                in: beforeContext,
                options: LoupeQueryOptions(
                    includeHidden: includeHidden,
                    includeDisabled: true,
                    maxResults: 8,
                    visibilityMode: .occlusion
                )
            ),
            in: beforeCapture.snapshot
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
                message: "Matched node \(target.ref) is synthetic or not backed by an NSView."
            )
        }

        try applyMutation(property: request.property, value: request.value, to: view, layout: request.layout)

        runtime.log(
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
        let selfSizingProbe = request.trySelfSizing
            ? LoupeSelfSizingProbeResult(
                requested: true,
                attempted: false,
                applied: false,
                reason: "unsupported_platform_appkit"
            )
            : nil

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
            warning: selfSizingProbe.map { "trySelfSizing skipped: \($0.reason ?? "unsupported_platform_appkit")." },
            selfSizingProbe: selfSizingProbe,
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
            constraint.priority = NSLayoutConstraint.Priority(Float(priority))
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

    private func captureSnapshotWithViewRefs() -> CapturedSnapshot {
        nextRef = 0

        var nodes: [String: LoupeNode] = [:]
        var viewRefs: [ObjectIdentifier: String] = [:]
        var viewsByRef: [String: NSView] = [:]
        let screenFrame = NSScreen.main?.frame ?? .zero
        let screenInfo = LoupeScreen(
            size: LoupeSize(width: Double(screenFrame.width), height: Double(screenFrame.height)),
            scale: Double(NSScreen.main?.backingScaleFactor ?? 1),
            interfaceStyle: currentAppearance()
        )

        let appRef = makeRef()
        let windowRefs = NSApp.windows.compactMap { window -> String? in
            captureWindow(window, parentRef: appRef, nodes: &nodes, viewRefs: &viewRefs, viewsByRef: &viewsByRef)
        }
        let registeredProbeRefs = runtime.registeredProbes().map { probe in
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
            typeName: "NSApplication",
            role: "application",
            frame: LoupeRect(x: 0, y: 0, width: Double(screenFrame.width), height: Double(screenFrame.height)),
            isVisible: true,
            isEnabled: true,
            isInteractive: false,
            children: windowRefs + registeredProbeRefs
        )

        return CapturedSnapshot(
            snapshot: LoupeSnapshot(
                id: UUID().uuidString,
                capturedAt: Date(),
                screen: screenInfo,
                rootRefs: [appRef],
                nodes: nodes
            ),
            viewRefs: viewRefs,
            viewsByRef: viewsByRef
        )
    }

    private func captureNativeAccessibilityTree(
        snapshot: LoupeSnapshot,
        viewRefs: [ObjectIdentifier: String]
    ) -> LoupeAccessibilityTree {
        nextNativeAccessibilityRef = 0

        var tree = LoupeAccessibilityTree.build(from: LoupeSnapshotContext(snapshot: snapshot))
        var signatures = Set(tree.nodes.values.map(nativeAccessibilitySignature(for:)))

        for window in NSApp.windows {
            guard let contentView = window.contentView else { continue }
            appendNativeAccessibilityElements(
                in: contentView,
                snapshot: snapshot,
                viewRefs: viewRefs,
                tree: &tree,
                signatures: &signatures
            )
        }

        return tree
    }

    private func appendNativeAccessibilityElements(
        in view: NSView,
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
            if element is NSView {
                continue
            }

            guard let accessibilityElement = element as? NSAccessibilityElement else {
                continue
            }
            let ownerRef = nativeAccessibilitySourceRef(
                for: accessibilityElement,
                fallback: sourceRef,
                viewRefs: viewRefs
            )
            guard let node = nativeAccessibilityNode(
                for: accessibilityElement,
                sourceRef: ownerRef,
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
        for element: NSAccessibilityElement,
        sourceRef: String,
        snapshot: LoupeSnapshot,
        tree: LoupeAccessibilityTree
    ) -> LoupeAccessibilityNode? {
        let testID = nonEmpty(element.accessibilityIdentifier())
        let label = nonEmpty(element.accessibilityLabel())
        let value = accessibilityValueString(for: element)
        let hint = nonEmpty(element.accessibilityHelp())
        let role = accessibilityRoleName(for: element)
        let traits = role.map { [$0] } ?? []
        let frame = loupeRect(fromScreenRect: element.accessibilityFrame())
        let activationPoint = validActivationPoint(
            loupePoint(fromScreenPoint: element.accessibilityActivationPoint()),
            frame: frame
        )

        guard testID != nil || label != nil || value != nil || hint != nil || !traits.isEmpty else {
            return nil
        }

        let isVisible = !frame.isEmpty && intersectsScreen(frame, screen: snapshot.screen.size)

        return LoupeAccessibilityNode(
            ref: makeNativeAccessibilityRef(sourceRef: sourceRef),
            sourceRef: sourceRef,
            parentRef: treeParentRef(for: sourceRef, tree: tree),
            role: role,
            label: label,
            value: value,
            hint: hint,
            testID: testID,
            traits: traits,
            frame: frame,
            activationPoint: activationPoint,
            isVisible: isVisible,
            isEnabled: element.isAccessibilityEnabled(),
            isInteractive: isInteractiveAccessibilityRole(role),
            children: []
        )
    }

    private func nativeAccessibilitySourceRef(
        for element: NSAccessibilityElement,
        fallback: String,
        viewRefs: [ObjectIdentifier: String]
    ) -> String {
        guard let parent = element.accessibilityParent() as? NSView else {
            return fallback
        }
        return viewRefs[ObjectIdentifier(parent)] ?? fallback
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

        let directElements: [Any]
        if let view = container as? NSView {
            directElements = view.accessibilityChildren() ?? []
        } else if let element = container as? NSAccessibilityElement {
            directElements = element.accessibilityChildren() ?? []
        } else {
            directElements = []
        }

        guard !directElements.isEmpty else {
            return []
        }

        var elements: [NSObject] = []
        for element in directElements.compactMap({ $0 as? NSObject }) {
            elements.append(element)
            if element is NSView {
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

    private func captureWindow(
        _ window: NSWindow,
        parentRef: String,
        nodes: inout [String: LoupeNode],
        viewRefs: inout [ObjectIdentifier: String],
        viewsByRef: inout [String: NSView]
    ) -> String? {
        let windowRef = makeRef()
        let childRefs: [String]
        if let contentView = window.contentView {
            childRefs = [captureView(contentView, parentRef: windowRef, window: window, nodes: &nodes, viewRefs: &viewRefs, viewsByRef: &viewsByRef)]
        } else {
            childRefs = []
        }

        nodes[windowRef] = LoupeNode(
            ref: windowRef,
            parentRef: parentRef,
            kind: .window,
            typeName: "NSWindow",
            role: "window",
            testID: nonEmpty(window.identifier?.rawValue),
            frame: loupeRect(fromScreenRect: window.frame),
            isVisible: window.isVisible,
            isEnabled: true,
            isInteractive: false,
            children: childRefs
        )
        return windowRef
    }

    private func captureView(
        _ view: NSView,
        parentRef: String,
        window: NSWindow,
        nodes: inout [String: LoupeNode],
        viewRefs: inout [ObjectIdentifier: String],
        viewsByRef: inout [String: NSView]
    ) -> String {
        let ref = makeRef()
        viewRefs[ObjectIdentifier(view)] = ref
        viewsByRef[ref] = view

        var childRefs = view.subviews.map {
            captureView($0, parentRef: ref, window: window, nodes: &nodes, viewRefs: &viewRefs, viewsByRef: &viewsByRef)
        }
        let testID = nonEmpty(view.identifier?.rawValue) ?? stringMetadata("id", from: view.loupeMetadata)
        let customMetadata = mergedMetadata(view.loupeMetadata, with: runtime.metadata(forTestID: testID))
        let runtimeProperties = runtimeProperties(for: view)
        let appKitProperties = appKitProperties(for: view)
        let swiftUIProperties = loupeSwiftUIProperties(
            backingTypeName: typeName(of: view),
            frameworkBundleIdentifier: runtimeProperties.frameworkBundleIdentifier,
            viewController: appKitProperties.viewController,
            customMetadata: customMetadata,
            privateSummary: loupeSwiftUIPrivateSummary(from: view)
        )

        if let swiftUIProperties {
            childRefs.append(
                contentsOf: captureSwiftUISemanticChildren(
                    in: view,
                    parentRef: ref,
                    hostProperties: swiftUIProperties,
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
            label: nonEmpty(view.accessibilityLabel()),
            value: accessibilityValueString(for: view),
            placeholder: placeholder(for: view),
            text: text(for: view),
            renderedText: text(for: view),
            semanticText: semanticText(for: view),
            frame: frameInScreen(for: view, window: window),
            isVisible: isVisible(view),
            isEnabled: isEnabled(view),
            isInteractive: isInteractive(view),
            style: style(for: view),
            accessibility: accessibility(for: view),
            runtime: runtimeProperties,
            appkit: appKitProperties,
            swiftui: swiftUIProperties,
            custom: customMetadata,
            children: childRefs
        )
        return ref
    }

    private func captureSwiftUISemanticChildren(
        in view: NSView,
        parentRef: String,
        hostProperties: LoupeSwiftUIProperties,
        nodes: inout [String: LoupeNode]
    ) -> [String] {
        var visitedContainers = Set<ObjectIdentifier>()
        var signatures = Set<String>()
        var refs: [String] = []

        for element in nativeAccessibilityElements(in: view, visitedContainers: &visitedContainers) {
            if element is NSView {
                continue
            }
            guard let element = element as? NSAccessibilityElement,
                  let node = swiftUISemanticNode(
                    for: element,
                    parentRef: parentRef,
                    hostProperties: hostProperties
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
        for element: NSAccessibilityElement,
        parentRef: String,
        hostProperties: LoupeSwiftUIProperties
    ) -> LoupeNode? {
        let testID = nonEmpty(element.accessibilityIdentifier())
        let label = nonEmpty(element.accessibilityLabel())
        let value = accessibilityValueString(for: element)
        let hint = nonEmpty(element.accessibilityHelp())
        let role = accessibilityRoleName(for: element)
        let traits = role.map { [$0] } ?? []
        let frame = loupeRect(fromScreenRect: element.accessibilityFrame())
        let activationPoint = validActivationPoint(
            loupePoint(fromScreenPoint: element.accessibilityActivationPoint()),
            frame: frame
        )

        guard testID != nil || label != nil || value != nil || hint != nil || !traits.isEmpty else {
            return nil
        }

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
            isVisible: !frame.isEmpty && intersectsScreen(frame, screen: currentAppKitScreenSize()),
            isEnabled: element.isAccessibilityEnabled(),
            isInteractive: isInteractiveAccessibilityRole(role),
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

    private func makeRef() -> String {
        nextRef += 1
        return "n\(nextRef)"
    }

    private func makeNativeAccessibilityRef(sourceRef: String) -> String {
        nextNativeAccessibilityRef += 1
        return "ax-native-\(sourceRef)-\(nextNativeAccessibilityRef)"
    }
}

private struct LoupeMutationDescriptor {
    var property: String
    var aliases: Set<String>
    var apply: @MainActor (NSView, LoupeMutationValue) throws -> Void
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
    apply: @escaping @MainActor (NSView, LoupeMutationValue) throws -> Void
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
            view.frame = nsRect(try rectValue(value))
        },
        mutation(["bounds"]) { view, value in
            view.bounds = nsRect(try rectValue(value))
        },
        mutation(["alpha", "style.alpha", "appkit.alpha"]) { view, value in
            view.alphaValue = CGFloat(try doubleValue(value))
        },
        mutation(["hidden", "isHidden", "appkit.isHidden"]) { view, value in
            view.isHidden = try boolValue(value)
        },
        mutation(["backgroundColor", "style.backgroundColor"]) { view, value in
            view.wantsLayer = true
            view.layer?.backgroundColor = try nsColor(value).cgColor
        },
        mutation(["layout.translatesAutoresizingMaskIntoConstraints", "translatesAutoresizingMaskIntoConstraints"]) { view, value in
            view.translatesAutoresizingMaskIntoConstraints = try boolValue(value)
        },
        mutation(["layout.hugging.horizontal"]) { view, value in
            view.setContentHuggingPriority(NSLayoutConstraint.Priority(Float(try doubleValue(value))), for: .horizontal)
        },
        mutation(["layout.hugging.vertical"]) { view, value in
            view.setContentHuggingPriority(NSLayoutConstraint.Priority(Float(try doubleValue(value))), for: .vertical)
        },
        mutation(["layout.compressionResistance.horizontal"]) { view, value in
            view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(Float(try doubleValue(value))), for: .horizontal)
        },
        mutation(["layout.compressionResistance.vertical"]) { view, value in
            view.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(Float(try doubleValue(value))), for: .vertical)
        }
    ]
}

@MainActor
private var layerMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["borderColor", "layer.borderColor", "style.borderColor"]) { view, value in
            view.wantsLayer = true
            view.layer?.borderColor = try nsColor(value).cgColor
        },
        mutation(["borderWidth", "layer.borderWidth", "style.borderWidth"]) { view, value in
            view.wantsLayer = true
            view.layer?.borderWidth = CGFloat(try doubleValue(value))
        },
        mutation(["cornerRadius", "layer.cornerRadius", "style.cornerRadius"]) { view, value in
            view.wantsLayer = true
            view.layer?.cornerRadius = CGFloat(try doubleValue(value))
        },
        mutation(["shadowColor", "layer.shadowColor"]) { view, value in
            view.wantsLayer = true
            view.layer?.shadowColor = try nsColor(value).cgColor
        },
        mutation(["shadowOpacity", "layer.shadowOpacity"]) { view, value in
            view.wantsLayer = true
            view.layer?.shadowOpacity = Float(try doubleValue(value))
        },
        mutation(["shadowRadius", "layer.shadowRadius"]) { view, value in
            view.wantsLayer = true
            view.layer?.shadowRadius = CGFloat(try doubleValue(value))
        },
        mutation(["shadowOffset", "layer.shadowOffset"]) { view, value in
            view.wantsLayer = true
            let size = try sizeValue(value)
            view.layer?.shadowOffset = CGSize(width: size.width, height: size.height)
        }
    ]
}

@MainActor
private var accessibilityMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["accessibility.identifier", "accessibilityIdentifier", "testID"]) { view, value in
            view.identifier = NSUserInterfaceItemIdentifier(try stringValue(value))
        },
        mutation(["accessibility.label", "accessibilityLabel", "label"]) { view, value in
            view.setAccessibilityLabel(try stringValue(value))
        },
        mutation(["accessibility.value", "accessibilityValue"]) { view, value in
            view.setAccessibilityValue(try stringValue(value))
        },
        mutation(["accessibility.hint", "accessibilityHint"]) { view, value in
            view.setAccessibilityHelp(try stringValue(value))
        },
        mutation(["accessibility.isElement", "isAccessibilityElement"]) { view, value in
            view.setAccessibilityElement(try boolValue(value))
        }
    ]
}

@MainActor
private var textMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["text", "label.text", "textField.text", "appkit.text"]) { view, value in
            try setText(try stringValue(value), on: view)
        },
        mutation(["title", "button.title"]) { view, value in
            guard let button = view as? NSButton else {
                throw unsupportedProperty("title", view: view)
            }
            button.title = try stringValue(value)
        },
        mutation(["textColor", "style.textColor"]) { view, value in
            try setTextColor(try nsColor(value), on: view)
        },
        mutation(["fontSize", "font.size", "style.fontSize"]) { view, value in
            try setFontSize(CGFloat(try doubleValue(value)), on: view)
        }
    ]
}

@MainActor
private var controlMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["enabled", "isEnabled", "control.enabled"]) { view, value in
            guard let control = view as? NSControl else {
                throw unsupportedProperty("enabled", view: view)
            }
            control.isEnabled = try boolValue(value)
        },
        mutation(["segmentedControl.selectedSegmentIndex", "appkit.segmentedControl.selectedSegmentIndex"]) { view, value in
            guard let control = view as? NSSegmentedControl else {
                throw unsupportedProperty("segmentedControl.selectedSegmentIndex", view: view)
            }
            let index = try intValue(value)
            guard index >= -1 && index < control.segmentCount else {
                throw LoupeMutationError(code: "invalid_value", message: "Segment index \(index) is outside available segments.")
            }
            control.selectedSegment = index
        },
        mutation(["slider.value", "appkit.slider.value", "uikit.slider.value"]) { view, value in
            guard let slider = view as? NSSlider else {
                throw unsupportedProperty("slider.value", view: view)
            }
            slider.doubleValue = try doubleValue(value)
        },
        mutation(["slider.minimumValue", "appkit.slider.minimumValue", "uikit.slider.minimumValue"]) { view, value in
            guard let slider = view as? NSSlider else {
                throw unsupportedProperty("slider.minimumValue", view: view)
            }
            slider.minValue = try doubleValue(value)
        },
        mutation(["slider.maximumValue", "appkit.slider.maximumValue", "uikit.slider.maximumValue"]) { view, value in
            guard let slider = view as? NSSlider else {
                throw unsupportedProperty("slider.maximumValue", view: view)
            }
            slider.maxValue = try doubleValue(value)
        },
        mutation(["stepper.value", "appkit.stepper.value", "uikit.stepper.value"]) { view, value in
            guard let stepper = view as? NSStepper else {
                throw unsupportedProperty("stepper.value", view: view)
            }
            stepper.doubleValue = try doubleValue(value)
        },
        mutation(["stepper.minimumValue", "appkit.stepper.minimumValue", "uikit.stepper.minimumValue"]) { view, value in
            guard let stepper = view as? NSStepper else {
                throw unsupportedProperty("stepper.minimumValue", view: view)
            }
            stepper.minValue = try doubleValue(value)
        },
        mutation(["stepper.maximumValue", "appkit.stepper.maximumValue", "uikit.stepper.maximumValue"]) { view, value in
            guard let stepper = view as? NSStepper else {
                throw unsupportedProperty("stepper.maximumValue", view: view)
            }
            stepper.maxValue = try doubleValue(value)
        },
        mutation(["stepper.stepValue", "appkit.stepper.stepValue", "uikit.stepper.stepValue"]) { view, value in
            guard let stepper = view as? NSStepper else {
                throw unsupportedProperty("stepper.stepValue", view: view)
            }
            stepper.increment = try doubleValue(value)
        },
        mutation(["progressView.progress", "progressView.value", "appkit.progressView.value", "uikit.progressView.value"]) { view, value in
            guard let progress = view as? NSProgressIndicator else {
                throw unsupportedProperty("progressView.progress", view: view)
            }
            let range = progress.maxValue - progress.minValue
            let normalized = try doubleValue(value)
            progress.doubleValue = range == 0 ? normalized : progress.minValue + normalized * range
        }
    ]
}

@MainActor
private var scrollMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["contentOffset", "scrollView.contentOffset"]) { view, value in
            guard let scrollView = view as? NSScrollView else {
                throw unsupportedProperty("contentOffset", view: view)
            }
            let point = try pointValue(value)
            scrollView.contentView.scroll(to: NSPoint(x: point.x, y: point.y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    ]
}

@MainActor
private var stackMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["stack.orientation", "stackView.orientation", "stack.axis", "stackView.axis"]) { view, value in
            guard let stackView = view as? NSStackView else {
                throw unsupportedProperty("stack.orientation", view: view)
            }
            stackView.orientation = try stackOrientation(try stringValue(value))
        },
        mutation(["stack.spacing", "stackView.spacing"]) { view, value in
            guard let stackView = view as? NSStackView else {
                throw unsupportedProperty("stack.spacing", view: view)
            }
            stackView.spacing = CGFloat(try doubleValue(value))
        }
    ]
}

@MainActor
private func applyMutation(
    property: String,
    value: LoupeMutationValue,
    to view: NSView,
    layout: Bool
) throws {
    let property = normalizedMutationProperty(property)
    guard let descriptor = mutationDescriptors.first(where: { $0.aliases.contains(property) }) else {
        throw unsupportedProperty(property, view: view)
    }
    try descriptor.apply(view, value)
    view.needsDisplay = true
    if layout {
        view.needsLayout = true
        view.superview?.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.superview?.layoutSubtreeIfNeeded()
    }
}

private func normalizedMutationProperty(_ property: String) -> String {
    property
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

@MainActor
private func unsupportedProperty(_ property: String, view: NSView) -> LoupeMutationError {
    LoupeMutationError(
        code: "unsupported_property",
        message: "Property '\(property)' is not supported for \(typeName(of: view))."
    )
}

@MainActor
private func activateView(_ view: NSView) throws {
    guard let control = view as? NSControl else {
        throw LoupeMutationError(
            code: "unsupported_activation_target",
            message: "Matched view \(typeName(of: view)) is not an NSControl."
        )
    }
    control.performClick(nil)
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
    let ancestors = mutationAncestorSummaries(from: parentNode, snapshot: snapshot)
    let siblings = parentNode?.children
        .filter { $0 != targetRef }
        .compactMap { snapshot.nodes[$0].map(mutationNodeSummary) } ?? []
    let children = target.children.compactMap { snapshot.nodes[$0].map(mutationNodeSummary) }

    return LoupeMutationHierarchyContext(
        target: mutationNodeSummary(target),
        parent: parent,
        ancestors: ancestors.isEmpty ? nil : ancestors,
        siblings: siblings,
        children: children
    )
}

@MainActor
private func mutationAncestorSummaries(from parent: LoupeNode?, snapshot: LoupeSnapshot) -> [LoupeMutationNodeSummary] {
    var summaries: [LoupeMutationNodeSummary] = []
    var current = parent?.parentRef.flatMap { snapshot.nodes[$0] }
    while let node = current, summaries.count < 8 {
        summaries.append(mutationNodeSummary(node))
        current = node.parentRef.flatMap { snapshot.nodes[$0] }
    }
    return summaries
}

@MainActor
private func mutationNodeSummary(_ node: LoupeNode) -> LoupeMutationNodeSummary {
    LoupeMutationNodeSummary(
        ref: node.ref,
        typeName: node.platform?.className ?? node.typeName,
        role: node.role,
        testID: node.testID,
        text: LoupeObservationCompactor.displayText(for: node),
        frame: node.frame
    )
}

private func mutationPropertyValue(_ property: String, in node: LoupeNode) -> LoupeMutationValue? {
    switch normalizedMutationProperty(property) {
    case "frame":
        return node.frame.map(LoupeMutationValue.rect)
    case "alpha", "style.alpha", "appkit.alpha":
        return node.style?.alpha.map(LoupeMutationValue.double)
    case "hidden", "ishidden", "appkit.ishidden":
        return .bool(!node.isVisible)
    case "backgroundcolor", "style.backgroundcolor":
        return node.style?.backgroundColor.map(LoupeMutationValue.color)
    case "bordercolor", "layer.bordercolor", "style.bordercolor":
        return node.style?.borderColor.map(LoupeMutationValue.color)
    case "borderwidth", "layer.borderwidth", "style.borderwidth":
        return node.style?.borderWidth.map(LoupeMutationValue.double)
    case "cornerradius", "layer.cornerradius", "style.cornerradius":
        return node.style?.cornerRadius.map(LoupeMutationValue.double)
    case "shadowcolor", "layer.shadowcolor":
        return node.style?.shadowColor.map(LoupeMutationValue.color)
    case "shadowopacity", "layer.shadowopacity":
        return node.style?.shadowOpacity.map(LoupeMutationValue.double)
    case "shadowradius", "layer.shadowradius":
        return node.style?.shadowRadius.map(LoupeMutationValue.double)
    case "shadowoffset", "layer.shadowoffset":
        return node.style?.shadowOffset.map(LoupeMutationValue.size)
    case "text", "label.text", "textfield.text", "appkit.text":
        return node.text.map(LoupeMutationValue.string)
    case "title", "button.title":
        return node.text.map(LoupeMutationValue.string)
    case "enabled", "isenabled", "control.enabled", "appkit.enabled":
        return .bool(node.isEnabled)
    case "accessibility.label", "accessibilitylabel", "label":
        return node.accessibility?.label.map(LoupeMutationValue.string) ?? node.label.map(LoupeMutationValue.string)
    case "accessibility.value", "accessibilityvalue":
        return node.accessibility?.value.map(LoupeMutationValue.string) ?? node.value.map(LoupeMutationValue.string)
    case "accessibility.identifier", "accessibilityidentifier", "testid":
        return node.accessibility?.identifier.map(LoupeMutationValue.string) ?? node.testID.map(LoupeMutationValue.string)
    case "layout.translatesautoresizingmaskintoconstraints", "translatesautoresizingmaskintoconstraints":
        return node.platform?.layout.map { .bool($0.translatesAutoresizingMaskIntoConstraints) }
    case "layout.isambiguouslayout", "isambiguouslayout":
        return node.platform?.layout.map { .bool($0.isAmbiguousLayout) }
    case "layout.hugging.horizontal":
        return node.platform?.layout.map { .double($0.hugging.horizontal) }
    case "layout.hugging.vertical":
        return node.platform?.layout.map { .double($0.hugging.vertical) }
    case "layout.compressionresistance.horizontal":
        return node.platform?.layout.map { .double($0.compressionResistance.horizontal) }
    case "layout.compressionresistance.vertical":
        return node.platform?.layout.map { .double($0.compressionResistance.vertical) }
    case "contentoffset", "scrollview.contentoffset":
        return node.platform?.scrollView.map { .point($0.contentOffset) }
    case "stack.orientation", "stackview.orientation", "stack.axis", "stackview.axis":
        return node.platform?.stackView.map { .string($0.axis) }
    case "stack.spacing", "stackview.spacing":
        return node.platform?.stackView.map { .double($0.spacing) }
    case "segmentedcontrol.selectedsegmentindex", "appkit.segmentedcontrol.selectedsegmentindex":
        return node.platform?.segmentedControl?.selectedSegmentIndex.map(LoupeMutationValue.int)
    case "slider.value", "appkit.slider.value", "uikit.slider.value":
        return node.platform?.slider?.value.map(LoupeMutationValue.double)
    case "slider.minimumvalue", "appkit.slider.minimumvalue", "uikit.slider.minimumvalue":
        return node.platform?.slider?.minimumValue.map(LoupeMutationValue.double)
    case "slider.maximumvalue", "appkit.slider.maximumvalue", "uikit.slider.maximumvalue":
        return node.platform?.slider?.maximumValue.map(LoupeMutationValue.double)
    case "stepper.value", "appkit.stepper.value", "uikit.stepper.value":
        return node.platform?.stepper?.value.map(LoupeMutationValue.double)
    case "stepper.minimumvalue", "appkit.stepper.minimumvalue", "uikit.stepper.minimumvalue":
        return node.platform?.stepper?.minimumValue.map(LoupeMutationValue.double)
    case "stepper.maximumvalue", "appkit.stepper.maximumvalue", "uikit.stepper.maximumvalue":
        return node.platform?.stepper?.maximumValue.map(LoupeMutationValue.double)
    case "stepper.stepvalue", "appkit.stepper.stepvalue", "uikit.stepper.stepvalue":
        return node.platform?.stepper?.stepValue.map(LoupeMutationValue.double)
    case "progressview.progress", "progressview.value", "appkit.progressview.value", "uikit.progressview.value":
        return node.platform?.progressView?.value.map(LoupeMutationValue.double)
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
    case let (.int(lhs), .double(rhs)):
        return abs(Double(lhs) - rhs) < 0.5
    case let (.double(lhs), .int(rhs)):
        return abs(lhs - Double(rhs)) < 0.5
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

private func nsRect(_ rect: LoupeRect) -> NSRect {
    NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
}

private func nsColor(_ value: LoupeMutationValue) throws -> NSColor {
    guard case let .color(color) = value else {
        throw LoupeMutationError(code: "invalid_value", message: "Expected a color value.")
    }
    return NSColor(
        red: CGFloat(color.red),
        green: CGFloat(color.green),
        blue: CGFloat(color.blue),
        alpha: CGFloat(color.alpha)
    )
}

@MainActor
private func setText(_ text: String, on view: NSView) throws {
    if let button = view as? NSButton {
        button.title = text
    } else if let textField = view as? NSTextField {
        textField.stringValue = text
    } else {
        throw unsupportedProperty("text", view: view)
    }
}

@MainActor
private func setTextColor(_ color: NSColor, on view: NSView) throws {
    if let textField = view as? NSTextField {
        textField.textColor = color
    } else {
        throw unsupportedProperty("textColor", view: view)
    }
}

@MainActor
private func setFontSize(_ size: CGFloat, on view: NSView) throws {
    if let control = view as? NSControl {
        control.font = (control.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).withSize(size)
    } else {
        throw unsupportedProperty("fontSize", view: view)
    }
}

private func stackOrientation(_ value: String) throws -> NSUserInterfaceLayoutOrientation {
    switch value.lowercased() {
    case "horizontal", "h":
        return .horizontal
    case "vertical", "v":
        return .vertical
    default:
        throw LoupeMutationError(code: "invalid_value", message: "Unsupported stack orientation: \(value)")
    }
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

    func visit(_ view: NSView) {
        view.constraints.forEach(append)
        view.constraintsAffectingLayout(for: .horizontal).forEach(append)
        view.constraintsAffectingLayout(for: .vertical).forEach(append)
        view.subviews.forEach(visit)
    }

    for window in NSApp.windows {
        window.contentView.map(visit)
    }
    return constraints
}

@MainActor
private func layoutRuntimeWindows() {
    for window in NSApp.windows {
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
    }
}

@MainActor
private func runtimeProperties(for view: NSView) -> LoupeNodeRuntimeProperties {
    LoupeNodeRuntimeProperties(
        frameworkBundleIdentifier: Bundle(for: type(of: view)).bundleIdentifier
    )
}

@MainActor
private func appKitProperties(for view: NSView) -> LoupeAppKitProperties {
    LoupeAppKitProperties(
        storage: LoupeUIKitProperties(
            className: typeName(of: view),
            tag: view.tag,
            alpha: finiteDouble(view.alphaValue) ?? 0,
            isHidden: view.isHidden,
            isOpaque: view.isOpaque,
            clipsToBounds: view.layer?.masksToBounds ?? false,
            userInteractionEnabled: isInteractive(view),
            gestureRecognizers: view.gestureRecognizers.map { typeName(of: $0) },
            isFirstResponder: view.window?.firstResponder === view,
            isFocused: view.window?.firstResponder === view,
            canBecomeFocused: view.acceptsFirstResponder,
            layout: layoutProperties(for: view),
            stackView: stackViewProperties(for: view),
            control: controlProperties(for: view),
            label: labelProperties(for: view),
            button: buttonProperties(for: view),
            textField: textFieldProperties(for: view),
            scrollView: scrollViewProperties(for: view),
            slider: sliderProperties(for: view),
            stepper: stepperProperties(for: view),
            segmentedControl: segmentedControlProperties(for: view),
            progressView: progressViewProperties(for: view),
            imageView: imageViewProperties(for: view)
        )
    )
}

@MainActor
private func layoutProperties(for view: NSView) -> LoupeUILayoutProperties {
    LoupeUILayoutProperties(
        translatesAutoresizingMaskIntoConstraints: view.translatesAutoresizingMaskIntoConstraints,
        isAmbiguousLayout: view.hasAmbiguousLayout,
        hugging: LoupeUILayoutPriorities(
            horizontal: finiteDouble(CGFloat(view.contentHuggingPriority(for: .horizontal).rawValue)) ?? 0,
            vertical: finiteDouble(CGFloat(view.contentHuggingPriority(for: .vertical).rawValue)) ?? 0
        ),
        compressionResistance: LoupeUILayoutPriorities(
            horizontal: finiteDouble(CGFloat(view.contentCompressionResistancePriority(for: .horizontal).rawValue)) ?? 0,
            vertical: finiteDouble(CGFloat(view.contentCompressionResistancePriority(for: .vertical).rawValue)) ?? 0
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
private func stackViewProperties(for view: NSView) -> LoupeUIStackViewProperties? {
    guard let stackView = view as? NSStackView else {
        return nil
    }
    return LoupeUIStackViewProperties(
        axis: stackView.orientation == .horizontal ? "horizontal" : "vertical",
        alignment: String(describing: stackView.alignment),
        distribution: String(describing: stackView.distribution),
        spacing: finiteDouble(stackView.spacing) ?? 0,
        isBaselineRelativeArrangement: false,
        isLayoutMarginsRelativeArrangement: false,
        arrangedSubviewCount: stackView.arrangedSubviews.count
    )
}

@MainActor
private func scrollViewProperties(for view: NSView) -> LoupeUIScrollViewProperties? {
    guard let scrollView = view as? NSScrollView else {
        return nil
    }
    let documentVisibleRect = scrollView.documentVisibleRect
    let documentSize = scrollView.documentView?.bounds.size ?? scrollView.contentView.bounds.size
    return LoupeUIScrollViewProperties(
        contentOffset: LoupePoint(x: Double(documentVisibleRect.minX), y: Double(documentVisibleRect.minY)),
        contentSize: LoupeSize(width: Double(documentSize.width), height: Double(documentSize.height)),
        adjustedContentInset: LoupeInsets(top: 0, left: 0, bottom: 0, right: 0),
        isScrollEnabled: true,
        isPagingEnabled: false,
        bounces: false,
        alwaysBounceVertical: false,
        alwaysBounceHorizontal: false,
        showsVerticalScrollIndicator: scrollView.hasVerticalScroller,
        showsHorizontalScrollIndicator: scrollView.hasHorizontalScroller
    )
}

@MainActor
private func controlProperties(for view: NSView) -> LoupeUIControlProperties? {
    guard let control = view as? NSControl else {
        return nil
    }
    return LoupeUIControlProperties(
        controlState: control.isEnabled ? "enabled" : "disabled",
        controlEvents: []
    )
}

@MainActor
private func buttonProperties(for view: NSView) -> LoupeUIButtonProperties? {
    guard let button = view as? NSButton else {
        return nil
    }
    return LoupeUIButtonProperties(
        lineBreakMode: button.cell.map { lineBreakModeName($0.lineBreakMode) }
    )
}

@MainActor
private func labelProperties(for view: NSView) -> LoupeUILabelProperties? {
    guard let textField = view as? NSTextField else {
        return nil
    }
    return LoupeUILabelProperties(
        textAlignment: textAlignmentName(textField.alignment),
        numberOfLines: textField.maximumNumberOfLines,
        lineBreakMode: lineBreakModeName(textField.lineBreakMode)
    )
}

@MainActor
private func textFieldProperties(for view: NSView) -> LoupeUITextFieldProperties? {
    guard let textField = view as? NSTextField else {
        return nil
    }
    return LoupeUITextFieldProperties(
        textAlignment: textAlignmentName(textField.alignment),
        borderStyle: textField.isBordered ? "bordered" : "none"
    )
}

@MainActor
private func sliderProperties(for view: NSView) -> LoupeUISliderProperties? {
    guard let slider = view as? NSSlider else {
        return nil
    }
    return LoupeUISliderProperties(
        value: finiteDouble(slider.doubleValue),
        minimumValue: finiteDouble(slider.minValue),
        maximumValue: finiteDouble(slider.maxValue)
    )
}

@MainActor
private func stepperProperties(for view: NSView) -> LoupeUIStepperProperties? {
    guard let stepper = view as? NSStepper else {
        return nil
    }
    return LoupeUIStepperProperties(
        value: finiteDouble(stepper.doubleValue),
        minimumValue: finiteDouble(stepper.minValue),
        maximumValue: finiteDouble(stepper.maxValue),
        stepValue: finiteDouble(stepper.increment)
    )
}

@MainActor
private func segmentedControlProperties(for view: NSView) -> LoupeUISegmentedControlProperties? {
    guard let control = view as? NSSegmentedControl else {
        return nil
    }
    return LoupeUISegmentedControlProperties(
        selectedSegmentIndex: control.selectedSegment,
        segments: (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }
    )
}

@MainActor
private func progressViewProperties(for view: NSView) -> LoupeUIProgressViewProperties? {
    guard let progress = view as? NSProgressIndicator, !progress.isIndeterminate else {
        return nil
    }
    let range = progress.maxValue - progress.minValue
    let normalized = range == 0 ? progress.doubleValue : (progress.doubleValue - progress.minValue) / range
    return LoupeUIProgressViewProperties(value: finiteDouble(normalized))
}

@MainActor
private func imageViewProperties(for view: NSView) -> LoupeUIImageViewProperties? {
    guard let imageView = view as? NSImageView else {
        return nil
    }
    return LoupeUIImageViewProperties(
        imageSize: imageView.image.map { LoupeSize(width: Double($0.size.width), height: Double($0.size.height)) }
    )
}

private func textAlignmentName(_ alignment: NSTextAlignment) -> String {
    switch alignment {
    case .left: return "left"
    case .right: return "right"
    case .center: return "center"
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

@MainActor
private func style(for view: NSView) -> LoupeStyle {
    LoupeStyle(
        alpha: finiteDouble(view.alphaValue),
        backgroundColor: color(from: view.layer?.backgroundColor),
        cornerRadius: view.layer.flatMap { finiteDouble($0.cornerRadius) },
        fontName: font(for: view)?.fontName,
        fontSize: font(for: view).flatMap { finiteDouble($0.pointSize) },
        textColor: textColor(for: view),
        borderColor: color(from: view.layer?.borderColor),
        borderWidth: view.layer.flatMap { finiteDouble($0.borderWidth) },
        shadowColor: color(from: view.layer?.shadowColor),
        shadowOpacity: view.layer.flatMap { finiteDouble(CGFloat($0.shadowOpacity)) },
        shadowRadius: view.layer.flatMap { finiteDouble($0.shadowRadius) },
        shadowOffset: view.layer.map { LoupeSize(width: Double($0.shadowOffset.width), height: Double($0.shadowOffset.height)) }
    )
}

@MainActor
private func textColor(for view: NSView) -> LoupeColor? {
    (view as? NSTextField)?.textColor.flatMap(color(from:))
}

@MainActor
private func font(for view: NSView) -> NSFont? {
    if let control = view as? NSControl {
        return control.font
    }
    if let textView = view as? NSTextView {
        return textView.font
    }
    return nil
}

@MainActor
private func color(from color: NSColor?) -> LoupeColor? {
    guard let color = color?.usingColorSpace(.deviceRGB) else {
        return nil
    }
    return LoupeColor(
        red: finiteDouble(color.redComponent) ?? 0,
        green: finiteDouble(color.greenComponent) ?? 0,
        blue: finiteDouble(color.blueComponent) ?? 0,
        alpha: finiteDouble(color.alphaComponent) ?? 0
    )
}

private func color(from color: CGColor?) -> LoupeColor? {
    guard let color else {
        return nil
    }
    return NSColor(cgColor: color).flatMap { nsColor in
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
            return nil
        }
        return LoupeColor(
            red: finiteDouble(rgb.redComponent) ?? 0,
            green: finiteDouble(rgb.greenComponent) ?? 0,
            blue: finiteDouble(rgb.blueComponent) ?? 0,
            alpha: finiteDouble(rgb.alphaComponent) ?? 0
        )
    }
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
        multiplier: finiteDouble(constraint.multiplier) ?? 0,
        constant: finiteDouble(constraint.constant) ?? 0,
        priority: finiteDouble(CGFloat(constraint.priority.rawValue)) ?? 0,
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
private func layoutItemDescription(_ item: Any?) -> String? {
    guard let item else {
        return nil
    }
    let object = item as AnyObject
    if let view = object as? NSView {
        if let identifier = nonEmpty(view.identifier?.rawValue) {
            return "\(typeName(of: view))#\(identifier)"
        }
        return typeName(of: view)
    }
    return typeName(of: object)
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
    case .notAnAttribute: return "notAnAttribute"
    @unknown default: return "unknown"
    }
}

private func layoutRelationName(_ relation: NSLayoutConstraint.Relation) -> String {
    switch relation {
    case .lessThanOrEqual: return "<="
    case .equal: return "=="
    case .greaterThanOrEqual: return ">="
    @unknown default: return "unknown"
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

private struct CapturedSnapshot {
    var snapshot: LoupeSnapshot
    var viewRefs: [ObjectIdentifier: String]
    var viewsByRef: [String: NSView]
}

@MainActor
private func currentAppearance() -> String {
    let name = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
    switch name {
    case .darkAqua:
        return "dark"
    case .aqua:
        return "light"
    default:
        return "unspecified"
    }
}

@MainActor
private func buildResponderChain(from view: NSView, capture: CapturedSnapshot) -> [LoupeResponderEntry] {
    var entries: [LoupeResponderEntry] = []
    var responder: NSResponder? = view

    while let current = responder {
        if let view = current as? NSView {
            let ref = capture.viewRefs[ObjectIdentifier(view)]
            let node = ref.flatMap { capture.snapshot.nodes[$0] }
            entries.append(
                LoupeResponderEntry(
                    typeName: typeName(of: view),
                    ref: ref,
                    testID: node?.testID ?? view.identifier?.rawValue,
                    frame: node?.frame
                )
            )
        } else {
            entries.append(LoupeResponderEntry(typeName: typeName(of: current)))
        }
        responder = current.nextResponder
    }

    return entries
}

@MainActor
private func frameInScreen(for view: NSView, window: NSWindow) -> LoupeRect? {
    guard view.window === window else {
        return nil
    }
    let rect = view.convert(view.bounds, to: nil)
    return loupeRect(fromScreenRect: window.convertToScreen(rect))
}

private func loupeRect(from rect: NSRect, flippedIn height: CGFloat?) -> LoupeRect {
    let y = height.map { $0 - rect.maxY } ?? rect.minY
    return LoupeRect(x: Double(rect.minX), y: Double(y), width: Double(rect.width), height: Double(rect.height))
}

private func loupeRect(fromScreenRect rect: NSRect) -> LoupeRect {
    let screenHeight = NSScreen.main?.frame.maxY ?? rect.maxY
    return LoupeRect(
        x: Double(rect.minX),
        y: Double(screenHeight - rect.maxY),
        width: Double(rect.width),
        height: Double(rect.height)
    )
}

private func loupePoint(fromScreenPoint point: NSPoint) -> LoupePoint {
    let screenHeight = NSScreen.main?.frame.maxY ?? point.y
    return LoupePoint(
        x: finiteDouble(Double(point.x)) ?? 0,
        y: finiteDouble(Double(screenHeight - point.y)) ?? 0
    )
}

private func appKitScreenPoint(from point: LoupePoint) -> NSPoint {
    let screenHeight = NSScreen.main?.frame.maxY ?? CGFloat(point.y)
    return NSPoint(x: point.x, y: Double(screenHeight) - point.y)
}

@MainActor
private func accessibility(for view: NSView) -> LoupeAccessibility? {
    let identifier = nonEmpty(view.identifier?.rawValue)
    let label = nonEmpty(text(for: view)) ?? nonEmpty(view.accessibilityLabel())
    let value = accessibilityValueString(for: view)
    let hint = accessibilityHint(for: view)
    guard identifier != nil || label != nil || value != nil || hint != nil || isInteractive(view) else {
        return nil
    }
    return LoupeAccessibility(
        identifier: identifier,
        label: label,
        value: value,
        hint: hint,
        traits: role(for: view).map { [$0] } ?? [],
        frame: view.window.flatMap { frameInScreen(for: view, window: $0) },
        activationPoint: view.window.flatMap { frameInScreen(for: view, window: $0) }?.center,
        isElement: isInteractive(view) || label != nil
    )
}

@MainActor
private func role(for view: NSView) -> String? {
    switch view {
    case is NSButton:
        return "button"
    case is NSTextField:
        return isInteractive(view) ? "textField" : "staticText"
    case is NSTableView:
        return "tableView"
    case is NSScrollView:
        return "scrollView"
    case is NSSegmentedControl:
        return "segmentedControl"
    case is NSSlider:
        return "slider"
    case is NSStepper:
        return "stepper"
    case is NSProgressIndicator:
        return "progress"
    case is NSImageView:
        return "image"
    default:
        return accessibilityRoleName(for: view.accessibilityRole())
    }
}

@MainActor
private func text(for view: NSView) -> String? {
    switch view {
    case let button as NSButton:
        return nonEmpty(button.title)
    case let textField as NSTextField:
        return nonEmpty(textField.stringValue)
    case let control as NSSegmentedControl:
        return (0..<control.segmentCount).compactMap { nonEmpty(control.label(forSegment: $0)) }.joined(separator: " ").nilIfEmpty
    default:
        return nil
    }
}

@MainActor
private func placeholder(for view: NSView) -> String? {
    (view as? NSTextField).flatMap { nonEmpty($0.placeholderString) }
}

@MainActor
private func semanticText(for view: NSView) -> String? {
    nonEmpty(view.accessibilityLabel())
        ?? accessibilityValueString(for: view)
        ?? text(for: view)
}

@MainActor
private func accessibilityValueString(for view: NSView) -> String? {
    guard let value = view.accessibilityValue() else {
        return nil
    }
    if let string = value as? String {
        return nonEmpty(string)
    }
    return nonEmpty(String(describing: value))
}

@MainActor
private func accessibilityHint(for view: NSView) -> String? {
    nonEmpty(view.accessibilityHelp())
}

@MainActor
private func isVisible(_ view: NSView) -> Bool {
    guard !view.isHidden, view.window?.isVisible == true else {
        return false
    }
    var current = view.superview
    while let parent = current {
        if parent.isHidden {
            return false
        }
        current = parent.superview
    }
    return true
}

@MainActor
private func isEnabled(_ view: NSView) -> Bool {
    (view as? NSControl)?.isEnabled ?? true
}

@MainActor
private func isInteractive(_ view: NSView) -> Bool {
    if let textField = view as? NSTextField {
        return textField.isEnabled && (textField.isEditable || textField.isSelectable)
    }
    if let control = view as? NSControl {
        return control.isEnabled
    }
    return view.gestureRecognizers.count > 0
}

private func typeName(of object: AnyObject) -> String {
    String(describing: type(of: object))
}

private func finiteDouble(_ value: CGFloat) -> Double? {
    let double = Double(value)
    return double.isFinite ? double : nil
}

private func finiteDouble(_ value: Double) -> Double? {
    value.isFinite ? value : nil
}

private func accessibilityValueString(for element: NSAccessibilityElement) -> String? {
    guard let value = element.accessibilityValue() else {
        return nil
    }
    if let string = value as? String {
        return nonEmpty(string)
    }
    return nonEmpty(String(describing: value))
}

private func accessibilityRoleName(for element: NSAccessibilityElement) -> String? {
    accessibilityRoleName(for: element.accessibilityRole())
}

private func accessibilityRoleName(for role: NSAccessibility.Role?) -> String? {
    guard let role else {
        return nil
    }
    switch role {
    case .button:
        return "button"
    case .link:
        return "link"
    case .image:
        return "image"
    case .staticText:
        return "staticText"
    case .textField:
        return "textField"
    case .checkBox:
        return "checkBox"
    case .radioButton:
        return "radioButton"
    case .slider:
        return "slider"
    case .popUpButton:
        return "popUpButton"
    default:
        return role.rawValue
            .replacingOccurrences(of: "AX", with: "")
            .nilIfEmpty
    }
}

private func isInteractiveAccessibilityRole(_ role: String?) -> Bool {
    switch role {
    case "button", "link", "textField", "checkBox", "radioButton", "slider", "popUpButton":
        return true
    default:
        return false
    }
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

private func currentAppKitScreenSize() -> LoupeSize {
    let frame = NSScreen.main?.frame ?? .zero
    return LoupeSize(width: Double(frame.width), height: Double(frame.height))
}

private func nativeAccessibilitySignature(for node: LoupeAccessibilityNode) -> String {
    let frame = node.frame.map {
        "\(Int($0.x.rounded())):\(Int($0.y.rounded())):\(Int($0.width.rounded())):\(Int($0.height.rounded()))"
    } ?? "nil"
    return [
        node.testID ?? "",
        node.label ?? "",
        node.value ?? "",
        node.hint ?? "",
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

private func metadataValue(fromDefault value: Any?) -> LoupeMetadataValue? {
    switch value {
    case let value as String:
        return .string(value)
    case let value as Bool:
        return .bool(value)
    case let value as Int:
        return .int(value)
    case let value as Double:
        return .double(value)
    case let value as Float:
        return .double(Double(value))
    case let value as NSNumber:
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return .bool(value.boolValue)
        }
        let doubleValue = value.doubleValue
        if doubleValue.rounded() == doubleValue {
            return .int(value.intValue)
        }
        return .double(doubleValue)
    default:
        return nil
    }
}

private func defaultObject(from value: LoupeMetadataValue) -> Any {
    switch value {
    case let .string(value):
        return value
    case let .bool(value):
        return value
    case let .int(value):
        return value
    case let .double(value):
        return value
    }
}

private func stringMetadata(_ key: String, from metadata: [String: LoupeMetadataValue]) -> String? {
    guard case let .string(value)? = metadata[key] else {
        return nil
    }
    return nonEmpty(value)
}

private func mergedMetadata(
    _ base: [String: LoupeMetadataValue],
    with runtime: [String: LoupeMetadataValue]
) -> [String: LoupeMetadataValue] {
    var merged = base
    merged.merge(runtime) { _, runtimeValue in runtimeValue }
    return merged
}

private func queryKeychainItems(itemClass: String) -> [LoupeKeychainItem] {
    let query: [String: Any] = [
        kSecClass as String: itemClass,
        kSecReturnAttributes as String: true,
        kSecMatchLimit as String: kSecMatchLimitAll,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else {
        return []
    }

    let dictionaries: [[String: Any]]
    if let array = result as? [[String: Any]] {
        dictionaries = array
    } else if let dictionary = result as? [String: Any] {
        dictionaries = [dictionary]
    } else {
        dictionaries = []
    }

    return dictionaries.map { dictionary in
        LoupeKeychainItem(
            itemClass: itemClass,
            service: dictionary[kSecAttrService as String] as? String,
            account: dictionary[kSecAttrAccount as String] as? String,
            accessGroup: dictionary[kSecAttrAccessGroup as String] as? String
        )
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#endif
