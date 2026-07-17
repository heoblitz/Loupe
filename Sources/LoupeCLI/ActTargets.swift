import Foundation
import LoupeCLIModel
import LoupeCore

struct ActTargetsOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        var udid: String?
        var timeout: TimeInterval = 5
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--host":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let url = URL(string: raw) else {
                    throw CLIError("Invalid --host URL: \(raw)")
                }
                host = url
                hostWasExplicit = true
            case "--udid", "--device":
                udid = try Self.value(after: argument, in: arguments, index: &index)
            case "--timeout":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let value = TimeInterval(raw), value > 0 else {
                    throw CLIError("--timeout must be greater than 0")
                }
                timeout = value
            default:
                throw CLIError("Unknown targets option: \(argument)")
            }
            index += 1
        }

        self.udid = udid
        self.timeout = timeout
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}

extension LoupeCLI {
    static func actionTargets(_ arguments: [String]) async throws {
        let options = try ActTargetsOptions(arguments)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid
        )
        let runtimeState = try await fetchRuntimeState(host: host, timeout: options.timeout)
        if let udid = options.udid {
            try validateRuntimeIdentity(state: runtimeState, expectedUDID: udid, host: host)
        }
        guard let bundleIdentifier = runtimeState.identity.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleIdentifier.isEmpty else {
            throw CLIError("Loupe runtime did not report a bundle identifier; cannot cache action targets")
        }

        let snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        let accessibilityTree = try await fetchAccessibilityTree(
            host: host,
            fallbackSnapshot: snapshot,
            timeout: options.timeout
        )
        let cache = ActionTargetAliasPlanner.makeCache(
            snapshot: snapshot,
            accessibilityTree: accessibilityTree,
            runtimeIdentity: runtimeState.identity,
            bundleIdentifier: bundleIdentifier,
            host: host
        )
        try ActionTargetAliasCacheStore().store(cache)
        print(ActionTargetAliasText.render(cache))
        if cache.totalTargetCount > cache.targets.count {
            FileHandle.standardError.write(Data(
                "TIP: showing the first \(cache.targets.count) action targets; use `loupe ui report` for full view analysis\n".utf8
            ))
        }
    }
}
