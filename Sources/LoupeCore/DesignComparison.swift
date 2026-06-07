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
    public var aliases: [String]?
    public var name: String
    public var role: String?
    public var text: String?
    public var frame: LoupeRect
    public var style: LoupeDesignStyle?

    public init(
        id: String? = nil,
        aliases: [String]? = nil,
        name: String,
        role: String? = nil,
        text: String? = nil,
        frame: LoupeRect,
        style: LoupeDesignStyle? = nil
    ) {
        self.id = id
        self.aliases = aliases
        self.name = name
        self.role = role
        self.text = text
        self.frame = frame
        self.style = style
    }
}

private extension LoupeDesignNode {
    var matchIdentifiers: [String] {
        var seen = Set<String>()
        return ([id] + (aliases ?? []).map(Optional.some)).compactMap { value in
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return nil
            }
            guard seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
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
    case roleDelta
    case textDelta
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

public struct LoupeDesignMutationSuggestion: Codable, Equatable {
    public var issueKind: LoupeDesignComparisonIssueKind
    public var designID: String?
    public var designName: String?
    public var ref: String
    public var testID: String?
    public var property: String
    public var value: LoupeMutationValue
    public var valueType: String
    public var valueLabel: String
    public var reason: String

    public init(
        issueKind: LoupeDesignComparisonIssueKind,
        designID: String? = nil,
        designName: String? = nil,
        ref: String,
        testID: String? = nil,
        property: String,
        value: LoupeMutationValue,
        valueType: String,
        valueLabel: String,
        reason: String
    ) {
        self.issueKind = issueKind
        self.designID = designID
        self.designName = designName
        self.ref = ref
        self.testID = testID
        self.property = property
        self.value = value
        self.valueType = valueType
        self.valueLabel = valueLabel
        self.reason = reason
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
    public var suggestions: [LoupeDesignMutationSuggestion]

    public init(
        snapshotID: String,
        designFrameName: String,
        matches: [LoupeDesignNodeMatch],
        issues: [LoupeDesignComparisonIssue],
        suggestions: [LoupeDesignMutationSuggestion]? = nil
    ) {
        self.snapshotID = snapshotID
        self.designFrameName = designFrameName
        self.matchedCount = matches.count
        self.issueCount = issues.count
        self.matches = matches
        self.issues = issues
        self.suggestions = suggestions ?? designMutationSuggestions(from: issues)
    }
}

private func designMutationSuggestions(from issues: [LoupeDesignComparisonIssue]) -> [LoupeDesignMutationSuggestion] {
    issues.compactMap { issue in
        guard let ref = issue.ref,
              let property = suggestedMutationProperty(for: issue.kind),
              let expected = issue.expected else {
            return nil
        }
        guard issue.property != "visualFrame" else {
            return nil
        }

        let value: LoupeMutationValue
        let valueType: String
        let reason: String

        switch issue.kind {
        case .textDelta:
            value = .string(expected)
            valueType = "string"
            reason = "Probe expected copy before patching source text."
        case .frameDelta:
            guard let rect = designRect(from: expected) else { return nil }
            value = .rect(rect)
            valueType = "rect"
            reason = "Probe target frame; Auto Layout may restore it, so verify effective state."
        case .backgroundColorDelta, .textColorDelta:
            guard let color = designColor(fromHex: expected) else { return nil }
            value = .color(color)
            valueType = "color"
            reason = "Probe expected color before patching source constants."
        case .cornerRadiusDelta, .fontSizeDelta:
            guard let number = Double(expected), number.isFinite else { return nil }
            value = number.rounded() == number ? .int(Int(number)) : .double(number)
            valueType = "number"
            reason = "Probe expected scalar before patching source constants."
        case .missingDesignNode, .unexpectedAppNode, .roleDelta, .fontNameDelta:
            return nil
        }

        return LoupeDesignMutationSuggestion(
            issueKind: issue.kind,
            designID: issue.designID,
            designName: issue.designName,
            ref: ref,
            testID: issue.testID,
            property: property,
            value: value,
            valueType: valueType,
            valueLabel: expected,
            reason: reason
        )
    }
}

private func suggestedMutationProperty(for kind: LoupeDesignComparisonIssueKind) -> String? {
    switch kind {
    case .textDelta:
        return "text"
    case .frameDelta:
        return "frame"
    case .backgroundColorDelta:
        return "backgroundColor"
    case .textColorDelta:
        return "textColor"
    case .cornerRadiusDelta:
        return "cornerRadius"
    case .fontSizeDelta:
        return "fontSize"
    case .missingDesignNode, .unexpectedAppNode, .roleDelta, .fontNameDelta:
        return nil
    }
}

private func designRect(from value: String) -> LoupeRect? {
    let parts = value.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    guard parts.count == 4, parts.allSatisfy(\.isFinite) else {
        return nil
    }
    return LoupeRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
}

private func designColor(fromHex rawValue: String) -> LoupeColor? {
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

public enum LoupeDesignComparator {
    public static func compare(
        snapshot: LoupeSnapshot,
        design: LoupeDesignDocument,
        options: LoupeDesignComparisonOptions = LoupeDesignComparisonOptions()
    ) -> LoupeDesignComparison {
        let comparisonSnapshot = snapshotByNormalizingWindowFrames(snapshot, design: design)
        let screenRect = LoupeRect(
            x: 0,
            y: 0,
            width: comparisonSnapshot.screen.size.width,
            height: comparisonSnapshot.screen.size.height
        )
        let nodes = comparisonSnapshot.nodes.values
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
            issues.append(
                contentsOf: propertyIssues(
                    designNode: designNode,
                    appNode: match.node,
                    snapshot: comparisonSnapshot,
                    options: options
                )
            )
        }

        if options.includeUnexpectedAppNodes {
            let designIDs = Set(design.nodes.compactMap(\.id))
            let unexpected = nodes
                .filter { node in
                    guard let testID = node.testID, !testID.isEmpty else { return false }
                    guard !testID.hasPrefix("com.apple.") else { return false }
                    guard !isFullScreenWrapperNoise(node, design: design, snapshot: comparisonSnapshot, options: options) else {
                        return false
                    }
                    guard !isStatusChromeIndicatorNoise(node) else {
                        return false
                    }
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
            snapshotID: comparisonSnapshot.id,
            designFrameName: design.frame.name,
            matches: matches,
            issues: issues
        )
    }

    private static func snapshotByNormalizingWindowFrames(
        _ snapshot: LoupeSnapshot,
        design: LoupeDesignDocument
    ) -> LoupeSnapshot {
        let designRect = LoupeRect(x: 0, y: 0, width: design.frame.width, height: design.frame.height)
        let windows = snapshot.nodes.values
            .filter { $0.kind == .window || $0.role == "window" }
            .compactMap { node -> (ref: String, frame: LoupeRect)? in
                guard let frame = node.frame, !frame.isEmpty else { return nil }
                return (node.ref, frame)
            }
        guard !windows.isEmpty else {
            return snapshot
        }

        var normalizedNodes = snapshot.nodes
        for node in snapshot.nodes.values {
            guard let frame = node.frame,
                  let windowFrame = ancestorWindowFrame(for: node, in: snapshot, windows: windows),
                  shouldNormalize(frame, within: windowFrame, designRect: designRect) else {
                continue
            }

            var normalizedNode = node
            normalizedNode.frame = normalize(frame, by: windowFrame)
            if var accessibility = normalizedNode.accessibility,
               let accessibilityFrame = accessibility.frame,
               shouldNormalize(accessibilityFrame, within: windowFrame, designRect: designRect) {
                accessibility.frame = normalize(accessibilityFrame, by: windowFrame)
                accessibility.activationPoint = accessibility.activationPoint.map {
                    LoupePoint(x: $0.x - windowFrame.x, y: $0.y - windowFrame.y)
                }
                normalizedNode.accessibility = accessibility
            }
            normalizedNodes[node.ref] = normalizedNode
        }

        return LoupeSnapshot(
            id: snapshot.id,
            capturedAt: snapshot.capturedAt,
            screen: snapshot.screen,
            rootRefs: snapshot.rootRefs,
            nodes: normalizedNodes
        )
    }

    private static func ancestorWindowFrame(
        for node: LoupeNode,
        in snapshot: LoupeSnapshot,
        windows: [(ref: String, frame: LoupeRect)]
    ) -> LoupeRect? {
        var currentParent = node.parentRef
        while let ref = currentParent, let parent = snapshot.nodes[ref] {
            if parent.kind == .window || parent.role == "window" {
                return parent.frame
            }
            currentParent = parent.parentRef
        }

        guard let frame = node.frame else {
            return nil
        }
        return windows
            .filter { frame.intersects($0.frame) || pointNear(frame.center, $0.frame) }
            .sorted { lhs, rhs in rectDelta(frame, lhs.frame) < rectDelta(frame, rhs.frame) }
            .first?
            .frame
    }

    private static func shouldNormalize(
        _ frame: LoupeRect,
        within windowFrame: LoupeRect,
        designRect: LoupeRect
    ) -> Bool {
        if rectDelta(windowFrame, designRect) <= 2 {
            return false
        }
        let tolerance = 2.0
        guard frame.x >= windowFrame.x - tolerance,
              frame.y >= windowFrame.y - tolerance,
              frame.maxX <= windowFrame.maxX + tolerance,
              frame.maxY <= windowFrame.maxY + tolerance else {
            return false
        }
        return abs(windowFrame.x) > tolerance || abs(windowFrame.y) > tolerance
    }

    private static func normalize(_ frame: LoupeRect, by windowFrame: LoupeRect) -> LoupeRect {
        LoupeRect(
            x: frame.x - windowFrame.x,
            y: frame.y - windowFrame.y,
            width: frame.width,
            height: frame.height
        )
    }

    private static func pointNear(_ point: LoupePoint, _ rect: LoupeRect) -> Bool {
        point.x >= rect.x - 2
            && point.y >= rect.y - 2
            && point.x <= rect.maxX + 2
            && point.y <= rect.maxY + 2
    }

    private static func isFullScreenWrapperNoise(
        _ node: LoupeNode,
        design: LoupeDesignDocument,
        snapshot: LoupeSnapshot,
        options: LoupeDesignComparisonOptions
    ) -> Bool {
        guard !node.isInteractive else { return false }
        guard trimmedNonEmpty(displayText(node)) == nil else { return false }
        guard !node.children.isEmpty else { return false }
        guard let frame = node.frame else { return false }

        let tolerance = max(options.frameTolerance, 2)
        let designRect = LoupeRect(x: 0, y: 0, width: design.frame.width, height: design.frame.height)
        let screenRect = LoupeRect(x: 0, y: 0, width: snapshot.screen.size.width, height: snapshot.screen.size.height)
        return rectDelta(frame, designRect) <= tolerance || rectDelta(frame, screenRect) <= tolerance
    }

    private static func isStatusChromeIndicatorNoise(_ node: LoupeNode) -> Bool {
        guard !node.isInteractive else { return false }
        guard node.role == nil || node.role == "image" else { return false }
        guard node.children.isEmpty else { return false }
        guard trimmedNonEmpty(displayText(node)) == nil else { return false }
        guard trimmedNonEmpty(node.label) == nil,
              trimmedNonEmpty(node.value) == nil,
              trimmedNonEmpty(node.placeholder) == nil,
              trimmedNonEmpty(node.accessibility?.label) == nil,
              trimmedNonEmpty(node.accessibility?.value) == nil,
              trimmedNonEmpty(node.accessibility?.hint) == nil else {
            return false
        }
        guard let testID = node.testID?.lowercased(), testID.contains("status") else {
            return false
        }
        return ["battery", "cellular", "wifi", "signal"].contains { testID.contains($0) }
    }

    private static func matchNode(
        _ designNode: LoupeDesignNode,
        in nodes: [LoupeNode],
        consumedRefs: Set<String>,
        options: LoupeDesignComparisonOptions
    ) -> (node: LoupeNode, strategy: String)? {
        let available = nodes.filter { !consumedRefs.contains($0.ref) }

        let ids = designNode.matchIdentifiers
        if !ids.isEmpty,
           let node = available.first(where: { node in
               ids.contains { id in
                   node.testID == id || node.accessibility?.identifier == id
               }
           }) {
            return (node, "testID")
        }

        if let role = designNode.role,
           let text = designNode.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           let node = nearestRoleTextNode(role: role, text: text, to: designNode.frame, in: available) {
            return (node, "roleText")
        }

        if let role = designNode.role,
           let nearest = nearestNode(to: designNode.frame, in: available.filter({ $0.role == role }), options: options) {
            return (nearest, "roleGeometry")
        }

        let nonApplicationNodes = available.filter { $0.kind != .application }
        if let nearest = nearestNode(to: designNode.frame, in: nonApplicationNodes, options: options) {
            return (nearest, "geometry")
        }

        if let nearest = nearestNode(to: designNode.frame, in: available, options: options) {
            return (nearest, "geometry")
        }

        return nil
    }

    private static func nearestRoleTextNode(
        role: String,
        text: String,
        to frame: LoupeRect,
        in nodes: [LoupeNode]
    ) -> LoupeNode? {
        let candidates = nodes.filter { rolesMatch(expected: role, appNode: $0) && displayText($0) == text }
        return candidates
            .compactMap { node -> (node: LoupeNode, distance: Double)? in
                guard let nodeFrame = node.frame else {
                    return nil
                }
                return (node, centerDistance(frame, nodeFrame))
            }
            .sorted { $0.distance < $1.distance }
            .first?
            .node ?? candidates.first
    }

    private static func nearestNode(
        to frame: LoupeRect,
        in nodes: [LoupeNode],
        options: LoupeDesignComparisonOptions
    ) -> LoupeNode? {
        nodes
            .compactMap { node -> (node: LoupeNode, distance: Double, rank: Int)? in
                guard let nodeFrame = node.frame else { return nil }
                let distance = centerDistance(frame, nodeFrame)
                guard distance <= options.maxMatchDistance else { return nil }
                return (node, distance, geometryTieBreakRank(node))
            }
            .sorted {
                if abs($0.distance - $1.distance) > 0.001 {
                    return $0.distance < $1.distance
                }
                return $0.rank < $1.rank
            }
            .first?
            .node
    }

    private static func geometryTieBreakRank(_ node: LoupeNode) -> Int {
        var rank = 0
        if node.kind == .application {
            rank += 20
        }
        if node.kind == .window || normalizedRole(node.role) == "window" {
            rank -= 6
        }
        if node.style?.backgroundColor != nil {
            rank -= 4
        }
        if node.style?.cornerRadius != nil {
            rank -= 2
        }
        return rank
    }

    private static func propertyIssues(
        designNode: LoupeDesignNode,
        appNode: LoupeNode,
        snapshot: LoupeSnapshot,
        options: LoupeDesignComparisonOptions
    ) -> [LoupeDesignComparisonIssue] {
        var issues: [LoupeDesignComparisonIssue] = []
        let visualNode = compoundVisualNode(for: designNode, appNode: appNode, snapshot: snapshot, options: options)
        let frameNode = visualNode ?? appNode
        let frameTolerance = visualNode == nil ? options.frameTolerance : max(options.frameTolerance, 8)
        let styleNode = visualNode ?? appNode

        appendRoleIssue(
            expected: designNode.role,
            designNode: designNode,
            appNode: appNode,
            to: &issues
        )
        appendStringIssue(
            .textDelta,
            property: "text",
            expected: trimmedNonEmpty(designNode.text),
            actual: trimmedNonEmpty(displayText(appNode)),
            designNode: designNode,
            appNode: appNode,
            to: &issues
        )

        if let appFrame = frameNode.frame {
            let delta = rectDelta(designNode.frame, appFrame)
            if delta > frameTolerance {
                issues.append(
                    issue(
                        .frameDelta,
                        designNode: designNode,
                        appNode: appNode,
                        property: visualNode == nil ? "frame" : "visualFrame",
                        expected: rectString(designNode.frame),
                        actual: rectString(appFrame),
                        measuredDelta: delta,
                        message: visualNode == nil
                            ? "\(displayName(designNode)) frame differs by \(delta)pt"
                            : "\(displayName(designNode)) visual frame differs by \(delta)pt"
                    )
                )
            }
        }

        guard let style = designNode.style else {
            return issues
        }
        let shouldCompareObservableContainerStyle = !isProbeBackedStyleUnavailable(styleNode)
        let shouldCompareObservableTextStyle = !isTextStyleUnobservable(
            designNode: designNode,
            appNode: appNode
        )

        if shouldCompareObservableContainerStyle {
            appendColorIssue(
                kind: .backgroundColorDelta,
                property: "backgroundColor",
                expected: style.backgroundColor,
                actual: styleNode.style?.backgroundColor,
                designNode: designNode,
                appNode: appNode,
                options: options,
                to: &issues
            )
            appendNumericIssue(
                .cornerRadiusDelta,
                property: "cornerRadius",
                expected: style.cornerRadius,
                actual: styleNode.style?.cornerRadius,
                tolerance: options.cornerRadiusTolerance,
                designNode: designNode,
                appNode: appNode,
                to: &issues
            )
        }
        if shouldCompareObservableTextStyle {
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
        }

        return issues
    }

    private static func isTextStyleUnobservable(
        designNode: LoupeDesignNode,
        appNode: LoupeNode
    ) -> Bool {
        guard normalizedRole(designNode.role) == "statictext",
              trimmedNonEmpty(designNode.text) != nil else {
            return false
        }
        guard trimmedNonEmpty(displayText(appNode)) == trimmedNonEmpty(designNode.text) else {
            return false
        }
        guard appNode.style?.textColor == nil,
              appNode.style?.fontName == nil,
              appNode.style?.fontSize == nil else {
            return false
        }
        if appNode.custom["loupe.probe"] == .bool(true) {
            return true
        }
        guard trimmedNonEmpty(appNode.text) == nil,
              trimmedNonEmpty(appNode.renderedText) == nil else {
            return false
        }
        return trimmedNonEmpty(appNode.label) != nil
            || trimmedNonEmpty(appNode.value) != nil
            || trimmedNonEmpty(appNode.semanticText) != nil
            || trimmedNonEmpty(appNode.accessibility?.label) != nil
            || trimmedNonEmpty(appNode.accessibility?.value) != nil
    }

    private static func isProbeBackedStyleUnavailable(_ node: LoupeNode) -> Bool {
        guard node.custom["loupe.probe"] == .bool(true) else {
            return false
        }
        return node.style?.backgroundColor == nil
            && node.style?.cornerRadius == nil
            && node.style?.textColor == nil
            && node.style?.fontName == nil
            && node.style?.fontSize == nil
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

    private static func appendRoleIssue(
        expected: String?,
        designNode: LoupeDesignNode,
        appNode: LoupeNode,
        to issues: inout [LoupeDesignComparisonIssue]
    ) {
        guard let expected, !expected.isEmpty else {
            return
        }
        if rolesMatch(expected: expected, appNode: appNode) {
            return
        }
        issues.append(
            issue(
                .roleDelta,
                designNode: designNode,
                appNode: appNode,
                property: "role",
                expected: expected,
                actual: appNode.role,
                message: "\(displayName(designNode)) role differs"
            )
        )
    }

    private static func rolesMatch(expected: String, appNode: LoupeNode) -> Bool {
        let normalizedExpected = normalizedRole(expected)
        if normalizedExpected == normalizedRole(appNode.role) {
            return true
        }
        if normalizedExpected == "view", appNode.role == nil, appNode.kind == .view {
            return true
        }
        if normalizedExpected == "view",
           normalizedRole(appNode.role) == "window" || appNode.kind == .window {
            return true
        }
        if normalizedExpected == "statictext",
           !appNode.isInteractive,
           trimmedNonEmpty(displayText(appNode)) != nil {
            return true
        }
        if normalizedExpected == "textfield",
           appNode.uiKit?.textField != nil,
           !appNode.isInteractive {
            return true
        }
        return false
    }

    private static func normalizedRole(_ role: String?) -> String? {
        guard let role else {
            return nil
        }
        let normalized = role
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        return normalized.isEmpty ? nil : normalized
    }

    private static func compoundVisualNode(
        for designNode: LoupeDesignNode,
        appNode: LoupeNode,
        snapshot: LoupeSnapshot,
        options: LoupeDesignComparisonOptions
    ) -> LoupeNode? {
        guard let style = designNode.style else {
            return nil
        }
        let expectedBackground = style.backgroundColor.flatMap(color(fromHex:))
        let expectedCornerRadius = style.cornerRadius
        guard expectedBackground != nil || expectedCornerRadius != nil else {
            return nil
        }

        if isSwitchLike(appNode),
           let descendant = bestCompoundVisualNode(
            in: descendants(of: appNode, in: snapshot, maxDepth: 5),
            designNode: designNode,
            expectedBackground: expectedBackground,
            expectedCornerRadius: expectedCornerRadius,
            options: options
           ) {
            return descendant
        }

        if isTextBackedVisualContainerCandidate(designNode: designNode, appNode: appNode) {
            return bestCompoundVisualNode(
                in: ancestors(of: appNode, in: snapshot, maxDepth: 4),
                designNode: designNode,
                expectedBackground: expectedBackground,
                expectedCornerRadius: expectedCornerRadius,
                options: options
            )
        }

        return nil
    }

    private static func bestCompoundVisualNode(
        in candidates: [LoupeNode],
        designNode: LoupeDesignNode,
        expectedBackground: LoupeColor?,
        expectedCornerRadius: Double?,
        options: LoupeDesignComparisonOptions
    ) -> LoupeNode? {
        let maxDistance = max(options.maxMatchDistance, 32)
        return candidates
            .compactMap { candidate -> (node: LoupeNode, score: Double)? in
                guard candidate.isVisible, let frame = candidate.frame else {
                    return nil
                }
                guard candidate.kind != .application else {
                    return nil
                }
                let distance = centerDistance(designNode.frame, frame)
                guard distance <= maxDistance else {
                    return nil
                }

                var score = distance
                var matchedStyle = false
                if let expectedBackground {
                    guard let actual = candidate.style?.backgroundColor else {
                        return nil
                    }
                    let delta = colorDelta(expectedBackground, actual)
                    guard delta <= max(options.colorTolerance, 0.06) else {
                        return nil
                    }
                    score += delta * 100
                    matchedStyle = true
                }
                if let expectedCornerRadius {
                    guard let actual = candidate.style?.cornerRadius else {
                        return nil
                    }
                    let delta = abs(expectedCornerRadius - actual)
                    guard delta <= max(options.cornerRadiusTolerance, 2) else {
                        return nil
                    }
                    score += delta
                    matchedStyle = true
                }

                return matchedStyle ? (candidate, score) : nil
            }
            .sorted { $0.score < $1.score }
            .first?
            .node
    }

    private static func isTextBackedVisualContainerCandidate(
        designNode: LoupeDesignNode,
        appNode: LoupeNode
    ) -> Bool {
        guard let expectedText = trimmedNonEmpty(designNode.text),
              trimmedNonEmpty(displayText(appNode)) == expectedText else {
            return false
        }
        guard !appNode.isInteractive else {
            return false
        }
        guard appNode.role == "staticText" || appNode.uiKit?.textField != nil else {
            return false
        }
        return true
    }

    private static func isSwitchLike(_ node: LoupeNode) -> Bool {
        node.role == "switch"
            || node.uiKit?.switchControl != nil
            || node.typeName.localizedCaseInsensitiveContains("Switch")
    }

    private static func descendants(of node: LoupeNode, in snapshot: LoupeSnapshot, maxDepth: Int) -> [LoupeNode] {
        guard maxDepth > 0 else {
            return []
        }
        var result: [LoupeNode] = []
        var queue = node.children.map { (ref: $0, depth: 1) }
        while let next = queue.first {
            queue.removeFirst()
            guard let child = snapshot.nodes[next.ref] else {
                continue
            }
            result.append(child)
            if next.depth < maxDepth {
                queue.append(contentsOf: child.children.map { (ref: $0, depth: next.depth + 1) })
            }
        }
        return result
    }

    private static func ancestors(of node: LoupeNode, in snapshot: LoupeSnapshot, maxDepth: Int) -> [LoupeNode] {
        guard maxDepth > 0 else {
            return []
        }
        var result: [LoupeNode] = []
        var current = node
        var depth = 0
        while depth < maxDepth, let parentRef = current.parentRef, let parent = snapshot.nodes[parentRef] {
            result.append(parent)
            current = parent
            depth += 1
        }
        return result
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
        if kind == .fontNameDelta, fontNamesEquivalent(expected, actual) {
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

    private static func fontNamesEquivalent(_ expected: String, _ actual: String?) -> Bool {
        guard let actual else {
            return false
        }
        let expectedFont = normalizedFontName(expected)
        let actualFont = normalizedFontName(actual)
        guard expectedFont.family == actualFont.family else {
            return false
        }
        return fontWeightsEquivalent(expected: expectedFont.weight, actual: actualFont.weight)
    }

    private struct NormalizedFontName: Equatable {
        var family: String
        var weight: String?
    }

    private static func fontWeightsEquivalent(expected: String?, actual: String?) -> Bool {
        guard let expected else {
            return true
        }
        guard let actual else {
            return false
        }
        if expected == actual {
            return true
        }
        let strongWeights: Set<String> = ["bold", "semibold"]
        return strongWeights.contains(expected) && strongWeights.contains(actual)
    }

    private static func normalizedFontName(_ fontName: String) -> NormalizedFontName {
        let cleaned = fontName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")

        switch cleaned {
        case ".applesystemuifont", "applesystemuifont", ".sfuiregular", "sfuiregular", ".sfuiproregular", "sfuiproregular", "interregular":
            return NormalizedFontName(family: "native-sans", weight: "regular")
        case ".applesystemuifontbold", "applesystemuifontbold", ".sfuibold", "sfuibold", ".sfuiprobold", "sfuiprobold", "interbold":
            return NormalizedFontName(family: "native-sans", weight: "bold")
        case ".applesystemuifontdemi", "applesystemuifontdemi", ".applesystemuifontsemibold", "applesystemuifontsemibold", ".sfuisemibold", "sfuisemibold", ".sfuiprosemibold", "sfuiprosemibold", "intersemibold":
            return NormalizedFontName(family: "native-sans", weight: "semibold")
        case ".applesystemuifontmedium", "applesystemuifontmedium", ".sfuimedium", "sfuimedium", ".sfuipromedium", "sfuipromedium", "intermedium":
            return NormalizedFontName(family: "native-sans", weight: "medium")
        case ".applesystemuifontlight", "applesystemuifontlight", ".sfuilight", "sfuilight", ".sfuiprolight", "sfuiprolight", "interlight":
            return NormalizedFontName(family: "native-sans", weight: "light")
        case ".applesystemuifontthin", "applesystemuifontthin", ".sfuithin", "sfuithin", ".sfuiprothin", "sfuiprothin", "interthin":
            return NormalizedFontName(family: "native-sans", weight: "thin")
        case ".applesystemuifontheavy", "applesystemuifontheavy", ".sfuiheavy", "sfuiheavy", ".sfuiproheavy", "sfuiproheavy", "interheavy":
            return NormalizedFontName(family: "native-sans", weight: "heavy")
        case "inter":
            return NormalizedFontName(family: "native-sans", weight: nil)
        default:
            return NormalizedFontName(family: cleaned, weight: nil)
        }
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

    private static func trimmedNonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
        designColor(fromHex: rawValue)
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
