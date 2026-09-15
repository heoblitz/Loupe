import Foundation

/// Geometry derived from two nodes in the same captured window. Values that
/// require text layout or image extraction are deliberately marked unavailable
/// instead of being guessed from a view frame.
public struct LoupeNodeRelation: Codable, Equatable, Sendable {
    public var firstRef: String
    public var secondRef: String
    public var windowRef: String?
    public var topDelta: Double
    public var bottomDelta: Double
    public var centerYDelta: Double
    public var horizontalGap: Double
    public var horizontalOverlap: Double
    public var verticalOverlap: Double
    public var overlapArea: Double
    public var baseline: String
    public var iconBounds: String

    public init(
        firstRef: String, secondRef: String, windowRef: String?, topDelta: Double,
        bottomDelta: Double, centerYDelta: Double, horizontalGap: Double,
        horizontalOverlap: Double, verticalOverlap: Double, overlapArea: Double,
        baseline: String = "unavailable", iconBounds: String = "unavailable"
    ) {
        self.firstRef = firstRef
        self.secondRef = secondRef
        self.windowRef = windowRef
        self.topDelta = topDelta
        self.bottomDelta = bottomDelta
        self.centerYDelta = centerYDelta
        self.horizontalGap = horizontalGap
        self.horizontalOverlap = horizontalOverlap
        self.verticalOverlap = verticalOverlap
        self.overlapArea = overlapArea
        self.baseline = baseline
        self.iconBounds = iconBounds
    }
}

public enum CompareNodes {
    /// Returns nil when either node has no captured screen frame or belongs to a
    /// different window.  Cross-window distances are not meaningful coordinates.
    public static func relation(
        first firstRef: String, second secondRef: String, in snapshot: LoupeSnapshot
    ) -> LoupeNodeRelation? {
        guard let first = snapshot.nodes[firstRef], let second = snapshot.nodes[secondRef],
              let firstFrame = first.frame, let secondFrame = second.frame,
              !firstFrame.isEmpty, !secondFrame.isEmpty else { return nil }
        let firstWindow = windowRef(for: first, in: snapshot)
        let secondWindow = windowRef(for: second, in: snapshot)
        guard firstWindow == secondWindow else { return nil }

        let overlapWidth = max(0, min(firstFrame.maxX, secondFrame.maxX) - max(firstFrame.x, secondFrame.x))
        let overlapHeight = max(0, min(firstFrame.maxY, secondFrame.maxY) - max(firstFrame.y, secondFrame.y))
        let horizontalGap: Double
        if overlapWidth > 0 { horizontalGap = 0 }
        else if secondFrame.x >= firstFrame.maxX { horizontalGap = secondFrame.x - firstFrame.maxX }
        else { horizontalGap = firstFrame.x - secondFrame.maxX }

        return LoupeNodeRelation(
            firstRef: firstRef, secondRef: secondRef, windowRef: firstWindow,
            topDelta: secondFrame.y - firstFrame.y,
            bottomDelta: secondFrame.maxY - firstFrame.maxY,
            centerYDelta: secondFrame.center.y - firstFrame.center.y,
            horizontalGap: horizontalGap, horizontalOverlap: overlapWidth,
            verticalOverlap: overlapHeight, overlapArea: overlapWidth * overlapHeight
        )
    }

    private static func windowRef(for node: LoupeNode, in snapshot: LoupeSnapshot) -> String? {
        var current: LoupeNode? = node
        var visited = Set<String>()
        while let value = current, visited.insert(value.ref).inserted {
            if value.kind == .window { return value.ref }
            current = value.parentRef.flatMap { snapshot.nodes[$0] }
        }
        return nil
    }
}
