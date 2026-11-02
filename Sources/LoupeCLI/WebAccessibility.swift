import Foundation
import LoupeCLIModel
import LoupeCore
import LoupeHID

struct WebAccessibilityElement: Codable, Sendable {
    let id: String
    let role: Int
    let enabled: Bool
    let focused: Bool
    let frame: LoupeRect
    let point: LoupePoint
    let identifier: String?
    let label: String?
    let value: String?

    var roleName: String {
        switch role {
        case 2: "button"
        case 3: "checkbox"
        case 6: "heading"
        case 7: "image"
        case 8: "link"
        case 9: "radioButton"
        case 13: "slider"
        case 14: "staticText"
        case 15: "textField"
        case 17: "textArea"
        case 19: "popupButton"
        default: "element"
        }
    }
    var supportsTap: Bool { [2, 3, 8, 9, 15, 17, 19].contains(role) }

    private enum CodingKeys: String, CodingKey { case id, role, enabled, focused, frame, point, identifier, label, value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(roleName, forKey: .role)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(focused, forKey: .focused)
        try container.encode(frame, forKey: .frame)
        try container.encode(point, forKey: .point)
        try container.encodeIfPresent(identifier, forKey: .identifier)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
    }
}

struct WebAccessibilityResult: Encodable {
    let discovery = "visible-point-grid"
    let gridSpacing = 25
    let complete = false
    let elements: [WebAccessibilityElement]
}

func webSearchRegions(_ visible: [LoupeRect], near point: LoupePoint?) -> [LoupeRect] {
    guard let point else { return visible }
    guard visible.contains(where: { point.x >= $0.x && point.x < $0.maxX && point.y >= $0.y && point.y < $0.maxY }) else { return [] }
    return [LoupeRect(x: point.x - 12.5, y: point.y - 12.5, width: 25, height: 25)]
}

extension LoupeCLI {
    static func addWebTargets(snapshot: inout LoupeSnapshot, identity: LoupeRuntimeIdentity, timeout: TimeInterval, near point: LoupePoint? = nil) async throws {
        let elements = try await webElements(snapshot: snapshot, identity: identity, timeout: timeout, near: point)
        for element in elements where element.enabled && element.supportsTap {
            let ref = "web:\(element.id)"
            snapshot.nodes[ref] = LoupeNode(
                ref: ref, parentRef: nil, kind: .view, typeName: "WebAccessibilityElement",
                role: element.roleName, testID: element.identifier, label: element.label,
                value: element.value, text: element.label, frame: element.frame,
                isVisible: true, isEnabled: true, isInteractive: true, touchActions: [.tap],
                accessibility: LoupeAccessibility(identifier: element.identifier, label: element.label,
                    value: element.value, frame: element.frame, activationPoint: element.point, isElement: true),
                custom: ["observationBackend": .string("simulator-accessibility-point-grid")]
            )
        }
    }

    static func webAccessibility(_ arguments: [String]) async throws {
        let options = try RuntimeFetchOptions(arguments, usage: "loupe ui web [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]", defaultTimeout: 15)
        let host = try await resolvedRuntimeHost(requestedHost: options.host, hostWasExplicit: options.hostWasExplicit,
            udid: options.udid, bundleID: options.bundleID, timeout: options.timeout)
        let state = try await fetchRuntimeState(host: host, timeout: options.timeout)
        try validateBundleIdentity(state: state, expectedBundleID: options.bundleID)
        if let udid = options.udid { try validateRuntimeIdentity(state: state, expectedUDID: udid, host: host) }
        let snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        let elements = try await webElements(snapshot: snapshot, identity: state.identity, timeout: options.timeout)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(data: encoder.encode(WebAccessibilityResult(elements: elements)), outputURL: options.outputURL)
    }

    static func webElements(snapshot: LoupeSnapshot, identity: LoupeRuntimeIdentity, timeout: TimeInterval, near point: LoupePoint? = nil) async throws -> [WebAccessibilityElement] {
        guard let udid = identity.simulatorUDID, identity.platform == "iOS" else {
            throw CLIError("Web accessibility discovery requires an iOS Simulator runtime")
        }
        let screen = snapshot.screen.size
        let visibleRegions = snapshot.nodes.values.compactMap { node -> LoupeRect? in
            guard node.role == "webView", node.isVisible, let frame = node.frame else { return nil }
            let x = max(0, frame.x), y = max(0, frame.y)
            let width = min(screen.width, frame.maxX) - x, height = min(screen.height, frame.maxY) - y
            guard width > 0, height > 0 else { return nil }
            return LoupeRect(x: x, y: y, width: width, height: height)
        }
        // A saved web alias already has an activation point. First hit-test
        // only that point; the caller can fall back to the full visible grid
        // if a relayout moved the target. The 25-point region produces exactly
        // one sample in the native scanner, and still rechecks the hit's center.
        let regions = webSearchRegions(visibleRegions, near: point)
        var result: [WebAccessibilityElement] = []
        var seen = Set<String>()
        let deadline = Date().addingTimeInterval(timeout)
        for region in regions {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw CLIError("web accessibility discovery timed out") }
            let elements = try await scanWebRegion(udid: udid, pid: identity.processIdentifier, region: region, timeout: remaining)
            for element in elements where seen.insert(element.id).inserted { result.append(element) }
        }
        return result.sorted { ($0.frame.y, $0.frame.x, $0.id) < ($1.frame.y, $1.frame.x, $1.id) }
    }

    private static func scanWebRegion(udid: String, pid: Int32, region: LoupeRect, timeout: TimeInterval) async throws -> [WebAccessibilityElement] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var json: UnsafeMutablePointer<CChar>?
                var error: UnsafeMutablePointer<CChar>?
                let status = udid.withCString { name in
                    LoupeSimulatorWebElements(name, pid, region.x, region.y, region.width, region.height, timeout, &json, &error)
                }
                defer { if let json { LoupeHIDFreeCString(json) }; if let error { LoupeHIDFreeCString(error) } }
                guard status == 0, let json else {
                    continuation.resume(throwing: CLIError(error.map { String(cString: $0) } ?? "web accessibility discovery failed"))
                    return
                }
                do {
                    continuation.resume(returning: try JSONDecoder().decode([WebAccessibilityElement].self, from: Data(String(cString: json).utf8)))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
