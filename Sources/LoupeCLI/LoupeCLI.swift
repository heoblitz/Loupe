import Foundation
import LoupeCLIModel
import LoupeCore
import LoupeHID

@main
struct LoupeCLI {
    static func main() async {
        do {
            try await runMain()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func runMain() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.isEmpty ? "help" : arguments.removeFirst()

        switch command {
        case "accessibility":
            try accessibility(arguments)
        case "audit":
            try audit(arguments)
        case "compact":
            try compact(arguments)
        case "compare-design":
            try compareDesign(arguments)
        case "cleanup":
            try await cleanup(arguments)
        case "diff":
            try diff(arguments)
        case "doctor":
            try doctor(arguments)
        case "fetch":
            try await fetch(arguments)
        case "install-skills":
            try skills(["install"] + arguments)
        case "logs":
            try await runtimeFetch(arguments, path: "/logs", usage: "loupe logs [--host <url>] [--udid <sim>] [--output <path>]")
        case "apps", "runtimes":
            try await runtimes(arguments)
        case "injector-path":
            try injectorPath(arguments)
        case "inspect":
            try inspect(arguments)
        case "reflect":
            try reflect(arguments)
        case "runtime":
            try await runtimeFetch(arguments, path: "/runtime", usage: "loupe runtime [--host <url>] [--udid <sim>] [--output <path>]")
        case "mutations":
            try await mutations(arguments)
        case "set", "mutate":
            try await set(arguments)
        case "query":
            try await query(arguments)
        case "launch":
            try await launch(arguments)
        case "screenshot":
            try screenshot(arguments)
        case "skills":
            try skills(arguments)
        case "start":
            try await start(arguments)
        case "subtree":
            try subtree(arguments)
        case "tree":
            try await tree(arguments)
        case "use":
            try await use(arguments)
        case "current":
            try await current(arguments)
        case "text-map":
            try await tree(arguments + ["--text"])
        case "trace-summary":
            try traceSummary(arguments)
        case "tap", "swipe", "drag", "pinch", "type":
            try await action(command: command, arguments: arguments)
        case "wait-for-visible":
            try await waitFor(arguments, mode: .visible)
        case "wait-for-gone":
            try await waitFor(arguments, mode: .gone)
        case "wait-for-value":
            try await waitFor(arguments, mode: .value)
        case "help", "--help", "-h":
            printHelp()
        default:
            throw CLIError("Unknown command: \(command)")
        }
    }

    private static func compact(_ arguments: [String]) throws {
        guard arguments.count == 1 else {
            throw CLIError("Usage: loupe compact <snapshot.json>")
        }

        let url = URL(fileURLWithPath: arguments[0])
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
        let observation = LoupeObservationCompactor.compact(snapshot)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        FileHandle.standardOutput.write(try encoder.encode(observation))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func query(_ arguments: [String]) async throws {
        let options = try QueryOptions(arguments)
        let snapshot: LoupeSnapshot
        if let snapshotURL = options.snapshotURL {
            let data = try Data(contentsOf: snapshotURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
        } else {
            let host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid,
                bundleID: options.bundleID
            )
            if let udid = options.udid {
                try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
            }
            snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        switch options.tree {
        case .view:
            let results = LoupeSnapshotQuery.find(
                options.selector,
                in: snapshot,
                options: LoupeQueryOptions(
                    includeHidden: options.includeHidden,
                    includeDisabled: true,
                    maxResults: options.maxResults
                )
            )
            FileHandle.standardOutput.write(try encoder.encode(results))
        case .accessibility:
            let tree = LoupeAccessibilityTree.build(from: snapshot, includeHidden: options.includeHidden)
            let results = LoupeAccessibilityTreeQuery.find(
                options.selector,
                in: tree,
                options: LoupeQueryOptions(
                    includeHidden: options.includeHidden,
                    includeDisabled: true,
                    maxResults: options.maxResults
                )
            )
            FileHandle.standardOutput.write(try encoder.encode(results))
        }
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func accessibility(_ arguments: [String]) throws {
        let options = try AccessibilityOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
        let tree = LoupeAccessibilityTree.build(from: snapshot, includeHidden: options.includeHidden)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        FileHandle.standardOutput.write(try encoder.encode(tree))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func inspect(_ arguments: [String]) throws {
        let options = try InspectOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)

        guard let inspection = LoupeSnapshotInspector.inspect(
            options.selector,
            in: snapshot,
            options: LoupeQueryOptions(includeHidden: options.includeHidden)
        ) else {
            throw CLIError("No Loupe node matched selector")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        FileHandle.standardOutput.write(try encoder.encode(inspection))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func subtree(_ arguments: [String]) throws {
        let options = try SubtreeOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)

        guard let subtree = LoupeSnapshotInspector.subtree(
            options.selector,
            in: snapshot,
            maxDepth: options.depth,
            options: LoupeQueryOptions(includeHidden: options.includeHidden)
        ) else {
            throw CLIError("No Loupe node matched selector")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        FileHandle.standardOutput.write(try encoder.encode(subtree))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func tree(_ arguments: [String]) async throws {
        let options = try TreeOptions(arguments)
        let snapshot: LoupeSnapshot
        let accessibilityTree: LoupeAccessibilityTree?

        if let snapshotURL = options.snapshotURL {
            let data = try Data(contentsOf: snapshotURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
            accessibilityTree = options.tree == .accessibility
                ? LoupeAccessibilityTree.build(from: snapshot, includeHidden: options.includeHidden)
                : nil
        } else {
            let host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid,
                bundleID: options.bundleID
            )
            if let udid = options.udid {
                try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
            }
            snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
            accessibilityTree = options.tree == .accessibility
                ? try await fetchAccessibilityTree(host: host, fallbackSnapshot: snapshot, timeout: options.timeout)
                : nil
        }

        let output: String
        switch options.tree {
        case .view:
            output = renderViewTree(
                snapshot,
                selector: options.selector,
                depth: options.depth,
                includeHidden: options.includeHidden,
                presentation: options.presentation
            )
        case .accessibility:
            output = renderAccessibilityTree(
                accessibilityTree ?? LoupeAccessibilityTree.build(from: snapshot, includeHidden: options.includeHidden),
                selector: options.selector,
                depth: options.depth,
                includeHidden: options.includeHidden,
                presentation: options.presentation
            )
        }
        print(output)
    }

    private static func audit(_ arguments: [String]) throws {
        let options = try AuditOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
        let audit = LoupeLayoutAuditor.audit(
            snapshot,
            options: LoupeLayoutAuditOptions(
                tolerance: options.tolerance,
                minOverlapArea: options.minOverlapArea,
                minTouchTarget: options.minTouchTarget,
                minContrastRatio: options.minContrastRatio
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(audit))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func diff(_ arguments: [String]) throws {
        let options = try DiffOptions(arguments)
        let before = try decodeSnapshot(from: options.beforeURL)
        let after = try decodeSnapshot(from: options.afterURL)
        let summary = snapshotDiff(before: before, after: after)

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(summary))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print(renderSnapshotDiff(summary, limit: options.limit))
    }

    private static func traceSummary(_ arguments: [String]) throws {
        let options = try TraceSummaryOptions(arguments)
        let summary = try makeTraceSummary(directory: options.directory)

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write(try encoder.encode(summary))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print(renderTraceSummary(summary, limit: options.limit))
    }

    private static func compareDesign(_ arguments: [String]) throws {
        let options = try CompareDesignOptions(arguments)
        let snapshot = try decodeSnapshot(from: options.snapshotURL)
        let decoder = JSONDecoder()
        let design = try decoder.decode(LoupeDesignDocument.self, from: Data(contentsOf: options.designURL))
        let comparison = LoupeDesignComparator.compare(
            snapshot: snapshot,
            design: design,
            options: LoupeDesignComparisonOptions(
                frameTolerance: options.frameTolerance,
                colorTolerance: options.colorTolerance,
                cornerRadiusTolerance: options.cornerRadiusTolerance,
                fontSizeTolerance: options.fontSizeTolerance,
                maxMatchDistance: options.maxMatchDistance,
                includeUnexpectedAppNodes: options.includeUnexpectedAppNodes
            )
        )

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(comparison))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print(renderDesignComparison(comparison, limit: options.limit))
    }

    private static func skills(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError("Usage: loupe skills install [--target all|codex|claude] [--source <skills/loupe>]")
        }

        switch subcommand {
        case "install":
            try installSkills(Array(arguments.dropFirst()))
        default:
            throw CLIError("Unknown skills command: \(subcommand)")
        }
    }

    private static func installSkills(_ arguments: [String]) throws {
        let options = try InstallSkillsOptions(arguments)
        let source = try resolvedSkillSource(options.sourceURL)
        let targets = options.target.targets
        var installed = 0

        for target in targets {
            guard FileManager.default.fileExists(atPath: target.root.path) else {
                print("skipped \(target.name): \(target.root.path) does not exist")
                continue
            }

            let skillsDirectory = target.root.appendingPathComponent("skills", isDirectory: true)
            let destination = skillsDirectory.appendingPathComponent("loupe", isDirectory: true)
            try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            installed += 1
            print("installed \(target.name): \(destination.path)")
        }

        if installed == 0 {
            throw CLIError("No supported skill folders found. Create ~/.codex or ~/.claude first, or pass --target for an installed client.")
        }
    }

    private static func cleanup(_ arguments: [String]) async throws {
        let options = try CleanupOptions(arguments)
        var report = CleanupReport()

        if options.pruneRuntimes {
            report.runtimeRecordsRemoved = try await cleanupRuntimeRecords(options: options)
        }
        if options.pruneTraces {
            report.traceBundlesRemoved = try cleanupDirectory(
                traceRootDirectory(),
                olderThan: options.tracesOlderThan,
                dryRun: options.dryRun
            )
        }
        print("\(options.dryRun ? "would remove" : "removed") runtimeRecords=\(report.runtimeRecordsRemoved) traceBundles=\(report.traceBundlesRemoved)")
    }

    private static func cleanupRuntimeRecords(options: CleanupOptions) async throws -> Int {
        let records = try loadRuntimeHostRecords()
        var removed = 0

        for record in records {
            var shouldRemove = true
            if let host = URL(string: record.host),
               let state = try? await fetchRuntimeState(host: host, timeout: options.timeout),
               state.identity.simulatorUDID == record.udid,
               state.identity.bundleIdentifier == record.bundleID {
                shouldRemove = false
            }

            guard shouldRemove else {
                continue
            }

            removed += 1
            if !options.dryRun {
                try? FileManager.default.removeItem(at: runtimeHostRecordURL(udid: record.udid))
            }
        }

        return removed
    }

    private static func cleanupDirectory(_ directory: URL, olderThan age: TimeInterval, dryRun: Bool) throws -> Int {
        guard age >= 0 else {
            throw CLIError("cleanup age must be non-negative")
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        let cutoff = Date().addingTimeInterval(-age)
        var removed = 0
        for url in urls {
            guard itemModificationDate(url) <= cutoff else {
                continue
            }
            removed += 1
            if !dryRun {
                try FileManager.default.removeItem(at: url)
            }
        }
        return removed
    }

    private static func itemModificationDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date.distantPast
    }

    private static func traceRootDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("loupe-traces", isDirectory: true)
    }

    private static func start(_ arguments: [String]) async throws {
        var launchArguments: [String] = []
        var index = 0
        var hasInject = false

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--port":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw CLIError("--port requires a value")
                }
                let rawPort = arguments[valueIndex]
                guard let port = Int(rawPort), (1...65535).contains(port) else {
                    throw CLIError("--port must be a valid TCP port")
                }
                launchArguments.append(contentsOf: ["--env", "LOUPE_PORT=\(port)"])
                index = valueIndex
            case "--inject":
                hasInject = true
                launchArguments.append(argument)
            default:
                launchArguments.append(argument)
            }
            index += 1
        }

        if !hasInject {
            launchArguments.append("--inject")
        }
        try await launch(launchArguments)
    }

    private static func launch(_ arguments: [String]) async throws {
        let options = try LaunchOptions(arguments)
        var environment = options.environment
        var runtimeUDID: String?
        var runtimeHost: URL?

        if options.shouldInject, let dylibPath = try resolvedInjectorPath(explicitPath: options.dylibPath) {
            environment["DYLD_INSERT_LIBRARIES"] = dylibPath
            let udid = try resolveSimulatorUDID(options.device)
            let port = try resolvedLoupePort(for: udid, environment: environment)
            let host = URL(string: "http://127.0.0.1:\(port)")!
            try validateLaunchPort(host: host, expectedUDID: udid, expectedBundleID: options.bundleID)
            environment["LOUPE_PORT"] = String(port)
            runtimeUDID = udid
            runtimeHost = host
            try terminateAppIfRunning(device: udid, bundleID: options.bundleID, timeout: min(5, options.timeout))
        }

        let request = SimctlLaunchRequest(
            device: options.device,
            bundleID: options.bundleID,
            environment: environment
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = SimctlCommandBuilder.launchArguments(for: request)
        process.environment = SimctlCommandBuilder.launchEnvironment(for: request)

        try run(process, label: "simctl launch", timeout: options.timeout)

        if let runtimeUDID, let runtimeHost {
            try await waitForRuntime(host: runtimeHost, expectedUDID: runtimeUDID, timeout: options.timeout)
            try storeRuntimeHost(udid: runtimeUDID, bundleID: options.bundleID, host: runtimeHost)
            try storeCurrentRuntimeHost(LoupeRuntimeHostRecord(udid: runtimeUDID, bundleID: options.bundleID, host: runtimeHost.absoluteString, updatedAt: Date()))
            print("loupe host: \(runtimeHost.absoluteString)")
        }
    }

    private static func injectorPath(_ arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw CLIError("Usage: loupe injector-path")
        }

        guard let path = try resolvedInjectorPath(explicitPath: nil) else {
            throw CLIError("LoupeInjector not found. Set LOUPE_INJECTOR_PATH or install Loupe through Homebrew.")
        }

        print(path)
    }

    private static func doctor(_ arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw CLIError("Usage: loupe doctor")
        }

        print("loupe: ok")

        if let path = try resolvedInjectorPath(explicitPath: nil) {
            print("injector: \(path)")
        } else {
            print("injector: not found")
            print("hint: set LOUPE_INJECTOR_PATH or install via Homebrew")
        }

        let simctl = Process()
        simctl.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        simctl.arguments = ["simctl", "help"]
        simctl.standardOutput = Pipe()
        simctl.standardError = Pipe()
        try simctl.run()
        simctl.waitUntilExit()
        print("simctl: \(simctl.terminationStatus == 0 ? "ok" : "unavailable")")
        print("action backend native: ok")
    }

    private static func resolvedInjectorPath(explicitPath: String?) throws -> String? {
        if let explicitPath {
            guard FileManager.default.isExecutableFile(atPath: explicitPath) else {
                throw CLIError("Injector is not executable: \(explicitPath)")
            }
            return explicitPath
        }

        return LoupeInjectorPathResolver().resolve()
    }

    private static func fetch(_ arguments: [String]) async throws {
        let options = try FetchOptions(arguments)
        let (data, response) = try await httpData(from: options.url, timeout: options.timeout, label: "fetch")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("fetch expected an HTTP response")
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("fetch failed with HTTP \(httpResponse.statusCode)")
        }

        if let outputURL = options.outputURL {
            try data.write(to: outputURL)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func printHelp() {
        print(
            """
            loupe

            Commands:
              accessibility <snapshot.json> [--include-hidden]
                  Print the accessibility tree derived from a full app snapshot.

              compact <snapshot.json>
                  Print the LLM-facing compact observation for a full app snapshot.

              cleanup [--dry-run] [--traces-older-than 7d]
                  Remove stale runtime records and old trace bundles.

              compare-design <snapshot.json> <design.json> [--json]
                  Compare a Loupe snapshot against an exported Figma-style design JSON.

              diff <before-snapshot.json> <after-snapshot.json> [--json] [--limit <n>]
                  Summarize appeared, disappeared, changed value/text/state, and moved nodes.

              doctor
                  Check local Loupe installation and injector discovery.

              fetch <url> [--output <path>] [--timeout <seconds>]
                  Fetch a probe endpoint such as http://127.0.0.1:8765/observation.

              logs [--host <url>] [--udid <sim>] [--output <path>] [--timeout <seconds>]
                  Fetch runtime logs emitted by the injected Loupe SDK.

              runtimes|apps [--json]
                  List known injected Loupe runtimes, hosts, bundles, and live status.

              use <bundle-id> | use --host <url>
                  Set the current Loupe runtime used when --host, --udid, and --bundle-id are omitted.

              current [--json]
                  Print the current Loupe runtime selection.

              injector-path
                  Print the LoupeInjector executable path used for simulator injection.

              inspect <snapshot.json> (--test-id <id> | --ref <ref> | --text <text> | --role <role>)
                  Print one full node plus parent, sibling, and child summaries.

              subtree <snapshot.json> (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--depth <n>]
                  Print a bounded subtree rooted at a matched node.

              tree [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--view|--accessibility] [--depth <n>]
                  Print a human-readable view or accessibility tree prefix.

              tree --interesting|--visible-leaves|--text|--mutable
                  Print discovery-focused tree slices for deep or container-heavy screens.

              text-map [snapshot.json] [--accessibility]
                  Print visible text-bearing nodes.

              trace-summary <trace-dir> [--json] [--limit <n>]
                  Summarize an action trace bundle, including target, errors, logs, and snapshot diff.

              audit <snapshot.json> [--tolerance <points>] [--min-overlap-area <points2>]
                  Report layout, target-size, testID, and contrast issues.

              query [snapshot.json] (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--bundle-id <id>] [--tree view|accessibility]
                  Query a full snapshot view tree or derived accessibility tree.

              set (--test-id <id> | --ref <ref>) <property> <value> [--udid <sim>] [--bundle-id <id>]
                  Mutate a supported UIKit view property through the injected runtime.

              set --list | mutations [--host <url>] [--udid <sim>] [--bundle-id <id>]
                  List runtime-supported UIKit mutation properties and aliases.

              mutations (--ref <ref> | --text <text> | --test-id <id>)
                  Print mutation properties that are useful for one matched node.

              reflect <mutation-response.json> --source <dir> [--output <path>]
                  Summarize a runtime mutation with hierarchy context and source candidates.

              wait-for-visible (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--host <url>]
                  Poll /snapshot until a visible node matches.

              wait-for-gone (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--host <url>]
                  Poll until a visible node no longer matches.

              wait-for-value (--test-id <id> | --ref <ref>) --key <path> --equals <value> [--host <url>]
                  Poll until an inspected node property matches.

              launch --bundle-id <id> [--device booted] [--inject] [--dylib <path>] [--env KEY=VALUE]
                  Launch an iOS Simulator app through simctl. --inject auto-resolves LoupeInjector.

              tap (--test-id <id> | --ref <ref> | --x <n> --y <n>) --udid <sim> [--expect-visible <testID>]
                  Resolve a Loupe target or coordinate and tap it through the native HID backend.

              swipe|drag --from x,y --to x,y --udid <sim>
                  Dispatch a one-finger gesture through the native HID backend. Add --trace-dir <path> to save before/after artifacts.

              pinch --center x,y --start-spread <n> --end-spread <n> --udid <sim>
                  Parse a two-finger pinch request. Pinch HID dispatch is not implemented yet.

              type <text> --udid <sim>
                  Type text into the focused field through the native HID backend.

              screenshot --udid <sim> --output <path> [--timeout <seconds>]
                  Capture a simulator screenshot through simctl.

              skills install [--target all|codex|claude] [--source <skills/loupe>]
                  Upsert the Loupe skill into existing Codex or Claude Code skill folders.

              start --bundle-id <id> [--device booted] [--port 8765] [--env KEY=VALUE]
                  Launch and inject the app so the in-app Loupe runtime server starts.

              runtime [--host <url>] [--udid <sim>] [--output <path>] [--timeout <seconds>]
                  Fetch injected SDK runtime identity and logs.
            """
        )
    }

    private static func mutations(_ arguments: [String]) async throws {
        let options = try MutationListOptions(arguments)
        guard let selector = options.selector else {
            try await runtimeFetch(
                arguments,
                path: "/mutations",
                usage: "loupe mutations [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
            return
        }

        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }
        let snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        let matches = LoupeSnapshotQuery.find(
            selector,
            in: snapshot,
            options: LoupeQueryOptions(includeHidden: options.includeHidden, includeDisabled: true, maxResults: 20)
        )
        guard let result = matches.first, let node = snapshot.nodes[result.ref] else {
            throw CLIError("No view node matched selector")
        }
        let output = renderNodeMutationCapabilities(node)
        if let outputURL = options.outputURL {
            try Data((output + "\n").utf8).write(to: outputURL)
        } else {
            print(output)
        }
    }

    private static func set(_ arguments: [String]) async throws {
        if arguments.contains("--list") {
            try await runtimeFetch(
                arguments.filter { $0 != "--list" },
                path: "/mutations",
                usage: "loupe set --list [--host <url>] [--udid <sim>] [--output <path>]"
            )
            return
        }

        let options = try MutationSetOptions(arguments)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let body = try encoder.encode(options.request)
        var request = URLRequest(url: host.appendingPathComponent("mutate"))
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await httpData(for: request, timeout: options.timeout, label: "mutation")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("mutation expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw CLIError("mutation failed with HTTP \(httpResponse.statusCode): \(body)")
        }
        try write(data: data, outputURL: options.outputURL)
    }

    private static func reflect(_ arguments: [String]) throws {
        let options = try MutationReflectOptions(arguments)
        let data = try Data(contentsOf: options.mutationURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(LoupeMutationResponse.self, from: data)
        let reflection = mutationReflection(response, sourceRoot: options.sourceRoot)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(data: try encoder.encode(reflection), outputURL: options.outputURL)
    }

    private static func runtimes(_ arguments: [String]) async throws {
        let options = try RuntimeListOptions(arguments)
        let records = try loadRuntimeHostRecords()
        var rows: [RuntimeListRow] = []

        for record in records {
            var live = false
            var simulator = ""
            var pid = ""
            var startedAt = ""
            var bundleID = record.bundleID
            if let host = URL(string: record.host),
               let state = try? await fetchRuntimeState(host: host, timeout: options.timeout) {
                live = runtimeState(state, matches: record)
                if live {
                    simulator = state.identity.simulatorName ?? ""
                    pid = String(state.identity.processIdentifier)
                    startedAt = isoString(state.identity.startedAt)
                    bundleID = state.identity.bundleIdentifier ?? bundleID
                }
            }
            rows.append(
                RuntimeListRow(
                    udid: record.udid,
                    simulator: simulator,
                    bundleID: bundleID,
                    host: record.host,
                    pid: pid,
                    live: live,
                    startedAt: startedAt,
                    updatedAt: isoString(record.updatedAt)
                )
            )
        }

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(rows))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print("udid\tlive\tbundle\t host\tpid\tsimulator\tstartedAt\tupdatedAt")
        for row in rows {
            print("\(row.udid)\t\(row.live ? "yes" : "no")\t\(row.bundleID)\t\(row.host)\t\(row.pid)\t\(row.simulator)\t\(row.startedAt)\t\(row.updatedAt)")
        }
    }

    private static func screenshot(_ arguments: [String]) throws {
        let options = try ScreenshotOptions(arguments)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", options.udid, "screenshot", options.outputPath]
        try run(process, label: "simctl screenshot", timeout: options.timeout)
    }

    private static func action(command: String, arguments: [String]) async throws {
        var options = try ActionOptions(command: command, arguments: arguments)
        var target: ActionTarget?
        do {
            if command == "tap",
               let point = options.point,
               options.screen.width > 0,
               options.screen.height > 0,
               options.traceDirectory == nil,
               !options.hostWasExplicit,
               options.expectVisibleTestID == nil {
                let coordinateTarget = ActionTarget(point: point, screen: options.screen, screenScale: 1, source: .coordinates)
                target = coordinateTarget
                try dispatchAction(command: command, options: options, target: coordinateTarget)
                return
            }

            options.host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid
            )
            try await validateRuntimeIdentity(host: options.host, expectedUDID: options.udid, timeout: options.timeout)
            if let traceDirectory = options.traceDirectory {
                try prepareTraceDirectory(traceDirectory)
                try await writePreActionTrace(command: command, options: options, traceDirectory: traceDirectory)
            }
            let resolvedTarget = try await resolveActionTarget(options)
            target = resolvedTarget
            if let traceDirectory = options.traceDirectory {
                try writeActionRecord(
                    command: command,
                    options: options,
                    target: resolvedTarget,
                    phase: "target",
                    to: traceDirectory.appendingPathComponent("action-target.json")
                )
            }
            try dispatchAction(command: command, options: options, target: resolvedTarget)
            try await verifyRuntimeAlive(host: options.host, timeout: options.timeout)
            if let expected = options.expectVisibleTestID {
                try await expectVisible(expected, host: options.host, timeout: options.timeout)
            }
            if let traceDirectory = options.traceDirectory {
                try await Task.sleep(nanoseconds: 250_000_000)
                try await writePostActionTrace(command: command, options: options, target: resolvedTarget, traceDirectory: traceDirectory)
            }
        } catch {
            let traceDirectory = options.traceDirectory ?? automaticTraceDirectory(command: command)
            try? prepareTraceDirectory(traceDirectory)
            try? await writeFailureTrace(
                command: command,
                options: options,
                target: target,
                error: error,
                traceDirectory: traceDirectory
            )
            if options.traceDirectory == nil {
                FileHandle.standardError.write(Data("trace: \(traceDirectory.path)\n".utf8))
            }
            throw error
        }
    }

    private static func waitFor(_ arguments: [String], mode: WaitMode) async throws {
        let options = try WaitForOptions(arguments, mode: mode)
        let deadline = Date().addingTimeInterval(options.timeout)

        while true {
            let snapshot = try await fetchSnapshot(host: options.host, timeout: min(3, options.timeout))
            let accessibilityTree = try await fetchAccessibilityTree(
                host: options.host,
                fallbackSnapshot: snapshot,
                timeout: min(3, options.timeout)
            )
            let accessibilityResult = LoupeAccessibilityTreeQuery.first(
                options.selector,
                in: accessibilityTree,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            )
            let viewResult = LoupeSnapshotQuery.first(
                options.selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            )

            switch mode {
            case .visible:
                if let result = accessibilityResult {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    FileHandle.standardOutput.write(try encoder.encode(result))
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    return
                }
                if let result = viewResult {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    FileHandle.standardOutput.write(try encoder.encode(result))
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    return
                }
            case .gone:
                if accessibilityResult == nil, viewResult == nil {
                    print(#"{"status":"gone"}"#)
                    return
                }
            case .value:
                guard let keyPath = options.keyPath, let expectedValue = options.expectedValue else {
                    throw CLIError("wait-for-value requires --key <path> and --equals <value>")
                }
                if let node = firstMatchingNode(options.selector, in: snapshot),
                   let value = jsonValue(in: node, keyPath: keyPath),
                   valueMatches(value, expected: expectedValue) {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    FileHandle.standardOutput.write(try encoder.encode(node))
                    FileHandle.standardOutput.write(Data("\n".utf8))
                    return
                }
            }

            guard Date() < deadline else {
                switch mode {
                case .visible:
                    throw CLIError("Timed out waiting for visible Loupe node")
                case .gone:
                    throw CLIError("Timed out waiting for Loupe node to disappear")
                case .value:
                    throw CLIError("Timed out waiting for Loupe node value")
                }
            }

            try await Task.sleep(nanoseconds: UInt64(options.interval * 1_000_000_000))
        }
    }

    private static func expectVisible(_ testID: String, host: URL, timeout: TimeInterval) async throws {
        let options = WaitForOptions(
            host: host,
            selector: .testID(testID),
            timeout: timeout,
            interval: 0.25,
            keyPath: nil,
            expectedValue: nil
        )
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let snapshot = try await fetchSnapshot(host: options.host, timeout: min(3, options.timeout))
            let accessibilityTree = try await fetchAccessibilityTree(
                host: options.host,
                fallbackSnapshot: snapshot,
                timeout: min(3, options.timeout)
            )
            if LoupeAccessibilityTreeQuery.first(
                options.selector,
                in: accessibilityTree,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            ) != nil {
                return
            }
            if LoupeSnapshotQuery.first(
                options.selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            ) != nil {
                return
            }
            guard Date() < deadline else {
                throw CLIError("Timed out waiting for expected visible Loupe node: \(testID)")
            }
            try await Task.sleep(nanoseconds: UInt64(options.interval * 1_000_000_000))
        }
    }

    private static func resolveActionTarget(_ options: ActionOptions) async throws -> ActionTarget {
        if let point = options.point {
            let screen = try await resolveActionScreen(options)
            return ActionTarget(point: point, screen: screen.size, screenScale: screen.scale, source: .coordinates)
        }

        guard let selector = options.selector else {
            if options.command == "type" {
                return ActionTarget(
                    point: LoupePoint(x: 0, y: 0),
                    screen: options.screen,
                    screenScale: 1,
                    source: .keyboardFocus
                )
            }
            throw CLIError("\(options.command) requires a selector or coordinates")
        }

        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        let accessibilityTree = try await fetchAccessibilityTree(
            host: options.host,
            fallbackSnapshot: snapshot,
            timeout: options.timeout
        )
        let accessibilityMatches = uniqueActionMatches(
            LoupeAccessibilityTreeQuery.find(
                selector,
                in: accessibilityTree,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: false, maxResults: 8)
            )
        )
        if accessibilityMatches.count > 1 {
            throw CLIError("Selector matched multiple accessibility nodes: \(matchSummary(accessibilityMatches))")
        }
        if let result = accessibilityMatches.first,
           let point = result.activationPoint ?? center(of: result.frame) {
            return ActionTarget(
                point: point,
                screen: snapshot.screen.size,
                screenScale: snapshot.screen.scale,
                source: .accessibility(ref: result.ref, sourceRef: result.sourceRef),
                match: .accessibility(result)
            )
        }

        let viewMatches = uniqueActionMatches(
            LoupeSnapshotQuery.find(
                selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: false, maxResults: 8)
            )
        )
        if viewMatches.count > 1 {
            throw CLIError("Selector matched multiple view nodes: \(matchSummary(viewMatches))")
        }
        guard let result = viewMatches.first else {
            throw CLIError("No Loupe accessibility or view node matched selector")
        }
        guard let point = center(of: result.frame) else {
            throw CLIError("Matched node has no frame: \(result.ref)")
        }

        return ActionTarget(
            point: point,
            screen: snapshot.screen.size,
            screenScale: snapshot.screen.scale,
            source: .view(ref: result.ref),
            match: .view(result)
        )
    }

    private static func resolveActionScreen(_ options: ActionOptions) async throws -> (size: LoupeSize, scale: Double) {
        if let screen = ActionScreenResolver.explicit(options.screen) {
            return (screen.size, screen.scale)
        }

        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        let screen = ActionScreenResolver.resolve(explicit: options.screen, fallback: snapshot.screen)
        return (screen.size, screen.scale)
    }

    private static func center(of frame: LoupeRect?) -> LoupePoint? {
        guard let frame else {
            return nil
        }
        return LoupePoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    private static func uniqueActionMatches(
        _ matches: [LoupeAccessibilityQueryResult]
    ) -> [LoupeAccessibilityQueryResult] {
        var seen = Set<String>()
        return matches.filter { match in
            seen.insert(actionEquivalenceKey(match)).inserted
        }
    }

    private static func uniqueActionMatches(_ matches: [LoupeQueryResult]) -> [LoupeQueryResult] {
        var seen = Set<String>()
        return matches.filter { match in
            seen.insert(actionEquivalenceKey(match)).inserted
        }
    }

    private static func actionEquivalenceKey(_ match: LoupeAccessibilityQueryResult) -> String {
        [
            match.role ?? "",
            match.testID ?? "",
            match.text ?? "",
            geometryKey(frame: match.frame, activationPoint: match.activationPoint),
        ].joined(separator: "|")
    }

    private static func actionEquivalenceKey(_ match: LoupeQueryResult) -> String {
        [
            match.role ?? "",
            match.testID ?? "",
            match.text ?? "",
            geometryKey(frame: match.frame, activationPoint: nil),
        ].joined(separator: "|")
    }

    private static func geometryKey(frame: LoupeRect?, activationPoint: LoupePoint?) -> String {
        let frameKey: String
        if let frame {
            frameKey = [frame.x, frame.y, frame.width, frame.height].map(roundedKey).joined(separator: ",")
        } else {
            frameKey = "nil"
        }
        let pointKey: String
        if let activationPoint {
            pointKey = [activationPoint.x, activationPoint.y].map(roundedKey).joined(separator: ",")
        } else {
            pointKey = "nil"
        }
        return "\(frameKey)|\(pointKey)"
    }

    private static func roundedKey(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func matchSummary(_ matches: [LoupeAccessibilityQueryResult]) -> String {
        matches
            .map { "\($0.ref)\($0.testID.map { "#\($0)" } ?? "")\($0.text.map { " \"\($0)\"" } ?? "")" }
            .joined(separator: ", ")
    }

    private static func matchSummary(_ matches: [LoupeQueryResult]) -> String {
        matches
            .map { "\($0.ref)\($0.testID.map { "#\($0)" } ?? "")\($0.text.map { " \"\($0)\"" } ?? "")" }
            .joined(separator: ", ")
    }

    private static func fetchSnapshot(host: URL, timeout: TimeInterval = 5) async throws -> LoupeSnapshot {
        let url = host.appendingPathComponent("snapshot")
        let (data, response) = try await httpData(from: url, timeout: timeout, label: "snapshot fetch")
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("snapshot fetch failed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeSnapshot.self, from: data)
    }

    private static func fetchAccessibilityTree(
        host: URL,
        fallbackSnapshot: LoupeSnapshot,
        timeout: TimeInterval = 5
    ) async throws -> LoupeAccessibilityTree {
        let url = host.appendingPathComponent("accessibility")
        do {
            let (data, response) = try await httpData(from: url, timeout: timeout, label: "accessibility fetch")
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return LoupeAccessibilityTree.build(from: fallbackSnapshot)
            }
            return try JSONDecoder().decode(LoupeAccessibilityTree.self, from: data)
        } catch {
            return LoupeAccessibilityTree.build(from: fallbackSnapshot)
        }
    }

    static func fetchRuntimeState(host: URL, timeout: TimeInterval = 5) async throws -> LoupeRuntimeState {
        let url = host.appendingPathComponent("runtime")
        let (data, response) = try await httpData(from: url, timeout: timeout, label: "runtime fetch")
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime fetch failed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeRuntimeState.self, from: data)
    }

    static func validateRuntimeIdentity(host: URL, expectedUDID: String, timeout: TimeInterval = 5) async throws {
        let expected = try resolvedBackendUDID(expectedUDID)
        let state = try await fetchRuntimeState(host: host, timeout: timeout)
        guard let actual = state.identity.simulatorUDID, !actual.isEmpty else {
            throw CLIError("Loupe runtime did not report SIMULATOR_UDID; cannot validate --udid \(expected)")
        }
        guard actual == expected else {
            let bundle = state.identity.bundleIdentifier ?? "unknown-bundle"
            throw CLIError(
                "Loupe runtime at \(host.absoluteString) is \(bundle) on simulator \(actual), not requested --udid \(expected)"
            )
        }
    }

    private static func verifyRuntimeAlive(host: URL, timeout: TimeInterval) async throws {
        _ = try await fetchRuntimeState(host: host, timeout: timeout)
    }

    private static func waitForRuntime(host: URL, expectedUDID: String, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        repeat {
            do {
                try await validateRuntimeIdentity(host: host, expectedUDID: expectedUDID, timeout: min(1, timeout))
                return
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        } while Date() < deadline

        throw CLIError("Timed out waiting for Loupe runtime at \(host.absoluteString): \(lastError.map(String.init(describing:)) ?? "no response")")
    }

    private static func resolvedLoupePort(for udid: String, environment: [String: String]) throws -> UInt16 {
        if let rawPort = environment["LOUPE_PORT"] {
            guard let port = UInt16(rawPort), port > 0 else {
                throw CLIError("LOUPE_PORT must be a valid TCP port")
            }
            return port
        }

        return stablePort(for: udid)
    }

    private static func stablePort(for udid: String) -> UInt16 {
        var hash: UInt32 = 2_166_136_261
        for byte in udid.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        return UInt16(8_765 + (hash % 1_000))
    }

    private static func validateLaunchPort(host: URL, expectedUDID: String, expectedBundleID: String) throws {
        var request = URLRequest(url: host.appendingPathComponent("runtime"))
        request.timeoutInterval = 0.75
        let semaphore = DispatchSemaphore(value: 0)
        let probe = LaunchPortProbe()
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                probe.result = .failure(error)
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                probe.result = .failure(CLIError("port is occupied by a non-Loupe HTTP service"))
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            probe.result = Result { try decoder.decode(LoupeRuntimeState.self, from: data) }
        }.resume()

        guard semaphore.wait(timeout: .now() + 1) == .success, let result = probe.result else {
            return
        }

        switch result {
        case let .success(state):
            guard state.identity.simulatorUDID == expectedUDID else {
                let actual = state.identity.simulatorUDID ?? "unknown"
                throw CLIError("Loupe port collision at \(host.absoluteString): running simulator \(actual), requested \(expectedUDID)")
            }
            guard state.identity.bundleIdentifier == expectedBundleID else {
                let actual = state.identity.bundleIdentifier ?? "unknown"
                throw CLIError("Loupe port collision at \(host.absoluteString): running bundle \(actual), requested \(expectedBundleID)")
            }
        case let .failure(error as CLIError):
            throw error
        case .failure:
            return
        }
    }

    private static func terminateAppIfRunning(device: String, bundleID: String, timeout: TimeInterval) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "terminate", device, bundleID]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        try process.run()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw CLIError("simctl terminate timed out after \(format(timeout))s for \(bundleID) on \(device)")
        }
    }

    private static func prepareTraceDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func writePreActionTrace(
        command: String,
        options: ActionOptions,
        traceDirectory: URL
    ) async throws {
        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        try writeJSON(snapshot, to: traceDirectory.appendingPathComponent("before-snapshot.json"))
        try writeJSON(
            try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot, timeout: options.timeout),
            to: traceDirectory.appendingPathComponent("before-accessibility.json")
        )
        try await writeRuntimeTracePayload(
            host: options.host,
            path: "logs",
            to: traceDirectory.appendingPathComponent("before-logs.json")
        )
        try writeActionRecord(
            command: command,
            options: options,
            target: nil,
            phase: "before",
            to: traceDirectory.appendingPathComponent("action-before.json")
        )

        let udid = try resolvedBackendUDID(options.udid)
        try captureSimulatorScreenshot(
            udid: udid,
            outputURL: traceDirectory.appendingPathComponent("before.png")
        )
    }

    private static func writePostActionTrace(
        command: String,
        options: ActionOptions,
        target: ActionTarget,
        traceDirectory: URL
    ) async throws {
        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        try writeJSON(snapshot, to: traceDirectory.appendingPathComponent("after-snapshot.json"))
        try writeJSON(
            try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot, timeout: options.timeout),
            to: traceDirectory.appendingPathComponent("after-accessibility.json")
        )
        try await writeRuntimeTracePayload(
            host: options.host,
            path: "logs",
            to: traceDirectory.appendingPathComponent("after-logs.json")
        )
        try writeActionRecord(
            command: command,
            options: options,
            target: target,
            phase: "after",
            to: traceDirectory.appendingPathComponent("action-after.json")
        )

        let udid = try resolvedBackendUDID(options.udid)
        let screenshotURL = traceDirectory.appendingPathComponent("after.png")
        try captureSimulatorScreenshot(udid: udid, outputURL: screenshotURL)
        try? cropTargetImage(
            target: target,
            screenshotURL: screenshotURL,
            outputURL: traceDirectory.appendingPathComponent("target-crop.png")
        )
    }

    private static func writeFailureTrace(
        command: String,
        options: ActionOptions,
        target: ActionTarget?,
        error: Error,
        traceDirectory: URL
    ) async throws {
        try writeJSON(
            LoupeCLIActionErrorTrace(message: String(describing: error), recordedAt: Date()),
            to: traceDirectory.appendingPathComponent("error.json")
        )
        try writeActionRecord(
            command: command,
            options: options,
            target: target,
            phase: "failure",
            to: traceDirectory.appendingPathComponent("action-failure.json")
        )
        if let snapshot = try? await fetchSnapshot(host: options.host, timeout: min(3, options.timeout)) {
            try? writeJSON(snapshot, to: traceDirectory.appendingPathComponent("failure-snapshot.json"))
            if let tree = try? await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot, timeout: min(3, options.timeout)) {
                try? writeJSON(tree, to: traceDirectory.appendingPathComponent("failure-accessibility.json"))
            }
        }
        try? await writeRuntimeTracePayload(
            host: options.host,
            path: "logs",
            to: traceDirectory.appendingPathComponent("failure-logs.json")
        )
        if let udid = try? resolvedBackendUDID(options.udid) {
            let screenshotURL = traceDirectory.appendingPathComponent("failure.png")
            try? captureSimulatorScreenshot(udid: udid, outputURL: screenshotURL)
            if let target {
                try? cropTargetImage(
                    target: target,
                    screenshotURL: screenshotURL,
                    outputURL: traceDirectory.appendingPathComponent("target-crop.png")
                )
            }
        }
    }

    private static func automaticTraceDirectory(command: String) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return traceRootDirectory()
            .appendingPathComponent("\(stamp)-\(command)", isDirectory: true)
    }

    private static func writeActionRecord(
        command: String,
        options: ActionOptions,
        target: ActionTarget?,
        phase: String,
        to url: URL
    ) throws {
        let record = LoupeCLIActionTrace(
            command: command,
            phase: phase,
            host: options.host.absoluteString,
            backend: options.backend,
            udid: options.udid,
            selector: options.selector.map(selectorDescription),
            point: options.point,
            endPoint: options.endPoint,
            duration: options.duration,
            text: options.text,
            resolvedPoint: target?.point,
            resolvedScreen: target?.screen,
            resolvedSource: target?.source.description,
            resolvedTarget: target?.match?.trace,
            recordedAt: Date()
        )
        try writeJSON(record, to: url)
    }

    private static func captureSimulatorScreenshot(udid: String, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "screenshot", "--type=png", outputURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try run(process, label: "simctl screenshot", timeout: 10)
    }

    private static func cropTargetImage(
        target: ActionTarget,
        screenshotURL: URL,
        outputURL: URL
    ) throws {
        guard let frame = target.match?.trace.frame, !frame.isEmpty else {
            return
        }
        let pixelSize = try pngPixelSize(screenshotURL)
        let scaleX = pixelSize.width / max(target.screen.width, 1)
        let scaleY = pixelSize.height / max(target.screen.height, 1)
        let padding: Double = 8
        let x = max(0, Int(((frame.x - padding) * scaleX).rounded(.down)))
        let y = max(0, Int(((frame.y - padding) * scaleY).rounded(.down)))
        let maxWidth = max(1, Int(pixelSize.width) - x)
        let maxHeight = max(1, Int(pixelSize.height) - y)
        let width = min(maxWidth, max(1, Int(((frame.width + padding * 2) * scaleX).rounded(.up))))
        let height = min(maxHeight, max(1, Int(((frame.height + padding * 2) * scaleY).rounded(.up))))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            screenshotURL.path,
            "--cropToHeightWidth", String(height), String(width),
            "--cropOffset", String(y), String(x),
            "--out", outputURL.path,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try run(process, label: "sips crop", timeout: 5)
    }

    private static func pngPixelSize(_ url: URL) throws -> LoupeSize {
        let data = try Data(contentsOf: url)
        guard data.count >= 24 else {
            throw CLIError("Could not read PNG size")
        }
        let width = UInt32(data[16]) << 24
            | UInt32(data[17]) << 16
            | UInt32(data[18]) << 8
            | UInt32(data[19])
        let height = UInt32(data[20]) << 24
            | UInt32(data[21]) << 16
            | UInt32(data[22]) << 8
            | UInt32(data[23])
        return LoupeSize(width: Double(width), height: Double(height))
    }

    private static func writeRuntimeTracePayload(host: URL, path: String, to url: URL) async throws {
        let endpoint = host.appendingPathComponent(path)
        let (data, response) = try await httpData(from: endpoint, timeout: 5, label: "runtime trace fetch")
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime trace fetch failed for /\(path)")
        }
        try data.write(to: url)
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }

    private static func selectorDescription(_ selector: LoupeSelector) -> String {
        switch selector {
        case let .testID(value):
            return "testID:\(value)"
        case let .text(value, exact):
            return exact ? "text:\(value)" : "textContains:\(value)"
        case let .role(value):
            return "role:\(value)"
        case let .roleAndText(role, text, exact):
            return exact ? "roleAndText:\(role):\(text)" : "roleAndTextContains:\(role):\(text)"
        case let .ref(value):
            return "ref:\(value)"
        }
    }

    private static func dispatchAction(command: String, options: ActionDispatchOptions, target: ActionTarget) throws {
        guard command != "pinch" else {
            throw CLIError("pinch is not supported by the native HID backend yet")
        }

        try validateActionBackend(options.backend)
        let udid = try resolvedBackendUDID(options.udid)
        let mappedPoint = mapToDisplayPoint(target.point)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status: Int32
        switch command {
        case "tap":
            status = LoupeHIDTap(udid, mappedPoint.x, mappedPoint.y, target.screen.width, target.screen.height, &errorMessage)
        case "swipe", "drag":
            let end = try options.requireEndPoint(command: command)
            let mappedEnd = mapToDisplayPoint(end)
            status = LoupeHIDDrag(
                udid,
                mappedPoint.x,
                mappedPoint.y,
                mappedEnd.x,
                mappedEnd.y,
                target.screen.width,
                target.screen.height,
                options.duration ?? 0.6,
                &errorMessage
            )
        case "type":
            status = LoupeHIDType(udid, options.text ?? "", &errorMessage)
        case "pinch":
            throw CLIError("pinch is not supported by the native HID backend yet")
        default:
            throw CLIError("Unsupported action command: \(command)")
        }

        if let errorMessage {
            defer { LoupeHIDFreeCString(errorMessage) }
            if status != 0 {
                throw CLIError("native HID \(command) failed: \(String(cString: errorMessage))")
            }
        } else if status != 0 {
            throw CLIError("native HID \(command) failed")
        }
    }

    private static func mapToDisplayPoint(_ point: LoupePoint) -> LoupePoint {
        point
    }

    private static func simulatorDisplaySize(udid: String, scale: Double) throws -> LoupeSize {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-display-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "screenshot", "--type=png", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try run(process, label: "simctl screenshot")

        let data = try Data(contentsOf: url)
        guard data.count >= 24 else {
            throw CLIError("Could not read simulator screenshot size")
        }

        let width = UInt32(data[16]) << 24
            | UInt32(data[17]) << 16
            | UInt32(data[18]) << 8
            | UInt32(data[19])
        let height = UInt32(data[20]) << 24
            | UInt32(data[21]) << 16
            | UInt32(data[22]) << 8
            | UInt32(data[23])

        return LoupeSize(width: Double(width) / scale, height: Double(height) / scale)
    }

    private static func validateActionBackend(_ requested: String) throws {
        guard requested == "auto" || requested == "native" else {
            throw CLIError("Unsupported action backend: \(requested). Loupe currently supports native only.")
        }
    }

    static func resolvedBackendUDID(_ requested: String) throws -> String {
        guard requested == "booted" else {
            return requested
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "--json"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try run(process, label: "simctl list booted devices", timeout: simctlListTimeout())

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devicesByRuntime = object["devices"] as? [String: [[String: Any]]]
        else {
            throw CLIError("Could not parse booted simulator list")
        }

        let booted = devicesByRuntime.values
            .flatMap { $0 }
            .filter { ($0["state"] as? String) == "Booted" }

        guard booted.count == 1 else {
            throw CLIError("Expected exactly one booted simulator, found \(booted.count). Pass --udid <UDID>.")
        }

        guard let udid = booted[0]["udid"] as? String else {
            throw CLIError("Booted simulator did not include a UDID")
        }

        return udid
    }

    private static func resolveSimulatorUDID(_ requested: String) throws -> String {
        if requested == "booted" {
            return try resolvedBackendUDID(requested)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "--json"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try run(process, label: "simctl list devices", timeout: simctlListTimeout())

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devicesByRuntime = object["devices"] as? [String: [[String: Any]]]
        else {
            throw CLIError("Could not parse simulator device list")
        }

        let devices = devicesByRuntime.values.flatMap { $0 }
        if devices.contains(where: { ($0["udid"] as? String) == requested }) {
            return requested
        }

        let bootedMatches = devices.filter {
            ($0["name"] as? String) == requested && ($0["state"] as? String) == "Booted"
        }
        guard bootedMatches.count == 1 else {
            throw CLIError("Expected exactly one booted simulator named \(requested), found \(bootedMatches.count). Pass --device <UDID>.")
        }

        guard let udid = bootedMatches[0]["udid"] as? String else {
            throw CLIError("Simulator \(requested) did not include a UDID")
        }
        return udid
    }

    private static func simctlListTimeout() -> TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["LOUPE_SIMCTL_LIST_TIMEOUT"],
              let value = Double(raw),
              value > 0 else {
            return 60
        }
        return value
    }

    private static func executablePath(named name: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func httpData(
        from url: URL,
        timeout: TimeInterval,
        label: String
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await httpData(for: request, timeout: timeout, label: label)
    }

    static func httpData(
        for request: URLRequest,
        timeout: TimeInterval,
        label: String
    ) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = timeout
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw CLIError("\(label) timed out or failed for \(request.url?.absoluteString ?? "unknown-url"): \(error.localizedDescription)")
        }
    }

    private static func run(_ process: Process, label: String, timeout: TimeInterval = 10) throws {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        try process.run()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw CLIError("\(label) timed out after \(format(timeout))s")
        }
        guard process.terminationStatus == 0 else {
            throw CLIError("\(label) exited with status \(process.terminationStatus)")
        }
    }

    static func write(data: Data, outputURL: URL?) throws {
        if let outputURL {
            try data.write(to: outputURL)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func decodeSnapshot(from url: URL) throws -> LoupeSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeSnapshot.self, from: Data(contentsOf: url))
    }

    private static func snapshotDiff(before: LoupeSnapshot, after: LoupeSnapshot) -> LoupeSnapshotDiff {
        let beforeIndex = indexedNodes(before)
        let afterIndex = indexedNodes(after)
        let beforeKeys = Set(beforeIndex.keys)
        let afterKeys = Set(afterIndex.keys)

        let appeared = afterKeys.subtracting(beforeKeys)
            .compactMap { key in afterIndex[key].map { diffNodeSummary(key: key, node: $0) } }
            .sorted { $0.key < $1.key }
        let disappeared = beforeKeys.subtracting(afterKeys)
            .compactMap { key in beforeIndex[key].map { diffNodeSummary(key: key, node: $0) } }
            .sorted { $0.key < $1.key }

        let changed = beforeKeys.intersection(afterKeys)
            .compactMap { key -> LoupeNodeChange? in
                guard let beforeNode = beforeIndex[key], let afterNode = afterIndex[key] else {
                    return nil
                }
                let changes = changedFields(before: beforeNode, after: afterNode)
                guard !changes.isEmpty else {
                    return nil
                }
                return LoupeNodeChange(key: key, summary: nodeSummary(afterNode), changes: changes)
            }
            .sorted { $0.key < $1.key }

        return LoupeSnapshotDiff(
            beforeSnapshotID: before.id,
            afterSnapshotID: after.id,
            appeared: appeared,
            disappeared: disappeared,
            changed: changed
        )
    }

    private static func indexedNodes(_ snapshot: LoupeSnapshot) -> [String: LoupeNode] {
        var counts: [String: Int] = [:]
        var result: [String: LoupeNode] = [:]

        for node in snapshot.nodes.values {
            let baseKey = nodeIdentityKey(node)
            let count = counts[baseKey, default: 0]
            counts[baseKey] = count + 1
            let key = count == 0 ? baseKey : "\(baseKey)#\(node.ref)"
            result[key] = node
        }
        return result
    }

    private static func nodeIdentityKey(_ node: LoupeNode) -> String {
        if let testID = node.testID, !testID.isEmpty {
            return "testID:\(testID)"
        }
        if let identifier = node.accessibility?.identifier, !identifier.isEmpty {
            return "axID:\(identifier)"
        }
        let type = node.uiKit?.className ?? node.typeName
        let role = node.role ?? ""
        let text = displayText(node) ?? ""
        if let frame = node.frame {
            return "visual:\(type):\(role):\(text):\(rectSummary(frame))"
        }
        return "ref:\(node.ref)"
    }

    private static func diffNodeSummary(key: String, node: LoupeNode) -> LoupeNodeDiffSummary {
        LoupeNodeDiffSummary(
            key: key,
            ref: node.ref,
            typeName: node.uiKit?.className ?? node.typeName,
            role: node.role,
            testID: node.testID,
            text: displayText(node),
            frame: node.frame
        )
    }

    private static func nodeSummary(_ node: LoupeNode) -> String {
        [
            node.uiKit?.className ?? node.typeName,
            node.testID.map { "#\($0)" },
            displayText(node).map { "\"\($0)\"" },
            node.frame.map(rectSummary),
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func changedFields(before: LoupeNode, after: LoupeNode) -> [LoupeNodeFieldChange] {
        var changes: [LoupeNodeFieldChange] = []
        appendChange("text", displayText(before), displayText(after), to: &changes)
        appendChange("value", before.value, after.value, to: &changes)
        appendChange("isVisible", before.isVisible, after.isVisible, to: &changes)
        appendChange("isEnabled", before.isEnabled, after.isEnabled, to: &changes)
        appendChange("isInteractive", before.isInteractive, after.isInteractive, to: &changes)
        appendChange("frame", before.frame.map(rectSummary), after.frame.map(rectSummary), to: &changes)
        appendChange("uiKit.switch.isOn", before.uiKit?.switchControl?.isOn, after.uiKit?.switchControl?.isOn, to: &changes)
        appendChange("uiKit.segmentedControl.selectedSegmentIndex", before.uiKit?.segmentedControl?.selectedSegmentIndex, after.uiKit?.segmentedControl?.selectedSegmentIndex, to: &changes)
        appendChange("uiKit.slider.value", before.uiKit?.slider?.value, after.uiKit?.slider?.value, to: &changes)
        appendChange("uiKit.stepper.value", before.uiKit?.stepper?.value, after.uiKit?.stepper?.value, to: &changes)
        appendChange("uiKit.pageControl.currentPage", before.uiKit?.pageControl?.currentPage, after.uiKit?.pageControl?.currentPage, to: &changes)
        appendChange("uiKit.progressView.value", before.uiKit?.progressView?.value, after.uiKit?.progressView?.value, to: &changes)
        return changes
    }

    private static func appendChange<T: Equatable>(
        _ field: String,
        _ before: T?,
        _ after: T?,
        to changes: inout [LoupeNodeFieldChange]
    ) {
        guard before != after else {
            return
        }
        changes.append(
            LoupeNodeFieldChange(
                field: field,
                before: before.map { String(describing: $0) },
                after: after.map { String(describing: $0) }
            )
        )
    }

    private static func renderSnapshotDiff(_ diff: LoupeSnapshotDiff, limit: Int) -> String {
        var lines: [String] = [
            "diff \(diff.beforeSnapshotID) -> \(diff.afterSnapshotID)",
            "appeared=\(diff.appeared.count) disappeared=\(diff.disappeared.count) changed=\(diff.changed.count)",
        ]

        appendSection("appeared", diff.appeared.prefix(limit).map(renderDiffNode), to: &lines)
        appendSection("disappeared", diff.disappeared.prefix(limit).map(renderDiffNode), to: &lines)
        appendSection("changed", diff.changed.prefix(limit).map(renderNodeChange), to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendSection<S: Sequence>(_ title: String, _ items: S, to lines: inout [String]) where S.Element == String {
        let rendered = Array(items)
        guard !rendered.isEmpty else {
            return
        }
        lines.append("")
        lines.append("\(title):")
        lines.append(contentsOf: rendered.map { "  \($0)" })
    }

    private static func renderDiffNode(_ node: LoupeNodeDiffSummary) -> String {
        [
            node.key,
            node.typeName,
            node.role.map { "role=\($0)" },
            node.testID.map { "testID=\($0)" },
            node.text.map { "text=\"\($0)\"" },
            node.frame.map { "frame=\(rectSummary($0))" },
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func renderNodeChange(_ change: LoupeNodeChange) -> String {
        let fields = change.changes
            .map { "\($0.field):\($0.before ?? "nil")->\($0.after ?? "nil")" }
            .joined(separator: ", ")
        return "\(change.key) \(change.summary) \(fields)"
    }

    private static func makeTraceSummary(directory: URL) throws -> LoupeTraceSummary {
        let beforeAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-before.json"))
        let targetAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-target.json"))
        let afterAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-after.json"))
        let failureAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-failure.json"))
        let error = try readJSONIfExists(LoupeCLIActionErrorTrace.self, directory.appendingPathComponent("error.json"))

        let beforeLogs = (try readJSONIfExists([LoupeRuntimeLog].self, directory.appendingPathComponent("before-logs.json"))) ?? []
        let afterLogs = (try readJSONIfExists([LoupeRuntimeLog].self, directory.appendingPathComponent("after-logs.json"))) ?? []
        let failureLogs = (try readJSONIfExists([LoupeRuntimeLog].self, directory.appendingPathComponent("failure-logs.json"))) ?? []
        let newLogs = afterLogs.filter { afterLog in
            !beforeLogs.contains(where: { $0.id == afterLog.id })
        }

        let beforeSnapshotURL = directory.appendingPathComponent("before-snapshot.json")
        let afterSnapshotURL = directory.appendingPathComponent("after-snapshot.json")
        let diff: LoupeSnapshotDiff?
        if FileManager.default.fileExists(atPath: beforeSnapshotURL.path),
           FileManager.default.fileExists(atPath: afterSnapshotURL.path) {
            diff = try snapshotDiff(before: decodeSnapshot(from: beforeSnapshotURL), after: decodeSnapshot(from: afterSnapshotURL))
        } else {
            diff = nil
        }

        let cropURL = directory.appendingPathComponent("target-crop.png")
        return LoupeTraceSummary(
            directory: directory.path,
            command: afterAction?.command ?? failureAction?.command ?? targetAction?.command ?? beforeAction?.command,
            phase: error == nil ? (afterAction?.phase ?? targetAction?.phase ?? beforeAction?.phase) : "failure",
            selector: afterAction?.selector ?? failureAction?.selector ?? targetAction?.selector ?? beforeAction?.selector,
            target: afterAction?.resolvedTarget ?? failureAction?.resolvedTarget ?? targetAction?.resolvedTarget,
            error: error?.message,
            diff: diff,
            newLogs: newLogs,
            failureLogs: failureLogs,
            targetCropPath: FileManager.default.fileExists(atPath: cropURL.path) ? cropURL.path : nil
        )
    }

    private static func readJSONIfExists<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private static func renderTraceSummary(_ summary: LoupeTraceSummary, limit: Int) -> String {
        var lines = [
            "trace \(summary.directory)",
            "command=\(summary.command ?? "unknown") phase=\(summary.phase ?? "unknown") selector=\(summary.selector ?? "none")",
        ]
        if let target = summary.target {
            lines.append("target=\(target.tree):\(target.ref) testID=\(target.testID ?? "none") role=\(target.role ?? "none") frame=\(target.frame.map(rectSummary) ?? "nil")")
        }
        if let targetCropPath = summary.targetCropPath {
            lines.append("targetCrop=\(targetCropPath)")
        }
        if let error = summary.error {
            lines.append("error=\(error)")
        }
        if let diff = summary.diff {
            lines.append("")
            lines.append(renderSnapshotDiff(diff, limit: limit))
        }
        let logs = summary.error == nil ? summary.newLogs : summary.failureLogs
        if !logs.isEmpty {
            lines.append("")
            lines.append("logs:")
            for log in logs.prefix(limit) {
                lines.append("  \(log.level) \(log.message)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderDesignComparison(_ comparison: LoupeDesignComparison, limit: Int) -> String {
        var lines = [
            "design \(comparison.designFrameName) vs snapshot \(comparison.snapshotID)",
            "matched=\(comparison.matchedCount) issues=\(comparison.issueCount)",
        ]

        if !comparison.matches.isEmpty {
            lines.append("")
            lines.append("matches:")
            for match in comparison.matches.prefix(limit) {
                lines.append("  \(match.strategy) \(match.designID ?? match.designName) -> \(match.ref) testID=\(match.testID ?? "none")")
            }
        }

        if !comparison.issues.isEmpty {
            lines.append("")
            lines.append("issues:")
            for issue in comparison.issues.prefix(limit) {
                let subject = issue.designID ?? issue.testID ?? issue.designName ?? issue.ref ?? "unknown"
                let property = issue.property.map { " \($0)" } ?? ""
                let expected = issue.expected.map { " expected=\($0)" } ?? ""
                let actual = issue.actual.map { " actual=\($0)" } ?? ""
                lines.append("  \(issue.kind.rawValue) \(subject)\(property)\(expected)\(actual): \(issue.message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func resolvedSkillSource(_ explicitSource: URL?) throws -> URL {
        var candidates: [URL] = []
        if let explicitSource {
            candidates.append(explicitSource)
        }
        if let env = ProcessInfo.processInfo.environment["LOUPE_SKILL_SOURCE"], !env.isEmpty {
            candidates.append(URL(fileURLWithPath: env, isDirectory: true))
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory.appendingPathComponent("skills/loupe", isDirectory: true))

        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("../share/loupe/skills/loupe", isDirectory: true)
                    .standardizedFileURL
            )
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/share/loupe/skills/loupe", isDirectory: true))
        candidates.append(URL(fileURLWithPath: "/usr/local/share/loupe/skills/loupe", isDirectory: true))

        for candidate in candidates {
            let skillFile = candidate.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillFile.path) {
                return candidate
            }
        }

        throw CLIError("Could not find Loupe skill source. Run from the repo root or pass --source <path-to-skills/loupe>.")
    }

    private static func renderViewTree(
        _ snapshot: LoupeSnapshot,
        selector: LoupeSelector?,
        depth: Int?,
        includeHidden: Bool,
        presentation: TreePresentation = .outline
    ) -> String {
        if presentation != .outline {
            return renderFlatViewTree(snapshot, selector: selector, includeHidden: includeHidden, presentation: presentation)
        }

        let roots: [String]
        if let selector {
            roots = LoupeSnapshotQuery.find(
                selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 20)
            ).map(\.ref)
        } else {
            roots = snapshot.rootRefs
        }

        var lines: [String] = []
        for ref in roots {
            appendViewTree(ref: ref, snapshot: snapshot, depth: 0, maxDepth: depth, includeHidden: includeHidden, lines: &lines)
        }
        guard !lines.isEmpty else {
            return "(empty)"
        }
        var output = lines.joined(separator: "\n")
        if let depth, depth <= 5, visiblePrefixContainsOnlyContainers(roots: roots, snapshot: snapshot, maxDepth: depth, includeHidden: includeHidden) {
            output += "\n\nhint: Only container nodes found at depth \(depth). Try --depth 8 or `loupe tree --interesting`."
        }
        return output
    }

    private static func appendViewTree(
        ref: String,
        snapshot: LoupeSnapshot,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        lines: inout [String]
    ) {
        guard let node = snapshot.nodes[ref] else {
            return
        }
        if !includeHidden, !node.isVisible {
            return
        }
        lines.append("\(String(repeating: "  ", count: depth))\(viewTreeLine(node))")
        guard maxDepth.map({ depth < $0 }) ?? true else {
            return
        }
        for child in node.children {
            appendViewTree(ref: child, snapshot: snapshot, depth: depth + 1, maxDepth: maxDepth, includeHidden: includeHidden, lines: &lines)
        }
    }

    private static func renderAccessibilityTree(
        _ tree: LoupeAccessibilityTree,
        selector: LoupeSelector?,
        depth: Int?,
        includeHidden: Bool,
        presentation: TreePresentation = .outline
    ) -> String {
        if presentation != .outline {
            return renderFlatAccessibilityTree(tree, selector: selector, includeHidden: includeHidden, presentation: presentation)
        }

        let roots: [String]
        if let selector {
            roots = LoupeAccessibilityTreeQuery.find(
                selector,
                in: tree,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 20)
            ).map(\.ref)
        } else {
            roots = tree.rootRefs
        }

        var lines: [String] = []
        for ref in roots {
            appendAccessibilityTree(ref: ref, tree: tree, depth: 0, maxDepth: depth, includeHidden: includeHidden, lines: &lines)
        }
        guard !lines.isEmpty else {
            return "(empty)"
        }
        var output = lines.joined(separator: "\n")
        if let depth, depth <= 5, accessibilityPrefixContainsOnlyContainers(roots: roots, tree: tree, maxDepth: depth, includeHidden: includeHidden) {
            output += "\n\nhint: Only container nodes found at depth \(depth). Try --depth 8 or `loupe tree --interesting`."
        }
        return output
    }

    private static func appendAccessibilityTree(
        ref: String,
        tree: LoupeAccessibilityTree,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        lines: inout [String]
    ) {
        guard let node = tree.nodes[ref] else {
            return
        }
        if !includeHidden, !node.isVisible {
            return
        }
        lines.append("\(String(repeating: "  ", count: depth))\(accessibilityTreeLine(node))")
        guard maxDepth.map({ depth < $0 }) ?? true else {
            return
        }
        for child in node.children {
            appendAccessibilityTree(ref: child, tree: tree, depth: depth + 1, maxDepth: maxDepth, includeHidden: includeHidden, lines: &lines)
        }
    }

    private static func renderFlatViewTree(
        _ snapshot: LoupeSnapshot,
        selector: LoupeSelector?,
        includeHidden: Bool,
        presentation: TreePresentation
    ) -> String {
        let nodes = selectedViewNodes(snapshot, selector: selector, includeHidden: includeHidden)
            .filter { node in
                switch presentation {
                case .outline:
                    return true
                case .interesting:
                    return isInteresting(node)
                case .visibleLeaves:
                    return isVisibleLeaf(node, in: snapshot, includeHidden: includeHidden)
                case .text:
                    return displayText(node) != nil
                case .mutable:
                    return !supportedMutationProperties(for: node).isEmpty
                }
            }
        let lines = nodes.map(viewTreeLine)
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }

    private static func selectedViewNodes(
        _ snapshot: LoupeSnapshot,
        selector: LoupeSelector?,
        includeHidden: Bool
    ) -> [LoupeNode] {
        if let selector {
            return LoupeSnapshotQuery.find(
                selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 200)
            ).compactMap { snapshot.nodes[$0.ref] }
        }
        return snapshot.nodes.values
            .filter { includeHidden || $0.isVisible }
            .sorted(by: nodeScreenOrder)
    }

    private static func renderFlatAccessibilityTree(
        _ tree: LoupeAccessibilityTree,
        selector: LoupeSelector?,
        includeHidden: Bool,
        presentation: TreePresentation
    ) -> String {
        let nodes = selectedAccessibilityNodes(tree, selector: selector, includeHidden: includeHidden)
            .filter { node in
                switch presentation {
                case .outline, .mutable:
                    return true
                case .interesting:
                    return accessibilityDisplayText(node) != nil || node.testID != nil || node.isInteractive
                case .visibleLeaves:
                    return node.children.isEmpty
                case .text:
                    return accessibilityDisplayText(node) != nil
                }
            }
        let lines = nodes.map(accessibilityTreeLine)
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }

    private static func selectedAccessibilityNodes(
        _ tree: LoupeAccessibilityTree,
        selector: LoupeSelector?,
        includeHidden: Bool
    ) -> [LoupeAccessibilityNode] {
        if let selector {
            return LoupeAccessibilityTreeQuery.find(
                selector,
                in: tree,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 200)
            ).compactMap { tree.nodes[$0.ref] }
        }
        return tree.nodes.values
            .filter { includeHidden || $0.isVisible }
            .sorted(by: accessibilityNodeScreenOrder)
    }

    private static func nodeScreenOrder(_ lhs: LoupeNode, _ rhs: LoupeNode) -> Bool {
        if let lhsFrame = lhs.frame, let rhsFrame = rhs.frame {
            if abs(lhsFrame.y - rhsFrame.y) > 0.5 {
                return lhsFrame.y < rhsFrame.y
            }
            if abs(lhsFrame.x - rhsFrame.x) > 0.5 {
                return lhsFrame.x < rhsFrame.x
            }
        }
        return lhs.ref < rhs.ref
    }

    private static func accessibilityNodeScreenOrder(_ lhs: LoupeAccessibilityNode, _ rhs: LoupeAccessibilityNode) -> Bool {
        if let lhsFrame = lhs.frame, let rhsFrame = rhs.frame {
            if abs(lhsFrame.y - rhsFrame.y) > 0.5 {
                return lhsFrame.y < rhsFrame.y
            }
            if abs(lhsFrame.x - rhsFrame.x) > 0.5 {
                return lhsFrame.x < rhsFrame.x
            }
        }
        return lhs.ref < rhs.ref
    }

    private static func isInteresting(_ node: LoupeNode) -> Bool {
        displayText(node) != nil || node.testID != nil || node.isInteractive || node.role != nil
    }

    private static func isVisibleLeaf(_ node: LoupeNode, in snapshot: LoupeSnapshot, includeHidden: Bool) -> Bool {
        guard includeHidden || node.isVisible else {
            return false
        }
        return !node.children.contains { ref in
            guard let child = snapshot.nodes[ref] else {
                return false
            }
            return includeHidden || child.isVisible
        }
    }

    private static func visiblePrefixContainsOnlyContainers(
        roots: [String],
        snapshot: LoupeSnapshot,
        maxDepth: Int,
        includeHidden: Bool
    ) -> Bool {
        var visited: [LoupeNode] = []
        for root in roots {
            collectViewPrefix(ref: root, snapshot: snapshot, depth: 0, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &visited)
        }
        return !visited.isEmpty && visited.allSatisfy(isContainerOnly)
    }

    private static func collectViewPrefix(
        ref: String,
        snapshot: LoupeSnapshot,
        depth: Int,
        maxDepth: Int,
        includeHidden: Bool,
        nodes: inout [LoupeNode]
    ) {
        guard let node = snapshot.nodes[ref], includeHidden || node.isVisible else {
            return
        }
        nodes.append(node)
        guard depth < maxDepth else {
            return
        }
        for child in node.children {
            collectViewPrefix(ref: child, snapshot: snapshot, depth: depth + 1, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &nodes)
        }
    }

    private static func accessibilityPrefixContainsOnlyContainers(
        roots: [String],
        tree: LoupeAccessibilityTree,
        maxDepth: Int,
        includeHidden: Bool
    ) -> Bool {
        var visited: [LoupeAccessibilityNode] = []
        for root in roots {
            collectAccessibilityPrefix(ref: root, tree: tree, depth: 0, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &visited)
        }
        return !visited.isEmpty && visited.allSatisfy(isAccessibilityContainerOnly)
    }

    private static func collectAccessibilityPrefix(
        ref: String,
        tree: LoupeAccessibilityTree,
        depth: Int,
        maxDepth: Int,
        includeHidden: Bool,
        nodes: inout [LoupeAccessibilityNode]
    ) {
        guard let node = tree.nodes[ref], includeHidden || node.isVisible else {
            return
        }
        nodes.append(node)
        guard depth < maxDepth else {
            return
        }
        for child in node.children {
            collectAccessibilityPrefix(ref: child, tree: tree, depth: depth + 1, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &nodes)
        }
    }

    private static func viewTreeLine(_ node: LoupeNode) -> String {
        [
            node.ref,
            node.uiKit?.className ?? node.typeName,
            node.role.map { "role=\($0)" },
            node.testID.map { "testID=\($0)" },
            displayText(node).map { "text=\"\($0)\"" },
            node.frame.map { "frame=\(rectSummary($0))" },
            node.isVisible ? nil : "hidden",
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func accessibilityTreeLine(_ node: LoupeAccessibilityNode) -> String {
        [
            node.ref,
            node.role ?? "accessibility",
            "source=\(node.sourceRef)",
            node.testID.map { "testID=\($0)" },
            LoupeAccessibilityTreeQuery.displayText(for: node).map { "text=\"\($0)\"" },
            node.frame.map { "frame=\(rectSummary($0))" },
            node.isVisible ? nil : "hidden",
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func rectSummary(_ rect: LoupeRect) -> String {
        "\(format(rect.x)),\(format(rect.y)),\(format(rect.width)),\(format(rect.height))"
    }

    private static func displayText(_ node: LoupeNode) -> String? {
        [node.text, node.renderedText, node.semanticText, node.label, node.value, node.placeholder]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func accessibilityDisplayText(_ node: LoupeAccessibilityNode) -> String? {
        LoupeAccessibilityTreeQuery.displayText(for: node)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func isContainerOnly(_ node: LoupeNode) -> Bool {
        displayText(node) == nil
            && node.testID == nil
            && node.role == nil
            && !node.isInteractive
    }

    private static func isAccessibilityContainerOnly(_ node: LoupeAccessibilityNode) -> Bool {
        accessibilityDisplayText(node) == nil
            && node.testID == nil
            && node.role == nil
            && !node.isInteractive
    }

    private static func supportedMutationProperties(for node: LoupeNode) -> [String] {
        var properties = [
            "frame", "bounds", "center", "alpha", "hidden", "clipsToBounds",
            "userInteractionEnabled", "backgroundColor", "tintColor", "accessibility.label",
            "accessibility.value", "accessibility.hint", "accessibility.isElement",
        ]

        if isTextBacked(node) {
            properties += ["text", "textColor", "fontSize", "textAlignment", "lineBreakMode"]
        }
        if node.uiKit?.label != nil || node.role == "staticText" {
            properties += ["numberOfLines", "adjustsFontSizeToFitWidth", "minimumScaleFactor"]
        }
        if node.uiKit?.textField != nil || node.role == "textField" {
            properties += ["placeholder", "secureTextEntry"]
        }
        if node.uiKit?.button != nil || node.role == "button" {
            properties += ["title"]
        }
        if node.uiKit?.switchControl != nil || node.role == "switch" {
            properties += ["enabled", "selected", "highlighted", "switch.isOn"]
        } else if node.uiKit?.control != nil || node.isInteractive {
            properties += ["enabled", "selected", "highlighted"]
        }
        if node.uiKit?.slider != nil || node.role == "slider" {
            properties += ["slider.value", "slider.minimumValue", "slider.maximumValue"]
        }
        if node.uiKit?.stepper != nil || node.role == "stepper" {
            properties += ["stepper.value", "stepper.minimumValue", "stepper.maximumValue", "stepper.stepValue"]
        }
        if node.uiKit?.segmentedControl != nil || node.role == "segmentedControl" {
            properties += ["segmentedControl.selectedSegmentIndex"]
        }
        if node.uiKit?.pageControl != nil || node.role == "pageControl" {
            properties += ["pageControl.currentPage", "pageControl.numberOfPages"]
        }
        if node.uiKit?.progressView != nil || node.role == "progress" {
            properties += ["progressView.progress"]
        }
        if node.uiKit?.datePicker != nil || node.role == "datePicker" {
            properties += ["datePicker.date", "datePicker.countDownDuration"]
        }
        if node.uiKit?.activityIndicator != nil || node.role == "activityIndicator" {
            properties += ["activityIndicator.animating"]
        }
        if node.uiKit?.pickerView != nil || node.role == "pickerView" {
            properties += ["pickerView.selectedRow"]
        }
        if node.role == "scrollView" {
            properties += ["contentOffset", "contentSize", "contentInset", "scrollEnabled", "pagingEnabled"]
        }

        return Array(Set(properties)).sorted()
    }

    private static func unsupportedMutationExamples(for node: LoupeNode) -> [String] {
        if isTextBacked(node) {
            return []
        }
        return ["text"]
    }

    private static func isTextBacked(_ node: LoupeNode) -> Bool {
        node.uiKit?.label != nil
            || node.uiKit?.button != nil
            || node.uiKit?.textField != nil
            || node.uiKit?.textView != nil
            || ["UILabel", "UIButton", "UITextField", "UITextView"].contains(node.uiKit?.className ?? node.typeName)
    }

    private static func renderNodeMutationCapabilities(_ node: LoupeNode) -> String {
        let supported = supportedMutationProperties(for: node)
        let unsupported = unsupportedMutationExamples(for: node)
        var lines = [
            "\(node.ref) \(node.uiKit?.className ?? node.typeName)",
            "supported: \(supported.isEmpty ? "none" : supported.joined(separator: ", "))",
        ]
        if !unsupported.isEmpty {
            lines.append("unsupported: \(unsupported.joined(separator: ", "))")
        }
        if !isTextBacked(node), displayText(node) != nil {
            lines.append("hint: visible text is semantic/accessibility text; mutate accessibility.label or inspect the source view instead of text.")
        }
        return lines.joined(separator: "\n")
    }

    private static func firstMatchingNode(_ selector: LoupeSelector, in snapshot: LoupeSnapshot) -> LoupeNode? {
        LoupeSnapshotQuery.find(
            selector,
            in: snapshot,
            options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
        ).first.flatMap { snapshot.nodes[$0.ref] }
    }

    private static func jsonValue(in node: LoupeNode, keyPath: String) -> Any? {
        let normalizedPath = keyPath
            .replacingOccurrences(of: "uiKit.switch.", with: "uiKit.switchControl.")
            .replacingOccurrences(of: "uikit.", with: "uiKit.")
        guard let data = try? JSONEncoder().encode(node),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var current: Any? = object
        for key in normalizedPath.split(separator: ".").map(String.init) {
            if let dictionary = current as? [String: Any] {
                current = dictionary[key]
            } else {
                return nil
            }
        }
        return current
    }

    private static func valueMatches(_ value: Any, expected: String) -> Bool {
        if let bool = value as? Bool {
            return bool == (expected as NSString).boolValue
        }
        if let number = value as? NSNumber {
            if expected == "true" || expected == "false" {
                return number.boolValue == (expected as NSString).boolValue
            }
            return format(number.doubleValue) == expected || String(number.intValue) == expected
        }
        if let string = value as? String {
            return string == expected
        }
        return String(describing: value) == expected
    }

    private static func mutationReflection(
        _ response: LoupeMutationResponse,
        sourceRoot: URL
    ) -> LoupeMutationReflection {
        let testID = response.after.testID ?? response.target.testID ?? mutationSelectorTestID(response.selector)
        let hierarchy = response.hierarchy ?? mutationHierarchyContext(response)
        let candidates = testID.map {
            sourceCandidates(matching: $0, under: sourceRoot)
        } ?? []
        return LoupeMutationReflection(
            selector: response.selector,
            property: response.property,
            value: response.value,
            targetType: response.after.uiKit?.className ?? response.after.typeName,
            testID: testID,
            before: mutationNodeSummary(response.before),
            after: mutationNodeSummary(response.after),
            targetMatchesHierarchy: targetMatchesHierarchy(response: response, hierarchy: hierarchy),
            hierarchy: hierarchy,
            sourceCandidates: candidates
        )
    }

    private static func mutationSelectorTestID(_ selector: LoupeMutationSelector) -> String? {
        selector.kind == .testID ? selector.value : nil
    }

    private static func sourceCandidates(matching testID: String, under sourceRoot: URL) -> [LoupeMutationSourceCandidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [LoupeMutationSourceCandidate] = []
        for case let url as URL in enumerator {
            guard isSearchableSource(url),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            for (offset, line) in text.components(separatedBy: .newlines).enumerated()
                where line.contains(testID) {
                candidates.append(
                    LoupeMutationSourceCandidate(
                        path: url.path,
                        line: offset + 1,
                        text: line.trimmingCharacters(in: .whitespaces)
                    )
                )
            }
        }

        return candidates.sorted {
            if $0.path != $1.path { return $0.path < $1.path }
            return $0.line < $1.line
        }
    }

    private static func isSearchableSource(_ url: URL) -> Bool {
        ["swift", "m", "mm", "h", "xib", "storyboard"].contains(url.pathExtension)
    }

    private static func mutationHierarchyContext(_ response: LoupeMutationResponse) -> LoupeMutationHierarchyContext {
        LoupeMutationHierarchyContext(
            target: mutationNodeSummary(response.after),
            parent: response.after.parentRef.map {
                LoupeMutationNodeSummary(ref: $0, typeName: "unknown")
            },
            siblings: [],
            children: response.after.children.map {
                LoupeMutationNodeSummary(ref: $0, typeName: "unknown")
            }
        )
    }

    private static func targetMatchesHierarchy(
        response: LoupeMutationResponse,
        hierarchy: LoupeMutationHierarchyContext
    ) -> Bool {
        guard hierarchy.target.ref == response.after.ref else {
            return false
        }

        switch response.selector.kind {
        case .testID:
            return hierarchy.target.testID == response.selector.value
        case .ref:
            return hierarchy.target.ref == response.selector.value
        case .role:
            return hierarchy.target.role == response.selector.value
        case .text:
            guard let text = hierarchy.target.text else {
                return false
            }
            if response.selector.exact {
                return text == response.selector.value
            }
            return text.localizedCaseInsensitiveContains(response.selector.value)
        case .roleAndText:
            guard hierarchy.target.role == response.selector.role,
                  let text = hierarchy.target.text else {
                return false
            }
            if response.selector.exact {
                return text == response.selector.value
            }
            return text.localizedCaseInsensitiveContains(response.selector.value)
        }
    }

    private static func mutationNodeSummary(_ node: LoupeNode) -> LoupeMutationNodeSummary {
        LoupeMutationNodeSummary(
            ref: node.ref,
            typeName: node.uiKit?.className ?? node.typeName,
            role: node.role,
            testID: node.testID,
            text: displayText(node),
            frame: node.frame
        )
    }

    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

}
