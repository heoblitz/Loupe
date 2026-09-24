import Foundation
import LoupeCLIModel
import LoupeCore

struct ActTargetsOptions {
    var host: URL?
    var udid: String?
    var bundleID: String?
    var timeout: TimeInterval
    var search: String?
    var limit: Int
    var includeAll: Bool

    init(_ arguments: [String]) throws {
        host = nil
        var udid: String?
        var timeout: TimeInterval = 5
        var search: String?
        var limit = 30
        var includeAll = false
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
            case "--udid", "--device":
                udid = try Self.value(after: argument, in: arguments, index: &index)
            case "--bundle-id":
                bundleID = try Self.value(after: argument, in: arguments, index: &index)
            case "--timeout":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let value = TimeInterval(raw), value > 0 else {
                    throw CLIError("--timeout must be greater than 0")
                }
                timeout = value
            case "--search":
                search = try Self.value(after: argument, in: arguments, index: &index)
            case "--limit":
                let raw = try Self.value(after: argument, in: arguments, index: &index)
                guard let value = Int(raw), (1...ActionTargetAliasPlanner.maximumTargetCount).contains(value) else {
                    throw CLIError("--limit must be between 1 and \(ActionTargetAliasPlanner.maximumTargetCount)")
                }
                limit = value
            case "--all":
                includeAll = true
            default:
                throw CLIError("Unknown targets option: \(argument)")
            }
            index += 1
        }

        self.udid = udid
        self.timeout = timeout
        self.search = search
        self.limit = limit
        self.includeAll = includeAll
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
            udid: options.udid,
            bundleID: options.bundleID, timeout: options.timeout
        )
        let runtimeState = try await fetchRuntimeState(host: host, timeout: options.timeout)
        try validateBundleIdentity(state: runtimeState, expectedBundleID: options.bundleID)
        if let udid = options.udid {
            try validateRuntimeIdentity(state: runtimeState, expectedUDID: udid, host: host)
        }
        guard let bundleIdentifier = runtimeState.identity.bundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !bundleIdentifier.isEmpty else {
            throw CLIError("Loupe runtime did not report a bundle identifier; cannot cache action targets")
        }

        let observation = try await fetchAccessibilityActionObservation(host: host, timeout: options.timeout)
        let cache = ActionTargetAliasPlanner.makeCache(
            snapshot: observation.snapshot,
            accessibilityTree: observation.tree,
            runtimeIdentity: runtimeState.identity,
            bundleIdentifier: bundleIdentifier,
            host: host,
            search: options.search,
            limit: options.limit,
            includeAll: options.includeAll
        )
        try ActionTargetAliasCacheStore(url: ActionTargetAliasCacheStore.defaultURL(host: host)).store(cache)
        print(ActionTargetAliasText.render(cache))
        if cache.totalTargetCount > cache.targets.count {
            FileHandle.standardError.write(Data(
                "Matched: \(cache.totalTargetCount)  Shown: \(cache.targets.count)  Omitted: \(cache.totalTargetCount - cache.targets.count)\n".utf8
            ))
        }
    }
}
