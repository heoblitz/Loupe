import Foundation

public final class LoupeSnapshotContext {
    public let snapshot: LoupeSnapshot
    public let screenRect: LoupeRect
    public let hasKnownScreenSize: Bool

    private let refsByTestID: [String: [String]]
    private let refsByRole: [String: [String]]
    private let refsByDisplayText: [String: [String]]
    private let displayTextByRef: [String: String]

    public lazy var surfaceVisibleRefs: Set<String> = {
        LoupeSurfaceVisibility.visibleNodeRefs(in: snapshot)
    }()

    public lazy var occlusionVisibleRefs: Set<String> = {
        LoupeSurfaceVisibility.visibleNodeRefs(in: snapshot, includesOffscreen: true)
    }()

    public init(snapshot: LoupeSnapshot) {
        self.snapshot = snapshot
        screenRect = LoupeRect(
            x: 0,
            y: 0,
            width: snapshot.screen.size.width,
            height: snapshot.screen.size.height
        )
        hasKnownScreenSize = snapshot.screen.size.width > 0 && snapshot.screen.size.height > 0

        var refsByTestID: [String: [String]] = [:]
        var refsByRole: [String: [String]] = [:]
        var refsByDisplayText: [String: [String]] = [:]
        var displayTextByRef: [String: String] = [:]

        for node in snapshot.nodes.values {
            if let testID = nonEmpty(node.testID) {
                refsByTestID[testID, default: []].append(node.ref)
            }
            if let metadataID = nonEmpty(stringMetadata("id", from: node.custom)),
               metadataID != nonEmpty(node.testID) {
                refsByTestID[metadataID, default: []].append(node.ref)
            }
            if let role = nonEmpty(node.role) {
                refsByRole[role, default: []].append(node.ref)
            }
            if let text = LoupeObservationCompactor.displayText(for: node) {
                displayTextByRef[node.ref] = text
                refsByDisplayText[text, default: []].append(node.ref)
            }
        }

        self.refsByTestID = refsByTestID
        self.refsByRole = refsByRole
        self.refsByDisplayText = refsByDisplayText
        self.displayTextByRef = displayTextByRef
    }

    public func node(ref: String) -> LoupeNode? {
        snapshot.nodes[ref]
    }

    public func displayText(for node: LoupeNode) -> String? {
        displayTextByRef[node.ref] ?? LoupeObservationCompactor.displayText(for: node)
    }

    public func visibleRefs(for mode: LoupeQueryVisibilityMode) -> Set<String>? {
        switch mode {
        case .surface:
            return surfaceVisibleRefs
        case .occlusion:
            return occlusionVisibleRefs
        case .raw:
            return nil
        }
    }

    public func candidateRefs(for selector: LoupeSelector) -> [String]? {
        switch selector {
        case let .ref(ref):
            return snapshot.nodes[ref] == nil ? [] : [ref]
        case let .testID(testID):
            return refsByTestID[testID] ?? []
        case let .role(role):
            return refsByRole[role] ?? []
        case let .roleAndText(role, _, _):
            return refsByRole[role] ?? []
        case let .text(text, exact: true):
            return refsByDisplayText[text] ?? []
        case .text(_, exact: false):
            return nil
        }
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private func stringMetadata(_ key: String, from metadata: [String: LoupeMetadataValue]) -> String? {
    guard case let .string(value) = metadata[key] else {
        return nil
    }
    return value
}
