import Foundation
import LoupeCore

package struct ActionTargetAliasEntry: Codable, Equatable {
    package var index: Int
    package var ref: String
    package var sourceRef: String
    package var role: String?
    package var text: String?
    package var testID: String?
    package var frame: LoupeRect?
    package var activationPoint: LoupePoint?
    package var point: LoupePoint
    package var isVisible: Bool
    package var isEnabled: Bool
    package var isInteractive: Bool
    package var actions: [LoupeAccessibilityAction] = []

    package var queryResult: LoupeAccessibilityQueryResult {
        LoupeAccessibilityQueryResult(
            node: LoupeAccessibilityNode(
                ref: ref,
                sourceRef: sourceRef,
                role: role,
                label: text,
                testID: testID,
                frame: frame,
                activationPoint: activationPoint,
                isVisible: isVisible,
                isEnabled: isEnabled,
                isInteractive: isInteractive,
                actions: actions
            )
        )
    }
}

package struct ActionTargetAliasCache: Codable, Equatable {
    package static let currentSchemaVersion = 2

    package var schemaVersion: Int
    package var cacheID: String
    package var capturedAt: Date
    package var launchID: String
    package var deviceIdentifier: String?
    package var bundleIdentifier: String
    package var host: String
    package var snapshotID: String
    package var screen: LoupeScreen
    package var totalTargetCount: Int
    package var targets: [ActionTargetAliasEntry]

    package init(
        schemaVersion: Int = currentSchemaVersion,
        cacheID: String = UUID().uuidString,
        capturedAt: Date = Date(),
        launchID: String,
        deviceIdentifier: String?,
        bundleIdentifier: String,
        host: String,
        snapshotID: String,
        screen: LoupeScreen,
        totalTargetCount: Int? = nil,
        targets: [ActionTargetAliasEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.cacheID = cacheID
        self.capturedAt = capturedAt
        self.launchID = launchID
        self.deviceIdentifier = deviceIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.host = ActionTargetAliasCache.normalizedHost(host)
        self.snapshotID = snapshotID
        self.screen = screen
        self.totalTargetCount = totalTargetCount ?? targets.count
        self.targets = targets
    }

    package func target(at index: Int) throws -> ActionTargetAliasEntry {
        guard let target = targets.first(where: { $0.index == index }) else {
            throw CLIError("Unknown action target '#\(index)'. Rerun `loupe act targets`")
        }
        guard target.isVisible,
              target.isEnabled,
              (target.isInteractive || !target.actions.isEmpty),
              target.point.x.isFinite,
              target.point.y.isFinite,
              target.point.x >= 0,
              target.point.y >= 0,
              target.point.x <= screen.size.width,
              target.point.y <= screen.size.height else {
            throw CLIError("Saved action target '#\(index)' is invalid. Rerun `loupe act targets`")
        }
        return target
    }

    package func validate(host: URL, runtimeIdentity: LoupeRuntimeIdentity) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CLIError("Saved action targets use an unsupported format. Rerun `loupe act targets`")
        }
        guard self.host == Self.normalizedHost(host.absoluteString) else {
            throw CLIError("Saved action targets belong to a different runtime host. Rerun `loupe act targets`")
        }
        guard launchID == runtimeIdentity.launchID else {
            throw CLIError("Saved action targets belong to an earlier app launch. Rerun `loupe act targets`")
        }
        let runtimeDevice = runtimeIdentity.deviceIdentifier ?? runtimeIdentity.simulatorUDID
        guard deviceIdentifier == runtimeDevice else {
            throw CLIError("Saved action targets belong to a different device. Rerun `loupe act targets`")
        }
        guard runtimeIdentity.bundleIdentifier == bundleIdentifier else {
            throw CLIError("Saved action targets belong to a different app. Rerun `loupe act targets`")
        }
    }

    private static func normalizedHost(_ raw: String) -> String {
        var value = raw
        while value.count > 1, value.last == "/" {
            value.removeLast()
        }
        return value
    }
}

package enum ActionTargetAliasPlanner {
    package static let maximumTargetCount = 100

    package static func makeCache(
        snapshot: LoupeSnapshot,
        accessibilityTree: LoupeAccessibilityTree,
        runtimeIdentity: LoupeRuntimeIdentity,
        bundleIdentifier: String,
        host: URL,
        cacheID: String = UUID().uuidString,
        capturedAt: Date = Date()
    ) -> ActionTargetAliasCache {
        var results = accessibilityTree.nodes.values
            .filter(isActionTarget)
            .map(LoupeAccessibilityQueryResult.init)
            .filter { actionPoint(for: $0, screen: accessibilityTree.screen) != nil }
            .sorted(by: visualOrder)

        results = preferPlatformBacked(results, snapshot: snapshot)
        results = exactDedupe(results)

        let totalTargetCount = results.count
        let targets = results.prefix(maximumTargetCount).enumerated().map { offset, result in
            ActionTargetAliasEntry(
                index: offset + 1,
                ref: result.ref,
                sourceRef: result.sourceRef,
                role: result.role,
                text: result.text,
                testID: result.testID,
                frame: result.frame,
                activationPoint: result.activationPoint,
                point: actionPoint(for: result, screen: accessibilityTree.screen)!,
                isVisible: result.isVisible,
                isEnabled: result.isEnabled,
                isInteractive: result.isInteractive,
                actions: accessibilityTree.nodes[result.ref]?.actions ?? []
            )
        }

        return ActionTargetAliasCache(
            cacheID: cacheID,
            capturedAt: capturedAt,
            launchID: runtimeIdentity.launchID,
            deviceIdentifier: runtimeIdentity.deviceIdentifier ?? runtimeIdentity.simulatorUDID,
            bundleIdentifier: bundleIdentifier,
            host: host.absoluteString,
            snapshotID: accessibilityTree.snapshotID,
            screen: accessibilityTree.screen,
            totalTargetCount: totalTargetCount,
            targets: targets
        )
    }

    private static func actionPoint(
        for result: LoupeAccessibilityQueryResult,
        screen: LoupeScreen
    ) -> LoupePoint? {
        let point: LoupePoint?
        if let activationPoint = result.activationPoint {
            point = activationPoint
        } else if let frame = result.frame, !frame.isEmpty {
            point = LoupePoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
        } else {
            point = nil
        }
        guard let point,
              point.x.isFinite, point.y.isFinite,
              point.x >= 0, point.y >= 0,
              point.x <= screen.size.width,
              point.y <= screen.size.height else {
            return nil
        }
        return point
    }

    private static func isActionTarget(_ node: LoupeAccessibilityNode) -> Bool {
        guard node.isVisible, node.isEnabled else { return false }
        if !(node.actions?.isEmpty ?? true) { return true }
        guard node.isInteractive else { return false }

        switch node.role {
        case "application", "scene", "window":
            return false
        case nil, "element":
            return nonEmpty(node.label) != nil || nonEmpty(node.testID) != nil
        default:
            return true
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func visualOrder(
        _ lhs: LoupeAccessibilityQueryResult,
        _ rhs: LoupeAccessibilityQueryResult
    ) -> Bool {
        let lhsPoint = lhs.frame.map { LoupePoint(x: $0.x, y: $0.y) } ?? lhs.activationPoint ?? LoupePoint(x: 0, y: 0)
        let rhsPoint = rhs.frame.map { LoupePoint(x: $0.x, y: $0.y) } ?? rhs.activationPoint ?? LoupePoint(x: 0, y: 0)
        if abs(lhsPoint.y - rhsPoint.y) > 1 {
            return lhsPoint.y < rhsPoint.y
        }
        if lhsPoint.x != rhsPoint.x {
            return lhsPoint.x < rhsPoint.x
        }
        return lhs.ref < rhs.ref
    }

    private static func preferPlatformBacked(
        _ results: [LoupeAccessibilityQueryResult],
        snapshot: LoupeSnapshot
    ) -> [LoupeAccessibilityQueryResult] {
        let grouped = Dictionary(grouping: results, by: semanticKey)
        let keysWithPlatformAlternative = Set(grouped.compactMap { key, group -> String? in
            let hasSynthetic = group.contains {
                LoupeSnapshotQuery.isSyntheticRegisteredProbeSource($0.sourceRef, in: snapshot)
            }
            let hasPlatform = group.contains {
                !LoupeSnapshotQuery.isSyntheticRegisteredProbeSource($0.sourceRef, in: snapshot)
            }
            return hasSynthetic && hasPlatform ? key : nil
        })
        return results.filter { result in
            let key = semanticKey(result)
            return !keysWithPlatformAlternative.contains(key)
                || !LoupeSnapshotQuery.isSyntheticRegisteredProbeSource(result.sourceRef, in: snapshot)
        }
    }

    private static func exactDedupe(
        _ results: [LoupeAccessibilityQueryResult]
    ) -> [LoupeAccessibilityQueryResult] {
        var keys = Set<String>()
        return results.filter { keys.insert(exactKey($0)).inserted }
    }

    private static func semanticKey(_ result: LoupeAccessibilityQueryResult) -> String {
        [result.role ?? "", result.testID ?? "", result.text ?? ""]
            .map(lengthPrefixed)
            .joined()
    }

    private static func exactKey(_ result: LoupeAccessibilityQueryResult) -> String {
        let frame = result.frame.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "nil"
        let point = result.activationPoint.map { "\($0.x),\($0.y)" } ?? "nil"
        return semanticKey(result) + lengthPrefixed(frame) + lengthPrefixed(point)
    }

    private static func lengthPrefixed(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }
}

package enum ActionTargetAliasText {
    package static func render(_ cache: ActionTargetAliasCache) -> String {
        var lines = ["App: \(cache.bundleIdentifier)", ""]
        lines.append(contentsOf: cache.targets.map { target in
            let role = nonEmpty(target.role) ?? "element"
            let text = escaped(nonEmpty(target.text) ?? "")
            var actions = ["tap"]
            if ["textField", "textView", "searchField"].contains(role) {
                actions.append("input")
            }
            actions.append(contentsOf: target.actions.map(\.commandName))
            var seen = Set<String>()
            let actionList = actions
                .filter { seen.insert($0).inserted }
                .map(displayAction)
                .joined(separator: ",")
            return "#\(target.index) \(role) \"\(text)\" [\(actionList)]"
        })
        return lines.joined(separator: "\n")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func displayAction(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "," || $0 == "[" || $0 == "]" }) else {
            return value
        }
        return "\"\(escaped(value))\""
    }
}

package struct ActionTargetAliasCacheStore {
    package var url: URL

    package init(url: URL = Self.defaultURL()) {
        self.url = url
    }

    package static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".loupe", isDirectory: true)
            .appendingPathComponent("act-targets", isDirectory: true)
            .appendingPathComponent("current.json")
    }

    package func store(_ cache: ActionTargetAliasCache) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(cache).write(to: url, options: .atomic)
    }

    package func load() throws -> ActionTargetAliasCache {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CLIError("No saved action targets. Run `loupe act targets` and use a quoted alias such as `loupe act tap '#1'`")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ActionTargetAliasCache.self, from: Data(contentsOf: url))
        } catch {
            throw CLIError("Saved action targets are unreadable. Rerun `loupe act targets`")
        }
    }

    package func consume(cacheID: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let current = try load()
        guard current.cacheID == cacheID else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}
