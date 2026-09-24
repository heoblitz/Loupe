import Foundation
import LoupeCLIModel
import LoupeCore

extension LoupeCLI {
    static func performAccessibilityAction(_ arguments: [String]) async throws {
        var options = try AccessibilityActionOptions(arguments: arguments)
        options.host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid
        )
        let runtimeState = try await fetchRuntimeState(host: options.host, timeout: options.timeout)
        if let udid = options.udid {
            try validateRuntimeIdentity(state: runtimeState, expectedUDID: udid, host: options.host)
        }

        var cache: ActionTargetAliasCache?
        let selector: LoupeSelector
        let targetIdentity: LoupeAccessibilityTargetIdentity?
        if let alias = options.targetAlias {
            let saved = try ActionTargetAliasCacheStore(url: ActionTargetAliasCacheStore.defaultURL(host: options.host)).load()
            try saved.validate(host: options.host, runtimeIdentity: runtimeState.identity)
            let entry = try saved.target(at: alias)
            guard entry.actions.contains(options.action) else {
                throw CLIError("Action target '#\(alias)' does not expose '\(options.action.commandName)'. Rerun `loupe act targets`")
            }
            cache = saved
            selector = .ref(entry.sourceRef)
            targetIdentity = LoupeAccessibilityTargetIdentity(
                ref: entry.ref,
                sourceRef: entry.sourceRef,
                testID: entry.testID,
                role: entry.role,
                label: entry.text,
                frame: entry.frame
            )
        } else if let explicitSelector = options.selector {
            selector = explicitSelector
            targetIdentity = nil
        } else {
            throw CLIError("perform requires a target")
        }

        let request = LoupeActivationRequest(
            selector: try activationSelector(from: selector),
            action: options.action,
            accessibilityTarget: targetIdentity
        )
        let response = try await postActivation(request, host: options.host, timeout: options.timeout)
        if let cache {
            try ActionTargetAliasCacheStore(url: ActionTargetAliasCacheStore.defaultURL(host: options.host)).consume(cacheID: cache.cacheID)
        }
        _ = try await fetchRuntimeState(host: options.host, timeout: options.timeout)
        print(try accessibilityActionSummary(response))
    }

    static func targetedInput(_ arguments: [String]) async throws {
        let options = try TargetedInputOptions(arguments: arguments)
        var tapOptions = try ActionOptions(
            command: "tap",
            arguments: options.targetArguments + options.commonArguments
        )
        tapOptions.host = try await resolvedRuntimeHost(
            requestedHost: tapOptions.host,
            hostWasExplicit: tapOptions.hostWasExplicit,
            udid: tapOptions.udid
        )
        let focusSelector: LoupeSelector
        if let alias = tapOptions.targetAlias {
            let entry = try ActionTargetAliasCacheStore(url: ActionTargetAliasCacheStore.defaultURL(host: tapOptions.host)).load().target(at: alias)
            focusSelector = entry.testID.map(LoupeSelector.testID) ?? .ref(entry.sourceRef)
        } else if let selector = tapOptions.selector {
            focusSelector = selector
        } else {
            throw CLIError("input requires a target")
        }

        try await action(
            command: "tap",
            arguments: options.targetArguments + options.commonArguments
        )
        if await waitForInputFocus(focusSelector, host: tapOptions.host, timeout: 1) == false {
            try await action(
                command: "tap",
                arguments: inputRetryTargetArguments(focusSelector) + options.commonArguments
            )
            guard await waitForInputFocus(
                focusSelector,
                host: tapOptions.host,
                timeout: min(tapOptions.timeout, 3)
            ) else {
                throw CLIError("input target did not become first responder after tap")
            }
        }
        try await action(
            command: "type",
            arguments: [options.text] + options.commonArguments
        )
        try await Task.sleep(nanoseconds: 250_000_000)
    }

    private static func waitForInputFocus(
        _ selector: LoupeSelector,
        host: URL,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                return false
            }
            if case let .testID(testID) = selector {
                do {
                    if let focused = try await fetchInputFocus(testID: testID, host: host, timeout: remaining) {
                        if focused { return true }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                } catch {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue
                }
            }
            let snapshot: LoupeSnapshot
            do {
                snapshot = try await fetchSnapshot(host: host, timeout: remaining)
            } catch {
                guard Date() < deadline else {
                    return false
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            let matches = LoupeSnapshotQuery.find(
                selector,
                in: LoupeSnapshotContext(snapshot: snapshot),
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: false, maxResults: 8)
            )
            if matches.contains(where: { snapshot.nodes[$0.ref]?.platform?.isFirstResponder == true }) {
                return true
            }
            guard Date() < deadline else {
                return false
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private struct InputFocusResponse: Decodable {
        var focused: Bool
    }

    /// Returns nil when an older runtime has no focused-input endpoint.
    private static func fetchInputFocus(testID: String, host: URL, timeout: TimeInterval) async throws -> Bool? {
        var components = URLComponents(url: host.appendingPathComponent("input/focus"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "testID", value: testID)]
        let (data, response) = try await httpData(
            from: components.url!, timeout: min(1, timeout), label: "input focus fetch"
        )
        guard let http = response as? HTTPURLResponse else {
            throw CLIError("input focus fetch expected an HTTP response")
        }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw CLIError("input focus fetch failed with HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(InputFocusResponse.self, from: data).focused
    }

    private static func inputRetryTargetArguments(_ selector: LoupeSelector) throws -> [String] {
        switch selector {
        case let .testID(value):
            return ["--test-id", value]
        case let .ref(value):
            return ["--ref", value]
        default:
            throw CLIError("input retry requires a stable testID or ref")
        }
    }

    private static func accessibilityActionSummary(_ response: LoupeActivationResponse) throws -> String {
        struct Summary: Encodable {
            var action: String
            var matched: Matched

            struct Matched: Encodable {
                var ref: String
                var text: String?
                var role: String?
            }
        }

        let target = response.accessibilityTarget
        let summary = Summary(
            action: response.action?.commandName ?? "activate",
            matched: Summary.Matched(
                ref: target?.ref ?? response.target.ref,
                text: target?.label ?? response.target.text,
                role: target?.role ?? response.target.role
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(summary), as: UTF8.self)
    }
}
