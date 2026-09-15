import Foundation
import LoupeCore

#if os(watchOS)
import WatchKit

@MainActor
public final class LoupeAgent {
    private let runtime: LoupeRuntime

    public init() {
        runtime = .shared
    }

    init(runtime: LoupeRuntime) {
        self.runtime = runtime
    }

    public func captureSnapshot() -> LoupeSnapshot {
        let appRef = "n0"
        var nodes: [String: LoupeNode] = [:]
        let probes = runtime.registeredProbes()
        let screen = currentWatchScreen()
        let probeRefs = probes.indices.map { "n\($0 + 1)" }
        let parentRefs = probeParentRefs(probes: probes, refs: probeRefs, appRef: appRef)
        for (index, probe) in probes.enumerated() {
            let ref = "n\(index + 1)"
            let customMetadata = mergedMetadata(probe.metadata, with: runtime.metadata(forTestID: probe.id))
            nodes[ref] = LoupeNode(
                ref: ref,
                parentRef: parentRefs[ref] ?? appRef,
                kind: .view,
                typeName: "LoupeWatchProbe",
                role: probe.role,
                testID: probe.id,
                label: probe.label,
                text: probe.label,
                frame: probe.frame,
                isVisible: probe.isVisible,
                isEnabled: probe.isEnabled,
                isInteractive: probe.isInteractive,
                accessibility: LoupeAccessibility(
                    identifier: probe.id,
                    label: probe.label ?? probe.id,
                    traits: probe.isInteractive ? ["button"] : [],
                    frame: probe.frame,
                    activationPoint: probe.frame?.center,
                    isElement: true
                ),
                swiftui: loupeSwiftUIProperties(
                    backingTypeName: "LoupeWatchProbe",
                    frameworkBundleIdentifier: nil,
                    customMetadata: customMetadata
                ),
                custom: customMetadata
            )
        }

        for ref in probeRefs {
            guard let parentRef = parentRefs[ref] else {
                continue
            }
            if parentRef != appRef {
                nodes[parentRef]?.children.append(ref)
            }
        }
        let rootProbeRefs = probeRefs.filter { parentRefs[$0] == appRef }

        nodes[appRef] = LoupeNode(
            ref: appRef,
            parentRef: nil,
            kind: .application,
            typeName: "WKApplication",
            role: "application",
            frame: LoupeRect(x: 0, y: 0, width: screen.size.width, height: screen.size.height),
            isVisible: true,
            isEnabled: true,
            isInteractive: false,
            custom: [
                "platform": .string("watchOS"),
                "observationBackend": .string("registered-probes"),
            ],
            children: rootProbeRefs
        )

        return LoupeSnapshot(
            id: UUID().uuidString,
            capturedAt: Date(),
            screen: screen,
            rootRefs: [appRef],
            nodes: nodes
        )
    }

    public func captureAccessibilityTree() -> LoupeAccessibilityTree {
        LoupeAccessibilityTree.build(from: captureSnapshot())
    }

    public func captureAccessibilityActionTree() -> LoupeAccessibilityTree {
        let snapshot = captureSnapshot()
        return LoupeAccessibilityTree(snapshotID: snapshot.id, screen: snapshot.screen, rootRefs: [], nodes: [:])
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

    func defaultsEntry(key: String) -> LoupeStateEntry {
        LoupeStateEntry(key: key, value: metadataValue(fromDefault: UserDefaults.standard.object(forKey: key)))
    }

    func setDefault(_ request: LoupeStateMutationRequest) -> LoupeStateMutationResponse {
        let before = metadataValue(fromDefault: UserDefaults.standard.object(forKey: request.key))
        if let value = request.value {
            UserDefaults.standard.set(defaultObject(from: value), forKey: request.key)
        } else {
            UserDefaults.standard.removeObject(forKey: request.key)
        }
        let after = metadataValue(fromDefault: UserDefaults.standard.object(forKey: request.key))
        return LoupeStateMutationResponse(key: request.key, before: before, after: after)
    }

    func keychainItems() -> [LoupeKeychainItem] {
        []
    }

    func setEnvironment(_ request: LoupeEnvironmentMutationRequest) throws -> LoupeEnvironmentMutationResponse {
        if let appearance = request.appearance, !appearance.isEmpty {
            throw LoupeDiagnosticError(message: "watchOS appearance mutation is not supported")
        }
        return currentEnvironment()
    }

    func currentEnvironment() -> LoupeEnvironmentMutationResponse {
        LoupeEnvironmentMutationResponse(appearance: nil)
    }

    public func hitTest(point: LoupePoint) -> LoupeHitTestReport {
        LoupeHitTestReport(point: point)
    }

    public func responderChain(selector: LoupeSelector) -> LoupeHitTestReport? {
        nil
    }

    func mutationCapabilities() -> [LoupeMutationCapability] {
        []
    }

    func mutate(_ request: LoupeMutationRequest) throws -> LoupeMutationResponse {
        throw LoupeDiagnosticError(message: "watchOS mutation backend is not supported")
    }

    func activate(_ request: LoupeActivationRequest) throws -> LoupeActivationResponse {
        throw LoupeDiagnosticError(message: "watchOS activation backend is not supported")
    }

    func mutateConstraint(_ request: LoupeConstraintMutationRequest) throws -> LoupeConstraintMutationResponse {
        throw LoupeDiagnosticError(message: "watchOS constraint mutation backend is not supported")
    }
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

private func mergedMetadata(
    _ base: [String: LoupeMetadataValue],
    with override: [String: LoupeMetadataValue]
) -> [String: LoupeMetadataValue] {
    var merged = base
    merged.merge(override) { _, new in new }
    return merged
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

private func currentWatchScreen() -> LoupeScreen {
    let device = WKInterfaceDevice.current()
    let bounds = device.screenBounds
    return LoupeScreen(
        size: LoupeSize(
            width: finiteDouble(Double(bounds.width)) ?? 0,
            height: finiteDouble(Double(bounds.height)) ?? 0
        ),
        scale: finiteDouble(Double(device.screenScale)) ?? 1
    )
}

private func finiteDouble(_ value: Double) -> Double? {
    value.isFinite ? value : nil
}

private func probeParentRefs(
    probes: [LoupeRegisteredProbe],
    refs: [String],
    appRef: String
) -> [String: String] {
    var parents: [String: String] = [:]
    for (index, probe) in probes.enumerated() {
        let ref = refs[index]
        guard let frame = probe.frame else {
            parents[ref] = appRef
            continue
        }

        let parentIndex = probes.indices
            .filter { $0 != index }
            .filter { candidateIndex in
                guard let candidateFrame = probes[candidateIndex].frame else {
                    return false
                }
                guard candidateFrame.area > frame.area + 1 else {
                    return false
                }
                return candidateFrame.contains(frame, tolerance: 1)
            }
            .min { lhs, rhs in
                guard let lhsFrame = probes[lhs].frame, let rhsFrame = probes[rhs].frame else {
                    return lhs < rhs
                }
                let lhsArea = lhsFrame.area
                let rhsArea = rhsFrame.area
                if abs(lhsArea - rhsArea) > 0.001 {
                    return lhsArea < rhsArea
                }
                // Equal-size SwiftUI probes often represent nested regions that
                // register later than the broad root probe.
                return lhs > rhs
            }

        parents[ref] = parentIndex.map { refs[$0] } ?? appRef
    }
    return parents
}

private extension LoupeRect {
    var area: Double {
        max(0, width) * max(0, height)
    }
}
#endif
