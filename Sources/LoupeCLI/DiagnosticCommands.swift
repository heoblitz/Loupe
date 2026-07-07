import Foundation
import LoupeCLIModel
import LoupeCore

extension LoupeCLI {
    static let debugUsage = """
    Usage: loupe debug <subcommand>

    SUBCOMMANDS:
      logs                    Fetch app-authored runtime logs.
      network                 Fetch fixture and app-authored network evidence.
      refs                    Fetch app-authored object reference evidence.
      object-graph            Summarize app-authored owner -> target references.
      heap                    Alias for object-graph evidence summary.
      objects classes|describe
                              Inspect Objective-C runtime class metadata.
      leaks                   Fetch weak lifetime probes registered by the app.
      keychain list           List current app keychain item metadata.
      defaults get|set|unset  Read or change UserDefaults.
      flags get|set|unset     Alias for feature flags stored in UserDefaults.
      trace summary|diff|explore|cleanup
      scroll                  Dispatch a scroll gesture or runtime offset probe.
    """

    static func debug(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError(debugUsage)
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "logs":
            try await runtimeFetch(
                rest,
                path: "/logs",
                usage: """
                loupe debug logs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]

                Apps without a LoupeKit import can post NotificationCenter name "dev.loupe.log" with userInfo keys level, message, and metadata.
                """
            )
        case "network":
            try await runtimeFetch(
                rest,
                path: "/network",
                usage: "loupe debug network [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
        case "refs":
            try await runtimeFetch(
                rest,
                path: "/refs",
                usage: "loupe debug refs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
        case "heap", "object-graph":
            try await referenceGraph(rest, commandName: subcommand)
        case "objects":
            try await debugObjects(rest)
        case "leaks":
            try await debugLeaks(rest)
        case "keychain":
            guard rest.isEmpty || rest.first == "list" else {
                throw CLIError("Usage: loupe debug keychain [list] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]")
            }
            try await runtimeFetch(
                rest.first == "list" ? Array(rest.dropFirst()) : rest,
                path: "/state/keychain",
                usage: "loupe debug keychain [list] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
        case "defaults":
            try await stateDefaults(rest, path: "state/defaults", usagePrefix: "loupe debug defaults")
        case "flags":
            try await stateDefaults(rest, path: "state/flags", usagePrefix: "loupe debug flags")
        case "trace":
            try await debugTrace(rest)
        case "scroll":
            try await perf(["scroll"] + rest)
        default:
            throw CLIError("Unknown debug command: \(subcommand)")
        }
    }

    static func env(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError("Usage: loupe ui appearance [light|dark|system] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]")
        }
        switch subcommand {
        case "appearance":
            let rest = Array(arguments.dropFirst())
            let appearance: String?
            let optionArgs: [String]
            if let first = rest.first, !first.hasPrefix("-") {
                appearance = first
                optionArgs = Array(rest.dropFirst())
            } else {
                appearance = nil
                optionArgs = rest
            }
            let options = try DiagnosticRuntimeOptions(optionArgs, usage: "loupe ui appearance [light|dark|system] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]")
            guard let appearance else {
                let data = try await runtimeData(path: "/environment", options: options.runtimeFetchOptions)
                try write(data: data, outputURL: options.outputURL)
                return
            }
            let request = LoupeEnvironmentMutationRequest(appearance: appearance)
            let data = try await postRuntimeJSON(request, path: "environment", options: options)
            try write(data: data, outputURL: options.outputURL)
        default:
            throw CLIError("Unknown ui appearance command: \(subcommand)")
        }
    }

    static func perf(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError("Usage: loupe debug scroll <subcommand>")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "scroll":
            if RuntimeScrollProfileOptions.usesRuntimeMode(rest) {
                try await runtimeScrollProfile(rest)
                return
            }
            let output = outputValue(in: rest)
            let actionArguments = argumentsRemovingOutput(rest)
            let startedAt = Date()
            try await action(command: "swipe", arguments: actionArguments)
            let traceDirectory = traceDirectoryValue(in: rest)
            let traceProfile = try scrollProfile(traceDirectory: traceDirectory)
            let profile = LoupeScrollProfile(
                ref: traceProfile?.ref,
                testID: traceProfile?.testID,
                beforeOffset: traceProfile?.beforeOffset,
                afterOffset: traceProfile?.afterOffset,
                delta: traceProfile?.delta,
                actionElapsed: Date().timeIntervalSince(startedAt),
                traceDirectory: traceDirectory
            )
            let data = try diagnosticJSONEncoder().encode(profile)
            try write(data: data, outputURL: output.map { URL(fileURLWithPath: $0) })
        default:
            throw CLIError("Unknown perf command: \(subcommand)")
        }
    }

    static func hitTest(_ arguments: [String]) async throws {
        let options = try DiagnosticRuntimeOptions(arguments, usage: "loupe ui hit-test --point x,y [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]")
        guard let point = options.point else {
            throw CLIError("loupe ui hit-test requires --point x,y")
        }
        let data = try await runtimeData(path: "/hit-test?point=\(urlEncode(point))", options: options.runtimeFetchOptions)
        try write(data: data, outputURL: options.outputURL)
    }

    static func responderChain(_ arguments: [String]) async throws {
        let options = try DiagnosticRuntimeOptions(arguments, usage: "loupe ui responder-chain (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]")
        let selectorQuery = try options.selectorQuery()
        let data = try await runtimeData(path: "/responder-chain?\(selectorQuery)", options: options.runtimeFetchOptions)
        try write(data: data, outputURL: options.outputURL)
    }

    static func debugTrace(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError("Usage: loupe debug trace summary|diff|explore|cleanup <args>")
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "summary":
            try traceSummary(rest)
        case "diff":
            try diff(rest)
        case "explore":
            try await exploreRoutes(rest)
        case "cleanup":
            let cleanupArgs = rest.contains("--no-runtimes") ? rest : rest + ["--no-runtimes"]
            try await cleanup(cleanupArgs)
        default:
            throw CLIError("Unknown debug trace command: \(subcommand)")
        }
    }

    private static func stateDefaults(_ arguments: [String], path: String, usagePrefix: String) async throws {
        guard let action = arguments.first else {
            throw CLIError("Usage: \(usagePrefix) get|set|unset <key> [value] [--host <url>] [--output <path>]")
        }
        let rest = Array(arguments.dropFirst())
        switch action {
        case "get":
            guard let key = rest.first else {
                throw CLIError("Usage: \(usagePrefix) get <key> [--host <url>] [--output <path>]")
            }
            let options = try DiagnosticRuntimeOptions(Array(rest.dropFirst()), usage: "\(usagePrefix) get <key> [--host <url>] [--output <path>]")
            let data = try await runtimeData(path: "/\(path)?key=\(urlEncode(key))", options: options.runtimeFetchOptions)
            try write(data: data, outputURL: options.outputURL)
        case "set":
            guard let key = rest.first else {
                throw CLIError("Usage: \(usagePrefix) set <key> [value] [--bool true|false|--number n] [--host <url>] [--output <path>]")
            }
            let remaining = Array(rest.dropFirst())
            let positionalValue = remaining.first.map { !$0.hasPrefix("-") } == true ? remaining[0] : nil
            let valueArgs = positionalValue == nil ? remaining : Array(remaining.dropFirst())
            let options = try DiagnosticRuntimeOptions(valueArgs, usage: "\(usagePrefix) set <key> [value] [--bool true|false|--number n] [--host <url>] [--output <path>]")
            guard let value = options.value ?? positionalValue.map(LoupeMetadataValue.string) else {
                throw CLIError("Usage: \(usagePrefix) set <key> [value] [--bool true|false|--number n] [--host <url>] [--output <path>]")
            }
            let request = LoupeStateMutationRequest(key: key, value: value)
            let data = try await postRuntimeJSON(request, path: path, options: options)
            try write(data: data, outputURL: options.outputURL)
        case "unset", "remove":
            guard let key = rest.first else {
                throw CLIError("Usage: \(usagePrefix) unset <key> [--host <url>] [--output <path>]")
            }
            let options = try DiagnosticRuntimeOptions(Array(rest.dropFirst()), usage: "\(usagePrefix) unset <key> [--host <url>] [--output <path>]")
            let request = LoupeStateMutationRequest(key: key, value: nil)
            let data = try await postRuntimeJSON(request, path: path, options: options)
            try write(data: data, outputURL: options.outputURL)
        default:
            throw CLIError("Unknown \(usagePrefix) command: \(action)")
        }
    }

    struct ReferenceGraphOptions {
        var target: String?
        var runtimeOptions: DiagnosticRuntimeOptions

        init(_ arguments: [String], commandName: String) throws {
            var runtimeArguments: [String] = []
            var target: String?
            var index = 0

            while index < arguments.count {
                switch arguments[index] {
                case "--target":
                    target = try Self.value(after: "--target", in: arguments, index: &index)
                case "--host", "--udid", "--device", "--bundle-id", "--output", "--timeout":
                    let option = arguments[index]
                    runtimeArguments.append(option)
                    runtimeArguments.append(try Self.value(after: option, in: arguments, index: &index))
                case "--help", "-h":
                    runtimeArguments.append(arguments[index])
                default:
                    if !arguments[index].hasPrefix("-"), target == nil {
                        target = arguments[index]
                    } else {
                        runtimeArguments.append(arguments[index])
                    }
                }
                index += 1
            }

            self.target = target
            self.runtimeOptions = try DiagnosticRuntimeOptions(
                runtimeArguments,
                usage: "loupe debug \(commandName) [target|--target <name>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
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

    struct ObjectClassesOptions {
        var matching: String?
        var limit: Int?
        var runtimeOptions: DiagnosticRuntimeOptions

        init(_ arguments: [String]) throws {
            var runtimeArguments: [String] = []
            var index = 0
            while index < arguments.count {
                switch arguments[index] {
                case "--matching", "--match":
                    matching = try Self.value(after: arguments[index], in: arguments, index: &index)
                case "--limit":
                    let raw = try Self.value(after: "--limit", in: arguments, index: &index)
                    guard let value = Int(raw), value > 0 else {
                        throw CLIError("--limit expects a positive integer")
                    }
                    limit = value
                case "--host", "--udid", "--device", "--bundle-id", "--output", "--timeout":
                    let option = arguments[index]
                    runtimeArguments.append(option)
                    runtimeArguments.append(try Self.value(after: option, in: arguments, index: &index))
                case "--help", "-h":
                    runtimeArguments.append(arguments[index])
                default:
                    throw CLIError("Unknown debug objects classes option: \(arguments[index])")
                }
                index += 1
            }

            runtimeOptions = try DiagnosticRuntimeOptions(
                runtimeArguments,
                usage: "loupe debug objects classes [--matching <name>] [--limit <n>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
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

    struct ObjectDescriptionOptions {
        var className: String
        var runtimeOptions: DiagnosticRuntimeOptions

        init(_ arguments: [String]) throws {
            var runtimeArguments: [String] = []
            var className: String?
            var index = 0
            while index < arguments.count {
                switch arguments[index] {
                case "--class":
                    className = try Self.value(after: "--class", in: arguments, index: &index)
                case "--host", "--udid", "--device", "--bundle-id", "--output", "--timeout":
                    let option = arguments[index]
                    runtimeArguments.append(option)
                    runtimeArguments.append(try Self.value(after: option, in: arguments, index: &index))
                case "--help", "-h":
                    runtimeArguments.append(arguments[index])
                default:
                    if !arguments[index].hasPrefix("-"), className == nil {
                        className = arguments[index]
                    } else {
                        throw CLIError("Unknown debug objects describe option: \(arguments[index])")
                    }
                }
                index += 1
            }

            guard let className else {
                throw CLIError("Usage: loupe debug objects describe <class|--class <name>> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]")
            }
            self.className = className
            runtimeOptions = try DiagnosticRuntimeOptions(
                runtimeArguments,
                usage: "loupe debug objects describe <class|--class <name>> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
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

    struct LeakProbeOptions {
        var aliveOnly: Bool
        var runtimeOptions: DiagnosticRuntimeOptions

        init(_ arguments: [String]) throws {
            aliveOnly = false
            var runtimeArguments: [String] = []
            var index = 0
            while index < arguments.count {
                switch arguments[index] {
                case "--alive-only", "--alive":
                    aliveOnly = true
                case "--host", "--udid", "--device", "--bundle-id", "--output", "--timeout":
                    let option = arguments[index]
                    runtimeArguments.append(option)
                    runtimeArguments.append(try Self.value(after: option, in: arguments, index: &index))
                case "--help", "-h":
                    runtimeArguments.append(arguments[index])
                default:
                    throw CLIError("Unknown debug leaks option: \(arguments[index])")
                }
                index += 1
            }

            runtimeOptions = try DiagnosticRuntimeOptions(
                runtimeArguments,
                usage: "loupe debug leaks [--alive-only] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
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

    private static func referenceGraph(_ arguments: [String], commandName: String) async throws {
        let options = try ReferenceGraphOptions(arguments, commandName: commandName)
        let data = try await runtimeData(path: "/refs", options: options.runtimeOptions.runtimeFetchOptions)
        let refs = try diagnosticJSONDecoder().decode([LoupeReferenceEvidence].self, from: data)
        let graph = makeReferenceGraph(from: refs, target: options.target)
        let encoded = try diagnosticJSONEncoder().encode(graph)
        try write(data: encoded, outputURL: options.runtimeOptions.outputURL)
    }

    private static func debugObjects(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError("Usage: loupe debug objects classes|describe <args>")
        }

        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "classes", "list":
            let options = try ObjectClassesOptions(rest)
            var query: [String] = []
            if let matching = options.matching {
                query.append("matching=\(urlEncode(matching))")
            }
            if let limit = options.limit {
                query.append("limit=\(limit)")
            }
            let suffix = query.isEmpty ? "" : "?\(query.joined(separator: "&"))"
            let data = try await runtimeData(
                path: "/objects/classes\(suffix)",
                options: options.runtimeOptions.runtimeFetchOptions
            )
            try write(data: data, outputURL: options.runtimeOptions.outputURL)
        case "describe", "class":
            let options = try ObjectDescriptionOptions(rest)
            let data = try await runtimeData(
                path: "/objects/describe?class=\(urlEncode(options.className))",
                options: options.runtimeOptions.runtimeFetchOptions
            )
            try write(data: data, outputURL: options.runtimeOptions.outputURL)
        default:
            throw CLIError("Unknown debug objects command: \(subcommand)")
        }
    }

    private static func debugLeaks(_ arguments: [String]) async throws {
        let options = try LeakProbeOptions(arguments)
        let suffix = options.aliveOnly ? "?alive=true" : ""
        let data = try await runtimeData(path: "/leaks\(suffix)", options: options.runtimeOptions.runtimeFetchOptions)
        try write(data: data, outputURL: options.runtimeOptions.outputURL)
    }

    static func makeReferenceGraph(
        from refs: [LoupeReferenceEvidence],
        target: String?
    ) -> LoupeReferenceGraph {
        let relevantRefs: [LoupeReferenceEvidence]
        if let target {
            relevantRefs = refs.filter { $0.owner == target || $0.target == target }
        } else {
            relevantRefs = refs
        }

        var incomingCounts: [String: Int] = [:]
        var outgoingCounts: [String: Int] = [:]
        let edges = relevantRefs.map { evidence in
            outgoingCounts[evidence.owner, default: 0] += 1
            incomingCounts[evidence.target, default: 0] += 1
            return LoupeReferenceGraphEdge(
                evidenceID: evidence.id,
                owner: evidence.owner,
                target: evidence.target,
                kind: evidence.kind,
                label: evidence.label,
                metadata: evidence.metadata,
                timestamp: evidence.timestamp
            )
        }.sorted(by: referenceEdgeOrder)

        let names = Set(incomingCounts.keys).union(outgoingCounts.keys)
        let nodes = names
            .sorted()
            .map { name in
                LoupeReferenceGraphNode(
                    name: name,
                    incomingCount: incomingCounts[name, default: 0],
                    outgoingCount: outgoingCounts[name, default: 0]
                )
            }

        let owners: [LoupeReferenceGraphOwner]
        if let target {
            owners = refs
                .filter { $0.target == target }
                .sorted(by: referenceEvidenceOrder)
                .map { evidence in
                    LoupeReferenceGraphOwner(
                        evidenceID: evidence.id,
                        owner: evidence.owner,
                        kind: evidence.kind,
                        label: evidence.label,
                        metadata: evidence.metadata,
                        timestamp: evidence.timestamp
                    )
                }
        } else {
            owners = []
        }

        return LoupeReferenceGraph(target: target, nodes: nodes, edges: edges, owners: owners)
    }

    static func referenceEdgeOrder(_ lhs: LoupeReferenceGraphEdge, _ rhs: LoupeReferenceGraphEdge) -> Bool {
        if lhs.owner != rhs.owner {
            return lhs.owner < rhs.owner
        }
        if lhs.kind != rhs.kind {
            return (lhs.kind ?? "") < (rhs.kind ?? "")
        }
        if lhs.label != rhs.label {
            return (lhs.label ?? "") < (rhs.label ?? "")
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        if lhs.target != rhs.target {
            return lhs.target < rhs.target
        }
        return lhs.evidenceID < rhs.evidenceID
    }

    static func referenceEvidenceOrder(_ lhs: LoupeReferenceEvidence, _ rhs: LoupeReferenceEvidence) -> Bool {
        if lhs.owner != rhs.owner {
            return lhs.owner < rhs.owner
        }
        if lhs.kind != rhs.kind {
            return (lhs.kind ?? "") < (rhs.kind ?? "")
        }
        if lhs.label != rhs.label {
            return (lhs.label ?? "") < (rhs.label ?? "")
        }
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        if lhs.target != rhs.target {
            return lhs.target < rhs.target
        }
        return lhs.id < rhs.id
    }

    private static func postRuntimeJSON<T: Encodable>(_ body: T, path: String, options: DiagnosticRuntimeOptions) async throws -> Data {
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }
        var request = URLRequest(url: host.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try diagnosticJSONEncoder().encode(body)
        let (data, response) = try await httpData(for: request, timeout: options.timeout, label: "runtime post")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("runtime post expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime post failed with HTTP \(httpResponse.statusCode): \(String(decoding: data, as: UTF8.self))")
        }
        return data
    }

    private static func diagnosticJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func traceDirectoryValue(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--trace-dir"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func outputValue(in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--output"), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func argumentsRemovingOutput(_ arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--output" {
                index += 2
            } else {
                result.append(arguments[index])
                index += 1
            }
        }
        return result
    }

    private struct RuntimeScrollProfileOptions {
        var runtimeOptions: DiagnosticRuntimeOptions
        var delta: LoupePoint?
        var toOffset: LoupePoint?

        static func usesRuntimeMode(_ arguments: [String]) -> Bool {
            arguments.contains("--delta") || arguments.contains("--to-offset")
        }

        init(_ arguments: [String]) throws {
            var runtimeArguments: [String] = []
            var delta: LoupePoint?
            var toOffset: LoupePoint?
            var index = 0

            while index < arguments.count {
                switch arguments[index] {
                case "--delta":
                    let value = try Self.value(after: "--delta", in: arguments, index: &index)
                    delta = try LoupeCLI.diagnosticPoint(value, option: "--delta")
                case "--to-offset":
                    let value = try Self.value(after: "--to-offset", in: arguments, index: &index)
                    toOffset = try LoupeCLI.diagnosticPoint(value, option: "--to-offset")
                default:
                    runtimeArguments.append(arguments[index])
                }
                index += 1
            }

            if delta != nil && toOffset != nil {
                throw CLIError("loupe debug scroll accepts only one of --delta or --to-offset")
            }
            if delta == nil && toOffset == nil {
                throw CLIError("Usage: loupe debug scroll (--from x,y --to x,y --udid <sim> | (--test-id <id>|--ref <ref>|--text <text>|--role <role>) (--delta dx,dy|--to-offset x,y)) [--host <url>] [--output <path>]")
            }

            self.runtimeOptions = try DiagnosticRuntimeOptions(
                runtimeArguments,
                usage: "loupe debug scroll (--test-id <id>|--ref <ref>|--text <text>|--role <role>) (--delta dx,dy|--to-offset x,y) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
            self.delta = delta
            self.toOffset = toOffset
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

    private static func runtimeScrollProfile(_ arguments: [String]) async throws {
        let options = try RuntimeScrollProfileOptions(arguments)
        let beforeData = try await runtimeData(path: "/snapshot", options: options.runtimeOptions.runtimeFetchOptions)
        let beforeSnapshot = try diagnosticJSONDecoder().decode(LoupeSnapshot.self, from: beforeData)
        let selector = try diagnosticSelector(from: options.runtimeOptions)
        let matches = LoupeSnapshotQuery.find(
            selector,
            in: beforeSnapshot,
            options: LoupeQueryOptions(
                includeHidden: true,
                includeDisabled: true,
                maxResults: 2,
                visibilityMode: .raw
            )
        )
        guard matches.count == 1, let target = matches.first else {
            throw CLIError("loupe debug scroll expected exactly one scroll target, found \(matches.count)")
        }
        guard let beforeNode = beforeSnapshot.nodes[target.ref],
              let beforeOffset = beforeNode.platform?.scrollView?.contentOffset else {
            throw CLIError("loupe debug scroll target is not a captured scroll view: \(target.testID ?? target.ref)")
        }

        let requestedOffset = options.toOffset ?? LoupePoint(
            x: beforeOffset.x + (options.delta?.x ?? 0),
            y: beforeOffset.y + (options.delta?.y ?? 0)
        )
        let request = LoupeMutationRequest(
            selector: LoupeMutationSelector(kind: .ref, value: target.ref),
            property: "contentOffset",
            value: .point(requestedOffset),
            layout: true,
            animation: nil
        )

        let startedAt = Date()
        let responseData = try await postRuntimeJSON(request, path: "mutate", options: options.runtimeOptions)
        let response = try diagnosticJSONDecoder().decode(LoupeMutationResponse.self, from: responseData)
        let elapsed = Date().timeIntervalSince(startedAt)
        guard let afterOffset = response.after.platform?.scrollView?.contentOffset else {
            throw CLIError("loupe debug scroll mutation response did not include an after scroll offset")
        }

        let profile = LoupeScrollProfile(
            ref: target.ref,
            testID: target.testID,
            beforeOffset: beforeOffset,
            afterOffset: afterOffset,
            delta: LoupePoint(x: afterOffset.x - beforeOffset.x, y: afterOffset.y - beforeOffset.y),
            actionElapsed: elapsed,
            traceDirectory: nil
        )
        let data = try diagnosticJSONEncoder().encode(profile)
        try write(data: data, outputURL: options.runtimeOptions.outputURL)
    }

    private static func diagnosticSelector(from options: DiagnosticRuntimeOptions) throws -> LoupeSelector {
        if let testID = options.testID {
            return .testID(testID)
        }
        if let ref = options.ref {
            return .ref(ref)
        }
        if let text = options.text {
            return .text(text)
        }
        if let role = options.role {
            return .role(role)
        }
        throw CLIError("loupe debug scroll requires --test-id, --ref, --text, or --role in runtime offset mode")
    }

    private static func diagnosticPoint(_ value: String, option: String) throws -> LoupePoint {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              x.isFinite,
              y.isFinite else {
            throw CLIError("\(option) expects x,y")
        }
        return LoupePoint(x: x, y: y)
    }

    private struct ScrollTraceProfile {
        var ref: String
        var testID: String?
        var beforeOffset: LoupePoint
        var afterOffset: LoupePoint
        var delta: LoupePoint
    }

    private static func scrollProfile(traceDirectory: String?) throws -> ScrollTraceProfile? {
        guard let traceDirectory else {
            return nil
        }
        let directory = URL(fileURLWithPath: traceDirectory)
        let beforeURL = directory.appendingPathComponent("before-snapshot.json")
        let afterURL = directory.appendingPathComponent("after-snapshot.json")
        guard FileManager.default.fileExists(atPath: beforeURL.path),
              FileManager.default.fileExists(atPath: afterURL.path) else {
            return nil
        }
        let before = try decodeDiagnosticSnapshot(from: beforeURL)
        let after = try decodeDiagnosticSnapshot(from: afterURL)
        for (ref, beforeNode) in before.nodes {
            guard let beforeOffset = beforeNode.platform?.scrollView?.contentOffset,
                  let afterOffset = after.nodes[ref]?.platform?.scrollView?.contentOffset,
                  beforeOffset != afterOffset else {
                continue
            }
            return ScrollTraceProfile(
                ref: ref,
                testID: beforeNode.testID,
                beforeOffset: beforeOffset,
                afterOffset: afterOffset,
                delta: LoupePoint(x: afterOffset.x - beforeOffset.x, y: afterOffset.y - beforeOffset.y)
            )
        }
        return nil
    }

    private static func decodeDiagnosticSnapshot(from url: URL) throws -> LoupeSnapshot {
        try diagnosticJSONDecoder().decode(LoupeSnapshot.self, from: Data(contentsOf: url))
    }

    private static func diagnosticJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
