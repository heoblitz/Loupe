import Foundation

public struct LoupeScreenMapElement: Codable, Equatable {
    public var ref: String
    public var parentRef: String?
    public var depth: Int
    public var typeName: String
    public var className: String?
    public var role: String?
    public var testID: String?
    public var text: String?
    public var frame: LoupeRect?
    public var style: LoupeStyle?
    public var isEnabled: Bool
    public var isInteractive: Bool
    public var childCount: Int

    public init(
        ref: String,
        parentRef: String?,
        depth: Int,
        typeName: String,
        className: String?,
        role: String?,
        testID: String?,
        text: String?,
        frame: LoupeRect?,
        style: LoupeStyle?,
        isEnabled: Bool,
        isInteractive: Bool,
        childCount: Int
    ) {
        self.ref = ref
        self.parentRef = parentRef
        self.depth = depth
        self.typeName = typeName
        self.className = className
        self.role = role
        self.testID = testID
        self.text = text
        self.frame = frame
        self.style = style
        self.isEnabled = isEnabled
        self.isInteractive = isInteractive
        self.childCount = childCount
    }
}

public struct LoupeScreenMap: Codable, Equatable {
    public var snapshotID: String
    public var screen: LoupeScreen
    public var elements: [LoupeScreenMapElement]

    public init(snapshotID: String, screen: LoupeScreen, elements: [LoupeScreenMapElement]) {
        self.snapshotID = snapshotID
        self.screen = screen
        self.elements = elements
    }
}

public struct LoupeScreenMapOptions: Equatable {
    public var includeHidden: Bool
    public var includeContainers: Bool
    public var maxElements: Int

    public init(includeHidden: Bool = false, includeContainers: Bool = false, maxElements: Int = 200) {
        self.includeHidden = includeHidden
        self.includeContainers = includeContainers
        self.maxElements = maxElements
    }
}

public enum LoupeScreenMapper {
    public static func map(
        _ snapshot: LoupeSnapshot,
        options: LoupeScreenMapOptions = LoupeScreenMapOptions()
    ) -> LoupeScreenMap {
        map(LoupeSnapshotContext(snapshot: snapshot), options: options)
    }

    public static func map(
        _ context: LoupeSnapshotContext,
        options: LoupeScreenMapOptions = LoupeScreenMapOptions()
    ) -> LoupeScreenMap {
        let snapshot = context.snapshot
        let screenRect = context.screenRect
        let hasKnownScreenSize = context.hasKnownScreenSize
        let depths = nodeDepths(snapshot)
        let surfaceVisibleRefs = options.includeHidden ? nil : context.surfaceVisibleRefs
        let elements = snapshot.nodes.values
            .filter { node in
                guard options.includeHidden || LoupeSurfaceVisibility.isSurfaceVisible(
                    node,
                    in: snapshot,
                    visibleRefs: surfaceVisibleRefs
                ) else { return false }
                guard !hasKnownScreenSize || node.frame.map({ $0.intersects(screenRect) }) ?? true else { return false }
                return options.includeContainers || isScreenMapElement(node)
            }
            .sorted(by: screenOrder)
            .prefix(options.maxElements)
            .map { node in
                LoupeScreenMapElement(
                    ref: node.ref,
                    parentRef: node.parentRef,
                    depth: depths[node.ref] ?? 0,
                    typeName: node.typeName,
                    className: node.platform?.className,
                    role: node.role,
                    testID: node.testID,
                    text: context.displayText(for: node),
                    frame: node.frame,
                    style: node.style,
                    isEnabled: node.isEnabled,
                    isInteractive: node.isInteractive,
                    childCount: node.children.count
                )
            }

        return LoupeScreenMap(snapshotID: snapshot.id, screen: snapshot.screen, elements: Array(elements))
    }

    private static func isScreenMapElement(_ node: LoupeNode) -> Bool {
        if let role = node.role, isStructuralRole(role) { return false }
        if LoupeObservationCompactor.displayText(for: node) != nil { return true }
        if node.testID != nil || node.isInteractive { return true }
        if node.role != nil { return true }
        if node.platform?.imageView != nil { return true }
        guard let style = node.style else { return false }
        return isMeaningfulStyle(style)
    }

    private static func isStructuralRole(_ role: String) -> Bool {
        ["application", "scene", "window"].contains(role)
    }

    private static func isMeaningfulStyle(_ style: LoupeStyle) -> Bool {
        if let color = style.backgroundColor, color.alpha > 0 {
            return true
        }
        if let width = style.borderWidth, width > 0 {
            return true
        }
        if let radius = style.cornerRadius, radius > 0 {
            return true
        }
        if let opacity = style.shadowOpacity, opacity > 0 {
            return true
        }
        if let radius = style.shadowRadius, radius > 0 {
            return true
        }
        return false
    }

    private static func nodeDepths(_ snapshot: LoupeSnapshot) -> [String: Int] {
        var depths: [String: Int] = [:]
        func visit(_ ref: String, depth: Int) {
            guard depths[ref] == nil, let node = snapshot.nodes[ref] else { return }
            depths[ref] = depth
            for child in node.children {
                visit(child, depth: depth + 1)
            }
        }
        for root in snapshot.rootRefs {
            visit(root, depth: 0)
        }
        return depths
    }

    private static func screenOrder(_ lhs: LoupeNode, _ rhs: LoupeNode) -> Bool {
        if let lhsFrame = lhs.frame, let rhsFrame = rhs.frame {
            if abs(lhsFrame.y - rhsFrame.y) > 0.5 {
                return lhsFrame.y < rhsFrame.y
            }
            if abs(lhsFrame.x - rhsFrame.x) > 0.5 {
                return lhsFrame.x < rhsFrame.x
            }
        }
        return lhs.ref < rhs.ref
    }
}
