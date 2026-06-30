import Foundation
import LoupeCore

#if canImport(UIKit) && !os(watchOS)
import UIKit

public extension LoupeAgent {
    func activate(_ request: LoupeActivationRequest) throws -> LoupeActivationResponse {
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
                message: "Matched node \(target.ref) is synthetic or not backed by a UIView."
            )
        }

        let startedAt = Date()
        try activateView(view)
        layoutRuntimeWindows()
        let elapsed = Date().timeIntervalSince(startedAt)

        LoupeRuntime.shared.log(
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

    func mutate(_ request: LoupeMutationRequest) throws -> LoupeMutationResponse {
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
                message: "Matched node \(target.ref) is synthetic or not backed by a UIView."
            )
        }

        let selfSizingProbe = prepareSelfSizingProbe(
            request: request,
            targetView: view,
            capture: beforeCapture
        )
        try applyMutation(
            property: request.property,
            value: request.value,
            to: view,
            layout: request.layout,
            animation: request.animation
        )
        triggerSelfSizingInvalidation(selfSizingProbe, targetView: view)

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
        let finalSelfSizingProbe = completeSelfSizingProbe(selfSizingProbe, afterCapture: afterCapture)
        let warning = mutationWarning(
            request: request,
            targetRef: target.ref,
            changed: changed,
            snapshot: afterCapture.snapshot,
            selfSizingProbe: finalSelfSizingProbe
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
            selfSizingProbe: finalSelfSizingProbe,
            snapshotID: afterCapture.snapshot.id
        )
    }

    func mutateConstraint(_ request: LoupeConstraintMutationRequest) throws -> LoupeConstraintMutationResponse {
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

    func mutationCapabilities() -> [LoupeMutationCapability] {
        mutationDescriptors
            .map { descriptor in
                LoupeMutationCapability(
                    property: descriptor.property,
                    aliases: descriptor.aliases.sorted()
                )
            }
            .sorted { $0.property < $1.property }
    }

}

@MainActor
private func activateView(_ view: UIView) throws {
    guard let control = view as? UIControl else {
        throw LoupeMutationError(
            code: "unsupported_activation_target",
            message: "Matched view \(typeName(of: view)) is not a UIControl."
        )
    }
    if control.allControlEvents.contains(.primaryActionTriggered) {
        control.sendActions(for: .primaryActionTriggered)
    } else {
        control.sendActions(for: .touchUpInside)
    }
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

private func mutationWarning(
    request: LoupeMutationRequest,
    targetRef: String,
    changed: Bool?,
    snapshot: LoupeSnapshot,
    selfSizingProbe: LoupeSelfSizingProbeResult? = nil
) -> String? {
    var warnings: [String] = []
    if changed == false {
        warnings.append("Mutation applied, but the effective snapshot value does not match the requested value. A layout pass or UIKit owner may have restored it.")
    }
    if normalizedMutationProperty(request.property) == "backgroundcolor",
       let coverageWarning = backgroundPaintCoverageWarning(targetRef: targetRef, snapshot: snapshot) {
        warnings.append(coverageWarning)
    }
    if let selfSizingProbe, selfSizingProbe.requested, !selfSizingProbe.attempted, !selfSizingProbe.applied {
        warnings.append("trySelfSizing skipped: \(selfSizingProbe.reason ?? "not_applicable").")
    } else if let selfSizingProbe, selfSizingProbe.attempted, !selfSizingProbe.applied {
        warnings.append("trySelfSizing did not apply: \(selfSizingProbe.reason ?? "unknown").")
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
    let typeName = coveringChild.platform?.className ?? coveringChild.typeName
    return "backgroundColor changed, but same-frame child \(coveringChild.ref) (\(typeName)) may cover it. Try mutating \(coveringChild.ref) backgroundColor instead."
}

private func framesApproximatelyEqual(_ lhs: LoupeRect, _ rhs: LoupeRect, tolerance: Double = 0.5) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance
        && abs(lhs.y - rhs.y) <= tolerance
        && abs(lhs.width - rhs.width) <= tolerance
        && abs(lhs.height - rhs.height) <= tolerance
}

private struct RuntimeSelfSizingProbe {
    var result: LoupeSelfSizingProbeResult
    var containerView: UIView?
    var cellView: UIView?
}

private struct RuntimeListSizingDecision {
    var sizingOwner: String
    var canAttempt: Bool
    var reason: String?
    var signals: [String]
}

@MainActor
private func prepareSelfSizingProbe(
    request: LoupeMutationRequest,
    targetView: UIView,
    capture: CapturedSnapshot
) -> RuntimeSelfSizingProbe? {
    guard request.trySelfSizing else {
        return nil
    }
    guard let context = runtimeListSizingContext(targetView: targetView, capture: capture) else {
        return RuntimeSelfSizingProbe(
            result: LoupeSelfSizingProbeResult(
                requested: true,
                attempted: false,
                applied: false,
                reason: "target_not_in_collection_or_table"
            ),
            containerView: nil,
            cellView: nil
        )
    }
    guard context.context.canAttemptSelfSizing else {
        return RuntimeSelfSizingProbe(
            result: LoupeSelfSizingProbeResult(
                requested: true,
                attempted: false,
                applied: false,
                reason: context.reason ?? "self_sizing_not_applicable",
                beforeContainerContentSize: contentSize(for: context.containerView),
                beforeCellFrame: context.cellView.flatMap(frameInScreen(for:)),
                context: context.context
            ),
            containerView: context.containerView,
            cellView: context.cellView
        )
    }

    let previousMode = currentSelfSizingInvalidationMode(for: context.containerView)
    if previousMode == "enabledIncludingConstraints" {
        return RuntimeSelfSizingProbe(
            result: LoupeSelfSizingProbeResult(
                requested: true,
                attempted: false,
                applied: true,
                reason: "already_enabledIncludingConstraints",
                previousMode: previousMode,
                effectiveMode: previousMode,
                beforeContainerContentSize: contentSize(for: context.containerView),
                beforeCellFrame: context.cellView.flatMap(frameInScreen(for:)),
                context: context.context
            ),
            containerView: context.containerView,
            cellView: context.cellView
        )
    }
    let applied = enableSelfSizingInvalidationIncludingConstraints(on: context.containerView)
    let effectiveMode = currentSelfSizingInvalidationMode(for: context.containerView)
    return RuntimeSelfSizingProbe(
        result: LoupeSelfSizingProbeResult(
            requested: true,
            attempted: true,
            applied: applied,
            reason: applied ? nil : "self_sizing_invalidation_unavailable",
            previousMode: previousMode,
            effectiveMode: effectiveMode,
            beforeContainerContentSize: contentSize(for: context.containerView),
            beforeCellFrame: context.cellView.flatMap(frameInScreen(for:)),
            context: context.context
        ),
        containerView: context.containerView,
        cellView: context.cellView
    )
}

@MainActor
private func triggerSelfSizingInvalidation(_ probe: RuntimeSelfSizingProbe?, targetView: UIView) {
    guard let probe, probe.result.attempted, probe.result.applied, let containerView = probe.containerView else {
        return
    }

    targetView.invalidateIntrinsicContentSize()
    targetView.superview?.invalidateIntrinsicContentSize()

    if let collectionCell = probe.cellView as? UICollectionViewCell {
        collectionCell.contentView.invalidateIntrinsicContentSize()
        collectionCell.setNeedsLayout()
        collectionCell.contentView.setNeedsLayout()
    } else if let tableCell = probe.cellView as? UITableViewCell {
        tableCell.contentView.invalidateIntrinsicContentSize()
        tableCell.setNeedsLayout()
        tableCell.contentView.setNeedsLayout()
    }

    if let collectionView = containerView as? UICollectionView {
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.setNeedsLayout()
        collectionView.layoutIfNeeded()
    } else if let tableView = containerView as? UITableView {
        tableView.beginUpdates()
        tableView.endUpdates()
        tableView.setNeedsLayout()
        tableView.layoutIfNeeded()
    }

    layoutRuntimeWindows()
}

@MainActor
private func completeSelfSizingProbe(
    _ probe: RuntimeSelfSizingProbe?,
    afterCapture: CapturedSnapshot
) -> LoupeSelfSizingProbeResult? {
    guard var probe else {
        return nil
    }

    if let containerView = probe.containerView {
        probe.result.afterContainerContentSize = contentSize(for: containerView)
        probe.result.effectiveMode = currentSelfSizingInvalidationMode(for: containerView)
    }
    if let cellView = probe.cellView {
        probe.result.afterCellFrame = frameInScreen(for: cellView)
    }
    if let containerView = probe.containerView,
       let containerRef = afterCapture.viewRefs[ObjectIdentifier(containerView)],
       let afterNode = afterCapture.snapshot.nodes[containerRef] {
        probe.result.afterContainerContentSize = afterNode.platform?.scrollView?.contentSize
    }
    if let cellView = probe.cellView,
       let cellRef = afterCapture.viewRefs[ObjectIdentifier(cellView)],
       let afterNode = afterCapture.snapshot.nodes[cellRef] {
        probe.result.afterCellFrame = afterNode.frame
    }
    return probe.result
}

private struct RuntimeListSizingContext {
    var containerView: UIView
    var cellView: UIView?
    var context: LoupeListSizingContext
    var reason: String?
}

@MainActor
private func runtimeListSizingContext(
    targetView: UIView,
    capture: CapturedSnapshot
) -> RuntimeListSizingContext? {
    var current: UIView? = targetView
    var depth = 0
    var cellView: UIView?
    var depthFromCell: Int?

    while let view = current {
        if cellView == nil, view is UICollectionViewCell || view is UITableViewCell {
            cellView = view
            depthFromCell = depth
        }
        if view is UICollectionView || view is UITableView {
            let decision = listSizingDecision(for: view)
            let containerRef = capture.viewRefs[ObjectIdentifier(view)]
            let cellRef = cellView.flatMap { capture.viewRefs[ObjectIdentifier($0)] }
            let containerNode = containerRef.flatMap { capture.snapshot.nodes[$0] }
            let cellNode = cellRef.flatMap { capture.snapshot.nodes[$0] }
            let context = LoupeListSizingContext(
                containerRef: containerRef,
                containerTestID: containerNode?.testID ?? view.accessibilityIdentifier,
                containerKind: view is UICollectionView ? "collectionView" : "tableView",
                containerTypeName: typeName(of: view),
                cellRef: cellRef,
                cellTestID: cellNode?.testID ?? cellView?.accessibilityIdentifier,
                cellTypeName: cellView.map(typeName(of:)),
                targetDepthFromCell: depthFromCell,
                sizingOwner: decision.sizingOwner,
                selfSizingInvalidation: currentSelfSizingInvalidationMode(for: view),
                canAttemptSelfSizing: decision.canAttempt,
                signals: decision.signals
            )
            return RuntimeListSizingContext(
                containerView: view,
                cellView: cellView,
                context: context,
                reason: decision.reason
            )
        }
        current = view.superview
        depth += 1
    }

    return nil
}

@MainActor
private func listSizingDecision(for view: UIView) -> RuntimeListSizingDecision {
    if let collectionView = view as? UICollectionView {
        return collectionViewSizingDecision(collectionView)
    }
    if let tableView = view as? UITableView {
        return tableViewSizingDecision(tableView)
    }
    return RuntimeListSizingDecision(
        sizingOwner: "notList",
        canAttempt: false,
        reason: "target_not_in_collection_or_table",
        signals: []
    )
}

@MainActor
private func collectionViewSizingDecision(_ collectionView: UICollectionView) -> RuntimeListSizingDecision {
    var signals = [
        "layoutClass=\(typeName(of: collectionView.collectionViewLayout))",
        "selfSizingInvalidation=\(collectionViewSelfSizingInvalidationName(collectionView) ?? "unsupported")",
        "delegateRespondsToSizeForItemAt=\(collectionViewDelegateRespondsToSizeForItemAt(collectionView))",
    ]

    guard collectionViewSelfSizingInvalidationName(collectionView) != nil else {
        return RuntimeListSizingDecision(
            sizingOwner: "unsupportedOS",
            canAttempt: false,
            reason: "self_sizing_invalidation_requires_ios_tvos_16",
            signals: signals
        )
    }
    if collectionViewDelegateRespondsToSizeForItemAt(collectionView) {
        return RuntimeListSizingDecision(
            sizingOwner: "delegateSizeForItem",
            canAttempt: false,
            reason: "delegate_size_for_item_owns_cell_size",
            signals: signals
        )
    }
    guard let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else {
        return RuntimeListSizingDecision(
            sizingOwner: "customCollectionLayout",
            canAttempt: false,
            reason: "collection_layout_sizing_unknown",
            signals: signals
        )
    }

    let usesEstimated = flowLayout.estimatedItemSize != .zero
    let usesAutomatic = flowLayout.itemSize == UICollectionViewFlowLayout.automaticSize
    signals.append("estimatedItemSize=\(formatSize(flowLayout.estimatedItemSize))")
    signals.append("itemSize=\(formatSize(flowLayout.itemSize))")
    signals.append("usesEstimatedItemSize=\(usesEstimated)")
    signals.append("usesAutomaticItemSize=\(usesAutomatic)")

    if usesEstimated || usesAutomatic {
        return RuntimeListSizingDecision(
            sizingOwner: usesAutomatic ? "automaticFlowLayoutSelfSizing" : "estimatedFlowLayoutSelfSizing",
            canAttempt: true,
            reason: nil,
            signals: signals
        )
    }

    return RuntimeListSizingDecision(
        sizingOwner: "fixedFlowLayoutItemSize",
        canAttempt: false,
        reason: "flow_layout_item_size_is_fixed",
        signals: signals
    )
}

@MainActor
private func tableViewSizingDecision(_ tableView: UITableView) -> RuntimeListSizingDecision {
    let heightDelegate = tableViewDelegateResponds(tableView, selector: #selector(UITableViewDelegate.tableView(_:heightForRowAt:)))
    let estimatedDelegate = tableViewDelegateResponds(tableView, selector: #selector(UITableViewDelegate.tableView(_:estimatedHeightForRowAt:)))
    let signals = [
        "selfSizingInvalidation=\(tableViewSelfSizingInvalidationName(tableView) ?? "unsupported")",
        "rowHeight=\(formatCGFloat(tableView.rowHeight))",
        "estimatedRowHeight=\(formatCGFloat(tableView.estimatedRowHeight))",
        "delegateRespondsToHeightForRowAt=\(heightDelegate)",
        "delegateRespondsToEstimatedHeightForRowAt=\(estimatedDelegate)",
    ]

    guard tableViewSelfSizingInvalidationName(tableView) != nil else {
        return RuntimeListSizingDecision(
            sizingOwner: "unsupportedOS",
            canAttempt: false,
            reason: "self_sizing_invalidation_requires_ios_tvos_16",
            signals: signals
        )
    }
    if heightDelegate {
        return RuntimeListSizingDecision(
            sizingOwner: "delegateHeightForRow",
            canAttempt: false,
            reason: "delegate_height_for_row_owns_cell_size",
            signals: signals
        )
    }
    if tableView.rowHeight == UITableView.automaticDimension || tableView.estimatedRowHeight > 0 {
        return RuntimeListSizingDecision(
            sizingOwner: "tableAutomaticDimension",
            canAttempt: true,
            reason: nil,
            signals: signals
        )
    }
    return RuntimeListSizingDecision(
        sizingOwner: "fixedTableRowHeight",
        canAttempt: false,
        reason: "table_row_height_is_fixed",
        signals: signals
    )
}

@MainActor
private func enableSelfSizingInvalidationIncludingConstraints(on view: UIView) -> Bool {
    if #available(iOS 16.0, tvOS 16.0, visionOS 1.0, *) {
        if let collectionView = view as? UICollectionView {
            collectionView.selfSizingInvalidation = .enabledIncludingConstraints
            return collectionView.selfSizingInvalidation == .enabledIncludingConstraints
        }
        if let tableView = view as? UITableView {
            tableView.selfSizingInvalidation = .enabledIncludingConstraints
            return tableView.selfSizingInvalidation == .enabledIncludingConstraints
        }
    }
    return false
}

@MainActor
private func currentSelfSizingInvalidationMode(for view: UIView) -> String? {
    if let collectionView = view as? UICollectionView {
        return collectionViewSelfSizingInvalidationName(collectionView)
    }
    if let tableView = view as? UITableView {
        return tableViewSelfSizingInvalidationName(tableView)
    }
    return nil
}

@MainActor
private func contentSize(for view: UIView) -> LoupeSize? {
    guard let scrollView = view as? UIScrollView else {
        return nil
    }
    return LoupeSize(
        width: finiteDouble(Double(scrollView.contentSize.width)) ?? 0,
        height: finiteDouble(Double(scrollView.contentSize.height)) ?? 0
    )
}

private func formatSize(_ size: CGSize) -> String {
    "\(formatCGFloat(size.width))x\(formatCGFloat(size.height))"
}

private func formatCGFloat(_ value: CGFloat) -> String {
    let double = Double(value)
    if double.rounded() == double {
        return "\(Int(double))"
    }
    return String(format: "%.2f", double)
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
    case "tintcolor", "style.tintcolor":
        return node.style?.tintColor.map(LoupeMutationValue.color)
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
    case "stack.axis", "stackview.axis":
        return node.platform?.stackView.map { .string($0.axis) }
    case "stack.alignment", "stackview.alignment":
        return node.platform?.stackView.map { .string($0.alignment) }
    case "stack.distribution", "stackview.distribution":
        return node.platform?.stackView.map { .string($0.distribution) }
    case "stack.spacing", "stackview.spacing":
        return node.platform?.stackView.map { .double($0.spacing) }
    case "stack.layoutmarginsrelativearrangement", "stackview.layoutmarginsrelativearrangement":
        return node.platform?.stackView.map { .bool($0.isLayoutMarginsRelativeArrangement) }
    case "contentoffset", "scrollview.contentoffset":
        return node.platform?.scrollView.map { .point($0.contentOffset) }
    case "contentsize", "scrollview.contentsize":
        return node.platform?.scrollView.map { .size($0.contentSize) }
    case "contentinset", "scrollview.contentinset":
        return node.platform?.scrollView.map { .rect(mutationRect(from: $0.contentInset)) }
    case "scrollindicatorinsets", "scrollview.scrollindicatorinsets":
        return node.platform?.scrollView.map { .rect(mutationRect(from: $0.scrollIndicatorInsets)) }
    case "scrollenabled", "isscrollenabled", "scrollview.isscrollenabled":
        return node.platform?.scrollView.map { .bool($0.isScrollEnabled) }
    #if !os(tvOS)
    case "pagingenabled", "ispagingenabled", "scrollview.ispagingenabled":
        return node.platform?.scrollView.map { .bool($0.isPagingEnabled) }
    #endif
    case "bounces", "scrollview.bounces":
        return node.platform?.scrollView.map { .bool($0.bounces) }
    case "showshorizontalscrollindicator":
        return node.platform?.scrollView.map { .bool($0.showsHorizontalScrollIndicator) }
    case "showsverticalscrollindicator":
        return node.platform?.scrollView.map { .bool($0.showsVerticalScrollIndicator) }
    case "collectionview.selfsizinginvalidation":
        return node.platform?.collectionView?.selfSizingInvalidation.map(LoupeMutationValue.string)
    case "tableview.selfsizinginvalidation":
        return node.platform?.tableView?.selfSizingInvalidation.map(LoupeMutationValue.string)
    default:
        return nil
    }
}

private func mutationRect(from insets: LoupeInsets) -> LoupeRect {
    LoupeRect(x: insets.top, y: insets.left, width: insets.bottom, height: insets.right)
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
            view.frame = frameInSuperview(try rectValue(value), for: view)
        },
        mutation(["bounds"]) { view, value in
            view.bounds = cgRect(try rectValue(value))
        },
        mutation(["center"]) { view, value in
            view.center = pointInSuperview(try pointValue(value), for: view)
        },
        mutation(["alpha", "style.alpha", "uikit.alpha"]) { view, value in
            view.alpha = CGFloat(try doubleValue(value))
        },
        mutation(["hidden", "isHidden", "uikit.isHidden"]) { view, value in
            view.isHidden = try boolValue(value)
        },
        mutation(["opaque", "isOpaque", "uikit.isOpaque"]) { view, value in
            view.isOpaque = try boolValue(value)
        },
        mutation(["clipsToBounds", "masksToBounds", "uikit.clipsToBounds"]) { view, value in
            let bool = try boolValue(value)
            view.clipsToBounds = bool
            view.layer.masksToBounds = bool
        },
        mutation(["userInteractionEnabled", "isUserInteractionEnabled", "uikit.userInteractionEnabled"]) { view, value in
            view.isUserInteractionEnabled = try boolValue(value)
        },
        mutation(["backgroundColor", "style.backgroundColor"]) { view, value in
            view.backgroundColor = try uiColor(value)
        },
        mutation(["tintColor"]) { view, value in
            view.tintColor = try uiColor(value)
        },
        mutation(["contentMode", "uikit.contentMode"]) { view, value in
            view.contentMode = try contentMode(try stringValue(value))
        },
        mutation(["tag", "uikit.tag"]) { view, value in
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
        mutation(["text", "label.text", "textField.text", "textView.text", "uikit.text"]) { view, value in
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
    commonControlMutationDescriptors + unavailableOnTVControlMutationDescriptors
}

@MainActor
private var commonControlMutationDescriptors: [LoupeMutationDescriptor] {
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
        mutation(["segmentedControl.selectedSegmentIndex", "uikit.segmentedControl.selectedSegmentIndex"]) { view, value in
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
        mutation(["pageControl.currentPage", "uikit.pageControl.currentPage"]) { view, value in
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
        mutation(["progressView.progress", "progressView.value", "uikit.progress.progress", "uikit.progressView.value"]) { view, value in
            guard let progressView = view as? UIProgressView else {
                throw unsupportedProperty("progressView.progress", view: view)
            }
            progressView.progress = Float(try doubleValue(value))
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
        }
    ]
}

#if !os(tvOS)
@MainActor
private var unavailableOnTVControlMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["switch.isOn", "switchControl.isOn", "uikit.switch.isOn", "uikit.switchControl.isOn"]) { view, value in
            guard let control = view as? UISwitch else {
                throw unsupportedProperty("switch.isOn", view: view)
            }
            control.setOn(try boolValue(value), animated: false)
            control.sendActions(for: .valueChanged)
        },
        mutation(["slider.value", "uikit.slider.value"]) { view, value in
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
        mutation(["stepper.value", "uikit.stepper.value"]) { view, value in
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
        mutation(["pickerView.selectedRow"]) { view, value in
            guard let pickerView = view as? UIPickerView else {
                throw unsupportedProperty("pickerView.selectedRow", view: view)
            }
            let point = try pointValue(value)
            pickerView.selectRow(Int(point.y), inComponent: Int(point.x), animated: false)
        }
    ]
}
#else
@MainActor
private var unavailableOnTVControlMutationDescriptors: [LoupeMutationDescriptor] { [] }
#endif

@MainActor
private var scrollMutationDescriptors: [LoupeMutationDescriptor] {
    commonScrollMutationDescriptors + listSizingMutationDescriptors + unavailableOnTVScrollMutationDescriptors
}

@MainActor
private var commonScrollMutationDescriptors: [LoupeMutationDescriptor] {
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
        mutation(["bounces", "scrollView.bounces"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("bounces", view: view)
            }
            scrollView.bounces = try boolValue(value)
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
private var listSizingMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["collectionView.selfSizingInvalidation"]) { view, value in
            guard let collectionView = view as? UICollectionView else {
                throw unsupportedProperty("collectionView.selfSizingInvalidation", view: view)
            }
            if #available(iOS 16.0, tvOS 16.0, visionOS 1.0, *) {
                collectionView.selfSizingInvalidation = try collectionViewSelfSizingInvalidation(try stringValue(value))
            } else {
                throw LoupeMutationError(
                    code: "unsupported_property",
                    message: "collectionView.selfSizingInvalidation requires iOS/tvOS 16 or newer."
                )
            }
        },
        mutation(["tableView.selfSizingInvalidation"]) { view, value in
            guard let tableView = view as? UITableView else {
                throw unsupportedProperty("tableView.selfSizingInvalidation", view: view)
            }
            if #available(iOS 16.0, tvOS 16.0, visionOS 1.0, *) {
                tableView.selfSizingInvalidation = try tableViewSelfSizingInvalidation(try stringValue(value))
            } else {
                throw LoupeMutationError(
                    code: "unsupported_property",
                    message: "tableView.selfSizingInvalidation requires iOS/tvOS 16 or newer."
                )
            }
        }
    ]
}

#if !os(tvOS)
@MainActor
private var unavailableOnTVScrollMutationDescriptors: [LoupeMutationDescriptor] {
    [
        mutation(["pagingEnabled", "isPagingEnabled", "scrollView.isPagingEnabled"]) { view, value in
            guard let scrollView = view as? UIScrollView else {
                throw unsupportedProperty("pagingEnabled", view: view)
            }
            scrollView.isPagingEnabled = try boolValue(value)
        }
    ]
}
#else
@MainActor
private var unavailableOnTVScrollMutationDescriptors: [LoupeMutationDescriptor] { [] }
#endif

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
        .lowercased()
}

@MainActor
private func unsupportedProperty(_ property: String, view: UIView) -> LoupeMutationError {
    LoupeMutationError(
        code: "unsupported_property",
        message: "Property '\(property)' is not supported for \(mutationTypeName(of: view))."
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

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, *)
private func collectionViewSelfSizingInvalidation(_ rawValue: String) throws -> UICollectionView.SelfSizingInvalidation {
    switch normalizedEnumValue(rawValue) {
    case "disabled":
        return .disabled
    case "enabled":
        return .enabled
    case "enabledincludingconstraints":
        return .enabledIncludingConstraints
    default:
        throw LoupeMutationError(
            code: "invalid_value",
            message: "collectionView.selfSizingInvalidation must be disabled, enabled, or enabledIncludingConstraints."
        )
    }
}

@available(iOS 16.0, tvOS 16.0, visionOS 1.0, *)
private func tableViewSelfSizingInvalidation(_ rawValue: String) throws -> UITableView.SelfSizingInvalidation {
    switch normalizedEnumValue(rawValue) {
    case "disabled":
        return .disabled
    case "enabled":
        return .enabled
    case "enabledincludingconstraints":
        return .enabledIncludingConstraints
    default:
        throw LoupeMutationError(
            code: "invalid_value",
            message: "tableView.selfSizingInvalidation must be disabled, enabled, or enabledIncludingConstraints."
        )
    }
}

private func normalizedEnumValue(_ rawValue: String) -> String {
    rawValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")
        .lowercased()
}

private func mutationTypeName(of value: AnyObject) -> String {
    String(describing: type(of: value))
}
#endif
