import Foundation

public struct LoupeDesignDocument: Codable, Equatable {
    public var frame: LoupeDesignFrame
    public var nodes: [LoupeDesignNode]

    public init(frame: LoupeDesignFrame, nodes: [LoupeDesignNode]) {
        self.frame = frame
        self.nodes = nodes
    }
}

public struct LoupeDesignFrame: Codable, Equatable {
    public var name: String
    public var width: Double
    public var height: Double

    public init(name: String, width: Double, height: Double) {
        self.name = name
        self.width = width
        self.height = height
    }
}

public struct LoupeDesignNode: Codable, Equatable {
    public var id: String?
    public var name: String
    public var role: String?
    public var text: String?
    public var frame: LoupeRect
    public var style: LoupeDesignStyle?

    public init(
        id: String? = nil,
        name: String,
        role: String? = nil,
        text: String? = nil,
        frame: LoupeRect,
        style: LoupeDesignStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.text = text
        self.frame = frame
        self.style = style
    }
}

public struct LoupeDesignStyle: Codable, Equatable {
    public var backgroundColor: String?
    public var textColor: String?
    public var cornerRadius: Double?
    public var fontName: String?
    public var fontSize: Double?

    public init(
        backgroundColor: String? = nil,
        textColor: String? = nil,
        cornerRadius: Double? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.cornerRadius = cornerRadius
        self.fontName = fontName
        self.fontSize = fontSize
    }
}

public struct LoupeDesignComparisonOptions: Equatable {
    public var frameTolerance: Double
    public var colorTolerance: Double
    public var cornerRadiusTolerance: Double
    public var fontSizeTolerance: Double
    public var maxMatchDistance: Double
    public var includeUnexpectedAppNodes: Bool

    public init(
        frameTolerance: Double = 2,
        colorTolerance: Double = 0.03,
        cornerRadiusTolerance: Double = 1,
        fontSizeTolerance: Double = 1,
        maxMatchDistance: Double = 24,
        includeUnexpectedAppNodes: Bool = true
    ) {
        self.frameTolerance = frameTolerance
        self.colorTolerance = colorTolerance
        self.cornerRadiusTolerance = cornerRadiusTolerance
        self.fontSizeTolerance = fontSizeTolerance
        self.maxMatchDistance = maxMatchDistance
        self.includeUnexpectedAppNodes = includeUnexpectedAppNodes
    }
}

public enum LoupeDesignComparisonIssueKind: String, Codable, Equatable {
    case missingDesignNode
    case unexpectedAppNode
    case frameDelta
    case backgroundColorDelta
    case textColorDelta
    case cornerRadiusDelta
    case fontNameDelta
    case fontSizeDelta
}

public struct LoupeDesignComparisonIssue: Codable, Equatable {
    public var kind: LoupeDesignComparisonIssueKind
    public var designID: String?
    public var designName: String?
    public var ref: String?
    public var testID: String?
    public var property: String?
    public var expected: String?
    public var actual: String?
    public var measuredDelta: Double?
    public var frame: LoupeRect?
    public var message: String

    public init(
        kind: LoupeDesignComparisonIssueKind,
        designID: String? = nil,
        designName: String? = nil,
        ref: String? = nil,
        testID: String? = nil,
        property: String? = nil,
        expected: String? = nil,
        actual: String? = nil,
        measuredDelta: Double? = nil,
        frame: LoupeRect? = nil,
        message: String
    ) {
        self.kind = kind
        self.designID = designID
        self.designName = designName
        self.ref = ref
        self.testID = testID
        self.property = property
        self.expected = expected
        self.actual = actual
        self.measuredDelta = measuredDelta
        self.frame = frame
        self.message = message
    }
}

public struct LoupeDesignNodeMatch: Codable, Equatable {
    public var designID: String?
    public var designName: String
    public var ref: String
    public var testID: String?
    public var strategy: String

    public init(designID: String?, designName: String, ref: String, testID: String?, strategy: String) {
        self.designID = designID
        self.designName = designName
        self.ref = ref
        self.testID = testID
        self.strategy = strategy
    }
}

public struct LoupeDesignComparison: Codable, Equatable {
    public var snapshotID: String
    public var designFrameName: String
    public var matchedCount: Int
    public var issueCount: Int
    public var matches: [LoupeDesignNodeMatch]
    public var issues: [LoupeDesignComparisonIssue]

    public init(
        snapshotID: String,
        designFrameName: String,
        matches: [LoupeDesignNodeMatch],
        issues: [LoupeDesignComparisonIssue]
    ) {
        self.snapshotID = snapshotID
        self.designFrameName = designFrameName
        self.matchedCount = matches.count
        self.issueCount = issues.count
        self.matches = matches
        self.issues = issues
    }
}

public enum LoupeDesignComparator {
    public static func compare(
        snapshot: LoupeSnapshot,
        design: LoupeDesignDocument,
        options: LoupeDesignComparisonOptions = LoupeDesignComparisonOptions()
    ) -> LoupeDesignComparison {
        let screenRect = LoupeRect(x: 0, y: 0, width: snapshot.screen.size.width, height: snapshot.screen.size.height)
        let nodes = snapshot.nodes.values
            .filter { node in
                guard node.isVisible, let frame = node.frame else { return false }
                return frame.intersects(screenRect)
            }

        var consumedRefs = Set<String>()
        var matches: [LoupeDesignNodeMatch] = []
        var issues: [LoupeDesignComparisonIssue] = []

        for designNode in design.nodes {
            guard let match = matchNode(designNode, in: nodes, consumedRefs: consumedRefs, options: options) else {
                issues.append(
                    LoupeDesignComparisonIssue(
                        kind: .missingDesignNode,
                        designID: designNode.id,
                        designName: designNode.name,
                        frame: designNode.frame,
                        message: "Design node \(displayName(designNode)) was not found in the app snapshot"
                    )
                )
                continue
            }

            consumedRefs.insert(match.node.ref)
            matches.append(
                LoupeDesignNodeMatch(
                    designID: designNode.id,
                    designName: designNode.name,
                    ref: match.node.ref,
                    testID: match.node.testID,
                    strategy: match.strategy
                )
            )
            issues.append(contentsOf: propertyIssues(designNode: designNode, appNode: match.node, options: options))
        }

        if options.includeUnexpectedAppNodes {
            let designIDs = Set(design.nodes.compactMap(\.id))
            let unexpected = nodes
                .filter { node in
                    guard let testID = node.testID, !testID.isEmpty else { return false }
                    guard !testID.hasPrefix("com.apple.") else { return false }
                    return !consumedRefs.contains(node.ref) && !designIDs.contains(testID)
                }
                .sorted { ($0.testID ?? $0.ref) < ($1.testID ?? $1.ref) }

            issues.append(contentsOf: unexpected.map { node in
                LoupeDesignComparisonIssue(
                    kind: .unexpectedAppNode,
                    ref: node.ref,
                    testID: node.testID,
                    frame: node.frame,
                    message: "App node \(node.testID ?? node.ref) was not present in the design document"
                )
            })
        }

        return LoupeDesignComparison(
            snapshotID: snapshot.id,
            designFrameName: design.frame.name,
            matches: matches,
            issues: issues
        )
    }

    private static func matchNode(
        _ designNode: LoupeDesignNode,
        in nodes: [LoupeNode],
        consumedRefs: Set<String>,
        options: LoupeDesignComparisonOptions
    ) -> (node: LoupeNode, strategy: String)? {
        let available = nodes.filter { !consumedRefs.contains($0.ref) }

        if let id = designNode.id, !id.isEmpty,
           let node = available.first(where: { $0.testID == id || $0.accessibility?.identifier == id }) {
            return (node, "testID")
        }

        if let role = designNode.role,
           let text = designNode.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           let node = available.first(where: { $0.role == role && displayText($0) == text }) {
            return (node, "roleText")
        }

        if let role = designNode.role,
           let nearest = nearestNode(to: designNode.frame, in: available.filter({ $0.role == role }), options: options) {
            return (nearest, "roleGeometry")
        }

        if let nearest = nearestNode(to: designNode.frame, in: available, options: options) {
            return (nearest, "geometry")
        }

        return nil
    }

    private static func nearestNode(
        to frame: LoupeRect,
        in nodes: [LoupeNode],
        options: LoupeDesignComparisonOptions
    ) -> LoupeNode? {
        nodes
            .compactMap { node -> (node: LoupeNode, distance: Double)? in
                guard let nodeFrame = node.frame else { return nil }
                let distance = centerDistance(frame, nodeFrame)
                guard distance <= options.maxMatchDistance else { return nil }
                return (node, distance)
            }
            .sorted { $0.distance < $1.distance }
            .first?
            .node
    }

    private static func propertyIssues(
        designNode: LoupeDesignNode,
        appNode: LoupeNode,
        options: LoupeDesignComparisonOptions
    ) -> [LoupeDesignComparisonIssue] {
        var issues: [LoupeDesignComparisonIssue] = []

        if let appFrame = appNode.frame {
            let delta = rectDelta(designNode.frame, appFrame)
            if delta > options.frameTolerance {
                issues.append(
                    issue(
                        .frameDelta,
                        designNode: designNode,
                        appNode: appNode,
                        property: "frame",
                        expected: rectString(designNode.frame),
                        actual: rectString(appFrame),
                        measuredDelta: delta,
                        message: "\(displayName(designNode)) frame differs by \(delta)pt"
                    )
                )
            }
        }

        guard let style = designNode.style else {
            return issues
        }

        appendColorIssue(
            kind: .backgroundColorDelta,
            property: "backgroundColor",
            expected: style.backgroundColor,
            actual: appNode.style?.backgroundColor,
            designNode: designNode,
            appNode: appNode,
            options: options,
            to: &issues
        )
        appendColorIssue(
            kind: .textColorDelta,
            property: "textColor",
            expected: style.textColor,
            actual: appNode.style?.textColor,
            designNode: designNode,
            appNode: appNode,
            options: options,
            to: &issues
        )
        appendNumericIssue(
            .cornerRadiusDelta,
            property: "cornerRadius",
            expected: style.cornerRadius,
            actual: appNode.style?.cornerRadius,
            tolerance: options.cornerRadiusTolerance,
            designNode: designNode,
            appNode: appNode,
            to: &issues
        )
        appendStringIssue(
            .fontNameDelta,
            property: "fontName",
            expected: style.fontName,
            actual: appNode.style?.fontName,
            designNode: designNode,
            appNode: appNode,
            to: &issues
        )
        appendNumericIssue(
            .fontSizeDelta,
            property: "fontSize",
            expected: style.fontSize,
            actual: appNode.style?.fontSize,
            tolerance: options.fontSizeTolerance,
            designNode: designNode,
            appNode: appNode,
            to: &issues
        )

        return issues
    }

    private static func appendColorIssue(
        kind: LoupeDesignComparisonIssueKind,
        property: String,
        expected: String?,
        actual: LoupeColor?,
        designNode: LoupeDesignNode,
        appNode: LoupeNode,
        options: LoupeDesignComparisonOptions,
        to issues: inout [LoupeDesignComparisonIssue]
    ) {
        guard let expected else { return }
        guard let expectedColor = color(fromHex: expected), let actual else {
            issues.append(
                issue(
                    kind,
                    designNode: designNode,
                    appNode: appNode,
                    property: property,
                    expected: expected,
                    actual: actual.map(colorString),
                    message: "\(displayName(designNode)) \(property) is missing or invalid"
                )
            )
            return
        }

        let delta = colorDelta(expectedColor, actual)
        guard delta > options.colorTolerance else {
            return
        }
        issues.append(
            issue(
                kind,
                designNode: designNode,
                appNode: appNode,
                property: property,
                expected: expected,
                actual: colorString(actual),
                measuredDelta: delta,
                message: "\(displayName(designNode)) \(property) differs by \(delta)"
            )
        )
    }

    private static func appendNumericIssue(
        _ kind: LoupeDesignComparisonIssueKind,
        property: String,
        expected: Double?,
        actual: Double?,
        tolerance: Double,
        designNode: LoupeDesignNode,
        appNode: LoupeNode,
        to issues: inout [LoupeDesignComparisonIssue]
    ) {
        guard let expected else { return }
        guard let actual else {
            issues.append(
                issue(
                    kind,
                    designNode: designNode,
                    appNode: appNode,
                    property: property,
                    expected: String(describing: expected),
                    actual: nil,
                    message: "\(displayName(designNode)) \(property) is missing"
                )
            )
            return
        }
        let delta = abs(expected - actual)
        guard delta > tolerance else { return }
        issues.append(
            issue(
                kind,
                designNode: designNode,
                appNode: appNode,
                property: property,
                expected: String(describing: expected),
                actual: String(describing: actual),
                measuredDelta: delta,
                message: "\(displayName(designNode)) \(property) differs by \(delta)"
            )
        )
    }

    private static func appendStringIssue(
        _ kind: LoupeDesignComparisonIssueKind,
        property: String,
        expected: String?,
        actual: String?,
        designNode: LoupeDesignNode,
        appNode: LoupeNode,
        to issues: inout [LoupeDesignComparisonIssue]
    ) {
        guard let expected, !expected.isEmpty, expected != actual else {
            return
        }
        issues.append(
            issue(
                kind,
                designNode: designNode,
                appNode: appNode,
                property: property,
                expected: expected,
                actual: actual,
                message: "\(displayName(designNode)) \(property) differs"
            )
        )
    }

    private static func issue(
        _ kind: LoupeDesignComparisonIssueKind,
        designNode: LoupeDesignNode,
        appNode: LoupeNode,
        property: String?,
        expected: String?,
        actual: String?,
        measuredDelta: Double? = nil,
        message: String
    ) -> LoupeDesignComparisonIssue {
        LoupeDesignComparisonIssue(
            kind: kind,
            designID: designNode.id,
            designName: designNode.name,
            ref: appNode.ref,
            testID: appNode.testID,
            property: property,
            expected: expected,
            actual: actual,
            measuredDelta: measuredDelta,
            frame: appNode.frame,
            message: message
        )
    }

    private static func displayName(_ node: LoupeDesignNode) -> String {
        node.id ?? node.name
    }

    private static func displayText(_ node: LoupeNode) -> String? {
        LoupeObservationCompactor.displayText(for: node)
    }

    private static func centerDistance(_ lhs: LoupeRect, _ rhs: LoupeRect) -> Double {
        let dx = (lhs.x + lhs.width / 2) - (rhs.x + rhs.width / 2)
        let dy = (lhs.y + lhs.height / 2) - (rhs.y + rhs.height / 2)
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func rectDelta(_ lhs: LoupeRect, _ rhs: LoupeRect) -> Double {
        [
            abs(lhs.x - rhs.x),
            abs(lhs.y - rhs.y),
            abs(lhs.width - rhs.width),
            abs(lhs.height - rhs.height),
        ].max() ?? 0
    }

    private static func rectString(_ rect: LoupeRect) -> String {
        "\(format(rect.x)),\(format(rect.y)),\(format(rect.width)),\(format(rect.height))"
    }

    private static func colorString(_ color: LoupeColor) -> String {
        let red = Int((clamp(color.red) * 255).rounded())
        let green = Int((clamp(color.green) * 255).rounded())
        let blue = Int((clamp(color.blue) * 255).rounded())
        let alpha = Int((clamp(color.alpha) * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    private static func colorDelta(_ lhs: LoupeColor, _ rhs: LoupeColor) -> Double {
        [
            abs(lhs.red - rhs.red),
            abs(lhs.green - rhs.green),
            abs(lhs.blue - rhs.blue),
            abs(lhs.alpha - rhs.alpha),
        ].max() ?? 0
    }

    private static func color(fromHex rawValue: String) -> LoupeColor? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard value.count == 6 || value.count == 8,
              let integer = UInt32(value, radix: 16) else {
            return nil
        }

        let red: UInt32
        let green: UInt32
        let blue: UInt32
        let alpha: UInt32
        if value.count == 6 {
            red = (integer & 0xFF0000) >> 16
            green = (integer & 0x00FF00) >> 8
            blue = integer & 0x0000FF
            alpha = 0xFF
        } else {
            red = (integer & 0xFF000000) >> 24
            green = (integer & 0x00FF0000) >> 16
            blue = (integer & 0x0000FF00) >> 8
            alpha = integer & 0x000000FF
        }

        return LoupeColor(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            alpha: Double(alpha) / 255
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded.rounded() == rounded {
            return String(Int(rounded))
        }
        return String(rounded)
    }
}
