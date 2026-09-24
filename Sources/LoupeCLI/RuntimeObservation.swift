import Foundation
import LoupeCLIModel
import LoupeCore

extension LoupeCLI {
    static func liveAccessibility(_ arguments: [String]) async throws {
        let options = try LiveAccessibilityOptions(arguments)
        let runtime = options.runtime
        let host = try await resolvedRuntimeHost(
            requestedHost: runtime.host, hostWasExplicit: runtime.hostWasExplicit,
            udid: runtime.udid, bundleID: runtime.bundleID, timeout: runtime.timeout
        )
        if let udid = runtime.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: runtime.timeout)
        }
        let tree = try await fetchAccessibilityTree(host: host, timeout: runtime.timeout, includeHidden: options.includeHidden)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(data: encoder.encode(tree), outputURL: runtime.outputURL)
    }

    static func validateBundleIdentity(state: LoupeRuntimeState, expectedBundleID: String?) throws {
        if let expectedBundleID, state.identity.bundleIdentifier != expectedBundleID {
            throw CLIError("Runtime bundle mismatch: expected \(expectedBundleID), received \(state.identity.bundleIdentifier ?? "unknown")")
        }
    }

    static func fetchSnapshot(host: URL, timeout: TimeInterval = 5) async throws -> LoupeSnapshot {
        let url = host.appendingPathComponent("snapshot")
        let (data, response) = try await RuntimeHTTPClient.shared.data(from: url, timeout: timeout, label: "snapshot fetch")
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("snapshot fetch failed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeSnapshot.self, from: data)
    }

    static func fetchAccessibilityTree(
        host: URL,
        fallbackSnapshot: LoupeSnapshot? = nil,
        timeout: TimeInterval = 5,
        includeHidden: Bool = false
    ) async throws -> LoupeAccessibilityTree {
        guard var components = URLComponents(url: host.appendingPathComponent("accessibility"), resolvingAgainstBaseURL: false) else {
            throw CLIError("Invalid runtime host: \(host)")
        }
        if includeHidden { components.queryItems = [URLQueryItem(name: "includeHidden", value: "true")] }
        guard let url = components.url else { throw CLIError("Invalid accessibility URL") }
        let (data, response) = try await RuntimeHTTPClient.shared.data(from: url, timeout: timeout, label: "accessibility fetch")
        if let tree = try decodeAccessibilityResponse(data: data, response: response) {
            return tree
        }
        FileHandle.standardError.write(Data("warning: runtime lacks /accessibility (HTTP 404); using a view-derived accessibility tree\n".utf8))
        let snapshot: LoupeSnapshot
        if let fallbackSnapshot {
            snapshot = fallbackSnapshot
        } else {
            snapshot = try await fetchSnapshot(host: host, timeout: timeout)
        }
        return LoupeAccessibilityTree.build(from: snapshot, includeHidden: includeHidden)
    }

    /// Only a missing endpoint permits compatibility fallback. Transport, server,
    /// and decoding errors must not turn into a successful but misleading observation.
    static func decodeAccessibilityResponse(data: Data, response: URLResponse) throws -> LoupeAccessibilityTree? {
        guard let response = response as? HTTPURLResponse else {
            throw CLIError("accessibility fetch expected an HTTP response")
        }
        if response.statusCode == 404 { return nil }
        guard (200..<300).contains(response.statusCode) else {
            throw CLIError("accessibility fetch failed with HTTP \(response.statusCode)")
        }
        return try JSONDecoder().decode(LoupeAccessibilityTree.self, from: data)
    }

    /// Action discovery intentionally has no snapshot fallback: aliases must be backed
    /// by a currently executable native accessibility action, not a plausible view.
    static func fetchAccessibilityActionTree(
        host: URL,
        timeout: TimeInterval = 5
    ) async throws -> LoupeAccessibilityTree {
        let url = host.appendingPathComponent("accessibility/actions")
        let (data, response) = try await RuntimeHTTPClient.shared.data(from: url, timeout: timeout, label: "accessibility action fetch")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("accessibility action fetch expected an HTTP response")
        }
        if httpResponse.statusCode == 404 {
            throw CLIError("Runtime does not expose native accessibility actions. Relaunch with the current LoupeInjector.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("accessibility action fetch failed with HTTP \(httpResponse.statusCode)")
        }
        return try JSONDecoder().decode(LoupeAccessibilityTree.self, from: data)
    }

    static func fetchAccessibilityActionObservation(
        host: URL, timeout: TimeInterval = 5
    ) async throws -> LoupeAccessibilityActionObservation {
        let url = host.appendingPathComponent("accessibility/action-observation")
        let (data, response) = try await RuntimeHTTPClient.shared.data(from: url, timeout: timeout, label: "action observation fetch")
        guard let response = response as? HTTPURLResponse else {
            throw CLIError("action observation fetch expected an HTTP response")
        }
        if response.statusCode == 404 {
            // Older runtimes expose these separately. Only a missing endpoint permits fallback.
            let snapshot = try await fetchSnapshot(host: host, timeout: timeout)
            let tree = try await fetchAccessibilityActionTree(host: host, timeout: timeout)
            return LoupeAccessibilityActionObservation(snapshot: snapshot, tree: tree)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CLIError("action observation fetch failed with HTTP \(response.statusCode)")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let observation = try decoder.decode(LoupeAccessibilityActionObservation.self, from: data)
        guard observation.snapshot.id == observation.tree.snapshotID else {
            throw CLIError("Action observation contains mismatched snapshot identities")
        }
        return observation
    }

    static func fetchRuntimeState(host: URL, timeout: TimeInterval = 5) async throws -> LoupeRuntimeState {
        let statusURL = host.appendingPathComponent("status")
        let (statusData, statusResponse) = try await RuntimeHTTPClient.shared.data(from: statusURL, timeout: timeout, label: "runtime status fetch")
        guard let httpResponse = statusResponse as? HTTPURLResponse else {
            throw CLIError("runtime status fetch failed")
        }
        if (200..<300).contains(httpResponse.statusCode) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let status = try decoder.decode(LoupeRuntimeStatus.self, from: statusData)
            return LoupeRuntimeState(identity: status.identity)
        }
        guard httpResponse.statusCode == 404 else {
            throw CLIError("runtime status fetch failed")
        }
        let url = host.appendingPathComponent("runtime")
        let (data, response) = try await RuntimeHTTPClient.shared.data(from: url, timeout: timeout, label: "runtime fetch")
        guard let legacyResponse = response as? HTTPURLResponse, (200..<300).contains(legacyResponse.statusCode) else {
            throw CLIError("runtime fetch failed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeRuntimeState.self, from: data)
    }
}
