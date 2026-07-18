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
            let saved = try ActionTargetAliasCacheStore().load()
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
            try ActionTargetAliasCacheStore().consume(cacheID: cache.cacheID)
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
            let entry = try ActionTargetAliasCacheStore().load().target(at: alias)
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
        if try await waitForInputFocus(focusSelector, host: tapOptions.host, timeout: 1) == false {
            try await action(
                command: "tap",
                arguments: inputRetryTargetArguments(focusSelector) + options.commonArguments
            )
            guard try await waitForInputFocus(
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
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let snapshot = try await fetchSnapshot(host: host, timeout: timeout)
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
            try await Task.sleep(nanoseconds: 100_000_000)
        }
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
