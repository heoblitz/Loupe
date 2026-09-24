import Foundation

/// Both views of the same capture, so action discovery need not walk the app twice
/// or associate native source refs with a different snapshot.
public struct LoupeAccessibilityActionObservation: Codable, Equatable, Sendable {
    public var snapshot: LoupeSnapshot
    public var tree: LoupeAccessibilityTree

    public init(snapshot: LoupeSnapshot, tree: LoupeAccessibilityTree) {
        self.snapshot = snapshot
        self.tree = tree
    }
}
