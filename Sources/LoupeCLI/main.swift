import Foundation
import LoupeCore

@main
struct LoupeCLI {
    static func main() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.isEmpty ? "help" : arguments.removeFirst()

        switch command {
        case "accessibility":
            try accessibility(arguments)
        case "audit":
            try audit(arguments)
        case "compact":
            try compact(arguments)
        case "doctor":
            try doctor(arguments)
        case "fetch":
            try await fetch(arguments)
        case "logs":
            try await runtimeFetch(arguments, path: "/logs", usage: "loupe logs [--host <url>] [--output <path>]")
        case "injector-path":
            try injectorPath(arguments)
        case "inspect":
            try inspect(arguments)
        case "recording":
            try await runtimeFetch(arguments, path: "/recording", usage: "loupe recording [--host <url>] [--output <path>]")
        case "record-start":
            try await runtimeFetch(arguments, path: "/recording/start", usage: "loupe record-start [--host <url>] [--output <path>]")
        case "record-stop":
            try await runtimeFetch(arguments, path: "/recording/stop", usage: "loupe record-stop [--host <url>] [--output <path>]")
        case "query":
            try query(arguments)
        case "launch":
            try launch(arguments)
        case "replay":
            try replay(arguments)
        case "screenshot":
            try screenshot(arguments)
        case "subtree":
            try subtree(arguments)
        case "tap", "swipe", "drag", "pinch", "type":
            try await action(command: command, arguments: arguments)
        case "wait-for-visible":
            try await waitForVisible(arguments)
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

    private static func query(_ arguments: [String]) throws {
        let options = try QueryOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)

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

    private static func launch(_ arguments: [String]) throws {
        let options = try LaunchOptions(arguments)
        var environment = options.environment

        if options.shouldInject, let dylibPath = try resolvedInjectorPath(explicitPath: options.dylibPath) {
            environment["DYLD_INSERT_LIBRARIES"] = dylibPath
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

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CLIError("simctl launch exited with status \(process.terminationStatus)")
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
        try simctl.run()
        simctl.waitUntilExit()
        print("simctl: \(simctl.terminationStatus == 0 ? "ok" : "unavailable")")
        print("action backend axe: \(executablePath(named: "axe") ?? "not found")")
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
        let (data, response) = try await URLSession.shared.data(from: options.url)

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

              doctor
                  Check local Loupe installation and injector discovery.

              fetch <url> [--output <path>]
                  Fetch a probe endpoint such as http://127.0.0.1:8765/observation.

              logs [--host <url>] [--output <path>]
                  Fetch runtime logs emitted by the injected Loupe SDK.

              injector-path
                  Print the LoupeInjector executable path used for simulator injection.

              inspect <snapshot.json> (--test-id <id> | --ref <ref> | --text <text> | --role <role>)
                  Print one full node plus parent, sibling, and child summaries.

              subtree <snapshot.json> (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--depth <n>]
                  Print a bounded subtree rooted at a matched node.

              audit <snapshot.json> [--tolerance <points>] [--min-overlap-area <points2>]
                  Report layout, target-size, testID, and contrast issues.

              query <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--tree view|accessibility]
                  Query a full snapshot view tree or derived accessibility tree.

              wait-for-visible (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--host <url>]
                  Poll /snapshot until a visible node matches.

              launch --bundle-id <id> [--device booted] [--inject] [--dylib <path>] [--env KEY=VALUE]
                  Launch an iOS Simulator app through simctl. --inject auto-resolves LoupeInjector.

              tap (--test-id <id> | --ref <ref> | --text <text> | --x <n> --y <n>) --udid <sim>
                  Resolve a Loupe target and tap it through AXe. Add --trace-dir <path> to save before/after artifacts.

              swipe|drag --from x,y --to x,y --udid <sim>
                  Dispatch a one-finger gesture through AXe. Add --trace-dir <path> to save before/after artifacts.

              pinch --center x,y --start-spread <n> --end-spread <n> --udid <sim>
                  Parse a two-finger pinch request. AXe does not support pinch yet.

              type <text> --udid <sim>
                  Type text into the focused field through AXe.

              screenshot --udid <sim> --output <path>
                  Capture a simulator screenshot through simctl.

              record-start|record-stop|recording [--host <url>] [--output <path>]
                  Control and fetch the injected SDK touch recorder.

              replay <recording.json> --udid <sim>
                  Replay a Loupe recording as AXe actions. Pinch events are not supported yet.
            """
        )
    }

    private static func runtimeFetch(_ arguments: [String], path: String, usage: String) async throws {
        let options = try RuntimeFetchOptions(arguments, usage: usage)
        let url = options.host.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("runtime fetch expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime fetch failed with HTTP \(httpResponse.statusCode)")
        }
        try write(data: data, outputURL: options.outputURL)
    }

    private static func screenshot(_ arguments: [String]) throws {
        let options = try ScreenshotOptions(arguments)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", options.udid, "screenshot", options.outputPath]
        try run(process, label: "simctl screenshot")
    }

    private static func action(command: String, arguments: [String]) async throws {
        let options = try ActionOptions(command: command, arguments: arguments)
        if let traceDirectory = options.traceDirectory {
            try prepareTraceDirectory(traceDirectory)
            try await writePreActionTrace(command: command, options: options, traceDirectory: traceDirectory)
        }
        let target = try await resolveActionTarget(options)
        if let traceDirectory = options.traceDirectory {
            try writeActionRecord(
                command: command,
                options: options,
                target: target,
                phase: "target",
                to: traceDirectory.appendingPathComponent("action-target.json")
            )
        }
        try dispatchAction(command: command, options: options, target: target)
        if let traceDirectory = options.traceDirectory {
            try await Task.sleep(nanoseconds: 250_000_000)
            try await writePostActionTrace(command: command, options: options, target: target, traceDirectory: traceDirectory)
        }
    }

    private static func waitForVisible(_ arguments: [String]) async throws {
        let options = try WaitForVisibleOptions(arguments)
        let deadline = Date().addingTimeInterval(options.timeout)

        while true {
            let snapshot = try await fetchSnapshot(host: options.host)
            let accessibilityTree = try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot)
            if let result = LoupeAccessibilityTreeQuery.first(
                options.selector,
                in: accessibilityTree,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            ) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(result))
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }
            if let result = LoupeSnapshotQuery.first(
                options.selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            ) {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(result))
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }

            guard Date() < deadline else {
                throw CLIError("Timed out waiting for visible Loupe node")
            }

            try await Task.sleep(nanoseconds: UInt64(options.interval * 1_000_000_000))
        }
    }

    private static func replay(_ arguments: [String]) throws {
        let options = try ReplayOptions(arguments)
        let data = try Data(contentsOf: options.recordingURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recording = try decoder.decode(LoupeRecording.self, from: data)
        let actions = replayActions(from: recording, screen: options.screen)

        for action in actions {
            var actionOptions = options.actionOptions
            actionOptions.endPoint = action.endPoint
            actionOptions.startSpread = action.startSpread
            actionOptions.endSpread = action.endSpread
            try dispatchAction(command: action.command, options: actionOptions, target: action.target)
        }
    }

    private static func resolveActionTarget(_ options: ActionOptions) async throws -> ActionTarget {
        if let point = options.point {
            return ActionTarget(point: point, screen: options.screen, screenScale: 1, source: .coordinates)
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

        let snapshot = try await fetchSnapshot(host: options.host)
        let accessibilityTree = try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot)
        if let result = LoupeAccessibilityTreeQuery.first(selector, in: accessibilityTree) {
            if let point = result.activationPoint ?? center(of: result.frame) {
                return ActionTarget(
                    point: point,
                    screen: snapshot.screen.size,
                    screenScale: snapshot.screen.scale,
                    source: .accessibility(ref: result.ref, sourceRef: result.sourceRef),
                    match: .accessibility(result)
                )
            }
        }

        guard let result = LoupeSnapshotQuery.first(selector, in: snapshot) else {
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

    private static func center(of frame: LoupeRect?) -> LoupePoint? {
        guard let frame else {
            return nil
        }
        return LoupePoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    private static func fetchSnapshot(host: URL) async throws -> LoupeSnapshot {
        let url = host.appendingPathComponent("snapshot")
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("snapshot fetch failed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeSnapshot.self, from: data)
    }

    private static func fetchAccessibilityTree(
        host: URL,
        fallbackSnapshot: LoupeSnapshot
    ) async throws -> LoupeAccessibilityTree {
        let url = host.appendingPathComponent("accessibility")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return LoupeAccessibilityTree.build(from: fallbackSnapshot)
            }
            return try JSONDecoder().decode(LoupeAccessibilityTree.self, from: data)
        } catch {
            return LoupeAccessibilityTree.build(from: fallbackSnapshot)
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
        let snapshot = try await fetchSnapshot(host: options.host)
        try writeJSON(snapshot, to: traceDirectory.appendingPathComponent("before-snapshot.json"))
        try writeJSON(
            try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot),
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
        let snapshot = try await fetchSnapshot(host: options.host)
        try writeJSON(snapshot, to: traceDirectory.appendingPathComponent("after-snapshot.json"))
        try writeJSON(
            try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot),
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
        try captureSimulatorScreenshot(
            udid: udid,
            outputURL: traceDirectory.appendingPathComponent("after.png")
        )
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
        try run(process, label: "simctl screenshot")
    }

    private static func writeRuntimeTracePayload(host: URL, path: String, to url: URL) async throws {
        let endpoint = host.appendingPathComponent(path)
        let (data, response) = try await URLSession.shared.data(from: endpoint)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime trace fetch failed for /\(path)")
        }
        try data.write(to: url)
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
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
            throw CLIError("pinch is not supported by the AXe backend yet")
        }

        let backend = try resolveBackend(options.backend)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: backend.path)
        process.arguments = try axeArguments(command: command, options: options, target: target)
        try run(process, label: "\(backend.name) \(command)")
    }

    private static func axeArguments(
        command: String,
        options: ActionDispatchOptions,
        target: ActionTarget
    ) throws -> [String] {
        let udid = try resolvedBackendUDID(options.udid)
        let mappedPoint = try mapToDisplayPoint(target.point, target: target, udid: udid)
        switch command {
        case "tap":
            return ["tap", "-x", format(mappedPoint.x), "-y", format(mappedPoint.y), "--udid", udid]
        case "swipe", "drag":
            let end = try options.requireEndPoint(command: command)
            let mappedEnd = try mapToDisplayPoint(end, target: target, udid: udid)
            var arguments = [
                "swipe",
                "--start-x", format(mappedPoint.x),
                "--start-y", format(mappedPoint.y),
                "--end-x", format(mappedEnd.x),
                "--end-y", format(mappedEnd.y),
                "--udid", udid
            ]
            if let duration = options.duration {
                arguments.append(contentsOf: ["--duration", format(duration)])
            }
            return arguments
        case "type":
            return ["type", options.text ?? "", "--udid", udid]
        case "pinch":
            throw CLIError("pinch is not supported by the AXe backend yet")
        default:
            throw CLIError("Unsupported AXe command: \(command)")
        }
    }

    private static func mapToDisplayPoint(
        _ point: LoupePoint,
        target: ActionTarget,
        udid: String
    ) throws -> LoupePoint {
        guard target.screenScale > 1, target.screen.width > 0, target.screen.height > 0 else {
            return point
        }

        let display = try simulatorDisplaySize(udid: udid, scale: target.screenScale)
        guard display.width > target.screen.width || display.height > target.screen.height else {
            return point
        }

        let scale = min(display.width / target.screen.width, display.height / target.screen.height)
        let offsetX = (display.width - target.screen.width * scale) / 2
        let offsetY = (display.height - target.screen.height * scale) / 2
        return LoupePoint(x: point.x * scale + offsetX, y: point.y * scale + offsetY)
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

    private static func resolveBackend(_ requested: String) throws -> ActionBackend {
        guard requested == "auto" || requested == "axe" else {
            throw CLIError("Unsupported action backend: \(requested). Loupe currently supports AXe only.")
        }

        if let path = executablePath(named: "axe") {
            return ActionBackend(name: "axe", path: path)
        }

        throw CLIError("No action backend found. Install AXe with `brew install cameroncooke/axe/axe`.")
    }

    private static func resolvedBackendUDID(_ requested: String) throws -> String {
        guard requested == "booted" else {
            return requested
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "--json"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try run(process, label: "simctl list booted devices")

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

    private static func replayActions(from recording: LoupeRecording, screen: LoupeSize) -> [ReplayAction] {
        var actions: [ReplayAction] = []
        var currentStart: LoupeRuntimeEvent?
        var lastMove: LoupeRuntimeEvent?

        for event in recording.events where event.kind == .touch {
            switch event.phase {
            case .began:
                currentStart = event
                lastMove = nil
            case .moved:
                lastMove = event
            case .ended, .cancelled:
                guard let start = currentStart, let first = start.points.first, let last = event.points.first else {
                    continue
                }
                if start.points.count >= 2, event.points.count >= 2 {
                    let startSpread = distance(start.points[0], start.points[1])
                    let endSpread = distance(event.points[0], event.points[1])
                    let center = LoupePoint(x: (first.x + start.points[1].x) / 2, y: (first.y + start.points[1].y) / 2)
                    actions.append(
                        ReplayAction(
                            command: "pinch",
                            target: ActionTarget(point: center, screen: screen, screenScale: 1, source: .coordinates),
                            endPoint: nil,
                            startSpread: startSpread,
                            endSpread: endSpread
                        )
                    )
                } else if let move = lastMove, let movePoint = move.points.first, distance(first, movePoint) > 4 || distance(first, last) > 4 {
                    actions.append(
                        ReplayAction(
                            command: "swipe",
                            target: ActionTarget(point: first, screen: screen, screenScale: 1, source: .coordinates),
                            endPoint: last,
                            startSpread: nil,
                            endSpread: nil
                        )
                    )
                } else {
                    actions.append(
                        ReplayAction(
                            command: "tap",
                            target: ActionTarget(point: first, screen: screen, screenScale: 1, source: .coordinates),
                            endPoint: nil,
                            startSpread: nil,
                            endSpread: nil
                        )
                    )
                }
                currentStart = nil
                lastMove = nil
            case nil:
                continue
            }
        }

        return actions
    }

    private static func run(_ process: Process, label: String) throws {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError("\(label) exited with status \(process.terminationStatus)")
        }
    }

    private static func write(data: Data, outputURL: URL?) throws {
        if let outputURL {
            try data.write(to: outputURL)
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    private static func distance(_ lhs: LoupePoint, _ rhs: LoupePoint) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

private enum QueryTree: String {
    case view
    case accessibility
}

private struct QueryOptions {
    var snapshotURL: URL
    var selector: LoupeSelector
    var includeHidden: Bool
    var maxResults: Int
    var tree: QueryTree

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe query <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--tree view|accessibility]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        includeHidden = false
        maxResults = 50
        tree = .view

        var selector: LoupeSelector?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--test-id":
                selector = .testID(try Self.value(after: "--test-id", in: arguments, index: &index))
            case "--text":
                selector = .text(try Self.value(after: "--text", in: arguments, index: &index), exact: false)
            case "--exact-text":
                selector = .text(try Self.value(after: "--exact-text", in: arguments, index: &index), exact: true)
            case "--role":
                selector = .role(try Self.value(after: "--role", in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: "--ref", in: arguments, index: &index))
            case "--include-hidden":
                includeHidden = true
            case "--max-results":
                let rawValue = try Self.value(after: "--max-results", in: arguments, index: &index)
                guard let value = Int(rawValue), value > 0 else {
                    throw CLIError("--max-results expects a positive integer")
                }
                maxResults = value
            case "--tree":
                let rawValue = try Self.value(after: "--tree", in: arguments, index: &index)
                guard let value = QueryTree(rawValue: rawValue) else {
                    throw CLIError("--tree expects view or accessibility")
                }
                tree = value
            default:
                throw CLIError("Unknown query option: \(arguments[index])")
            }

            index += 1
        }

        guard let selector else {
            throw CLIError("query requires one selector option")
        }

        self.selector = selector
    }

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}

private struct AccessibilityOptions {
    var snapshotURL: URL
    var includeHidden: Bool

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe accessibility <snapshot.json> [--include-hidden]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        includeHidden = false

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--include-hidden":
                includeHidden = true
            default:
                throw CLIError("Unknown accessibility option: \(arguments[index])")
            }
            index += 1
        }
    }
}

private struct InspectOptions {
    var snapshotURL: URL
    var selector: LoupeSelector
    var includeHidden: Bool

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe inspect <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--include-hidden]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        includeHidden = false

        var selector: LoupeSelector?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--test-id":
                selector = .testID(try Self.value(after: "--test-id", in: arguments, index: &index))
            case "--text":
                selector = .text(try Self.value(after: "--text", in: arguments, index: &index), exact: false)
            case "--exact-text":
                selector = .text(try Self.value(after: "--exact-text", in: arguments, index: &index), exact: true)
            case "--role":
                selector = .role(try Self.value(after: "--role", in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: "--ref", in: arguments, index: &index))
            case "--include-hidden":
                includeHidden = true
            default:
                throw CLIError("Unknown inspect option: \(arguments[index])")
            }
            index += 1
        }

        guard let selector else {
            throw CLIError("inspect requires --test-id, --text, --role, or --ref")
        }

        self.selector = selector
    }

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}

private struct SubtreeOptions {
    var snapshotURL: URL
    var selector: LoupeSelector
    var includeHidden: Bool
    var depth: Int

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe subtree <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--depth <n>] [--include-hidden]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        includeHidden = false
        depth = 2

        var selector: LoupeSelector?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--test-id":
                selector = .testID(try Self.value(after: "--test-id", in: arguments, index: &index))
            case "--text":
                selector = .text(try Self.value(after: "--text", in: arguments, index: &index), exact: false)
            case "--exact-text":
                selector = .text(try Self.value(after: "--exact-text", in: arguments, index: &index), exact: true)
            case "--role":
                selector = .role(try Self.value(after: "--role", in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: "--ref", in: arguments, index: &index))
            case "--depth":
                let raw = try Self.value(after: "--depth", in: arguments, index: &index)
                guard let value = Int(raw), value >= 0 else {
                    throw CLIError("--depth expects a non-negative integer")
                }
                depth = value
            case "--include-hidden":
                includeHidden = true
            default:
                throw CLIError("Unknown subtree option: \(arguments[index])")
            }
            index += 1
        }

        guard let selector else {
            throw CLIError("subtree requires --test-id, --text, --role, or --ref")
        }

        self.selector = selector
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

private struct AuditOptions {
    var snapshotURL: URL
    var tolerance: Double
    var minOverlapArea: Double
    var minTouchTarget: Double
    var minContrastRatio: Double

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe audit <snapshot.json> [--tolerance <points>] [--min-overlap-area <points2>] [--min-touch-target <points>] [--min-contrast-ratio <ratio>]")
        }

        snapshotURL = URL(fileURLWithPath: path)
        tolerance = 1
        minOverlapArea = 16
        minTouchTarget = 44
        minContrastRatio = 4.5

        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--tolerance":
                tolerance = try Self.double(after: "--tolerance", in: arguments, index: &index)
            case "--min-overlap-area":
                minOverlapArea = try Self.double(after: "--min-overlap-area", in: arguments, index: &index)
            case "--min-touch-target":
                minTouchTarget = try Self.double(after: "--min-touch-target", in: arguments, index: &index)
            case "--min-contrast-ratio":
                minContrastRatio = try Self.double(after: "--min-contrast-ratio", in: arguments, index: &index)
            default:
                throw CLIError("Unknown audit option: \(arguments[index])")
            }
            index += 1
        }
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }
}

private struct FetchOptions {
    var url: URL
    var outputURL: URL?

    init(_ arguments: [String]) throws {
        guard let rawURL = arguments.first, !rawURL.hasPrefix("--") else {
            throw CLIError("Usage: loupe fetch <url> [--output <path>]")
        }

        guard let url = URL(string: rawURL) else {
            throw CLIError("Invalid URL: \(rawURL)")
        }

        var outputURL: URL?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--output":
                let value = try Self.value(after: "--output", in: arguments, index: &index)
                outputURL = URL(fileURLWithPath: value)
            default:
                throw CLIError("Unknown fetch option: \(arguments[index])")
            }

            index += 1
        }

        self.url = url
        self.outputURL = outputURL
    }

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}

private struct LaunchOptions {
    var bundleID: String
    var device: String
    var dylibPath: String?
    var environment: [String: String]
    var shouldInject: Bool

    init(_ arguments: [String]) throws {
        var bundleID: String?
        var device = "booted"
        var dylibPath: String?
        var environment: [String: String] = [:]
        var shouldInject = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--bundle-id":
                bundleID = try Self.value(after: argument, in: arguments, index: &index)
            case "--device":
                device = try Self.value(after: argument, in: arguments, index: &index)
            case "--dylib":
                dylibPath = try Self.value(after: argument, in: arguments, index: &index)
                shouldInject = true
            case "--inject":
                shouldInject = true
            case "--env":
                let pair = try Self.value(after: argument, in: arguments, index: &index)
                let pieces = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard pieces.count == 2 else {
                    throw CLIError("--env expects KEY=VALUE")
                }
                environment[pieces[0]] = pieces[1]
            default:
                throw CLIError("Unknown launch option: \(argument)")
            }

            index += 1
        }

        guard let bundleID else {
            throw CLIError("launch requires --bundle-id <id>")
        }

        self.bundleID = bundleID
        self.device = device
        self.dylibPath = dylibPath
        self.environment = environment
        self.shouldInject = shouldInject
    }

    private static func value(
        after option: String,
        in arguments: [String],
        index: inout Int
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }
}

private protocol ActionDispatchOptions {
    var backend: String { get }
    var udid: String { get }
    var endPoint: LoupePoint? { get }
    var duration: Double? { get }
    var text: String? { get }
    var startSpread: Double? { get }
    var endSpread: Double? { get }
    var traceDirectory: URL? { get }
}

private extension ActionDispatchOptions {
    func requireEndPoint(command: String) throws -> LoupePoint {
        guard let endPoint else {
            throw CLIError("\(command) requires --to x,y")
        }
        return endPoint
    }
}

private struct ActionOptions: ActionDispatchOptions {
    var command: String
    var host: URL
    var backend: String
    var udid: String
    var selector: LoupeSelector?
    var point: LoupePoint?
    var endPoint: LoupePoint?
    var screen: LoupeSize
    var duration: Double?
    var text: String?
    var startSpread: Double?
    var endSpread: Double?
    var traceDirectory: URL?

    init(command: String, arguments: [String]) throws {
        self.command = command
        host = URL(string: "http://127.0.0.1:8765")!
        backend = "auto"
        udid = "booted"
        screen = LoupeSize(width: 0, height: 0)

        var selector: LoupeSelector?
        var point: LoupePoint?
        var endPoint: LoupePoint?
        var duration: Double?
        var text: String?
        var startSpread: Double?
        var endSpread: Double?
        var traceDirectory: URL?
        var screenWidth: Double?
        var screenHeight: Double?
        var hasX = false
        var hasY = false
        var index = 0

        if command == "type", let first = arguments.first, !first.hasPrefix("--") {
            text = first
            index = 1
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--host":
                host = try Self.url(after: argument, in: arguments, index: &index)
            case "--backend":
                backend = try Self.value(after: argument, in: arguments, index: &index)
            case "--udid", "--device":
                udid = try Self.value(after: argument, in: arguments, index: &index)
            case "--test-id":
                selector = .testID(try Self.value(after: argument, in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: argument, in: arguments, index: &index))
            case "--text":
                let value = try Self.value(after: argument, in: arguments, index: &index)
                if command == "type" {
                    text = value
                } else {
                    selector = .text(value, exact: false)
                }
            case "--exact-text":
                selector = .text(try Self.value(after: argument, in: arguments, index: &index), exact: true)
            case "--x":
                let x = try Self.double(after: argument, in: arguments, index: &index)
                let y = point?.y ?? 0
                point = LoupePoint(x: x, y: y)
                hasX = true
            case "--y":
                let y = try Self.double(after: argument, in: arguments, index: &index)
                let x = point?.x ?? 0
                point = LoupePoint(x: x, y: y)
                hasY = true
            case "--from", "--center":
                point = try Self.point(after: argument, in: arguments, index: &index)
            case "--to":
                endPoint = try Self.point(after: argument, in: arguments, index: &index)
            case "--width":
                screenWidth = try Self.double(after: argument, in: arguments, index: &index)
            case "--height":
                screenHeight = try Self.double(after: argument, in: arguments, index: &index)
            case "--duration":
                duration = try Self.double(after: argument, in: arguments, index: &index)
            case "--start-spread":
                startSpread = try Self.double(after: argument, in: arguments, index: &index)
            case "--end-spread":
                endSpread = try Self.double(after: argument, in: arguments, index: &index)
            case "--trace-dir":
                traceDirectory = URL(fileURLWithPath: try Self.value(after: argument, in: arguments, index: &index))
            default:
                throw CLIError("Unknown \(command) option: \(argument)")
            }
            index += 1
        }

        if let screenWidth, let screenHeight {
            screen = LoupeSize(width: screenWidth, height: screenHeight)
        }

        if command == "type", text == nil {
            throw CLIError("type requires text")
        }

        if hasX != hasY {
            throw CLIError("--x and --y must be provided together")
        }

        self.selector = selector
        self.point = point
        self.endPoint = endPoint
        self.duration = duration
        self.text = text
        self.startSpread = startSpread
        self.endSpread = endSpread
        self.traceDirectory = traceDirectory
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }

    private static func point(after option: String, in arguments: [String], index: inout Int) throws -> LoupePoint {
        let raw = try value(after: option, in: arguments, index: &index)
        let parts = raw.split(separator: ",").map(String.init)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            throw CLIError("\(option) expects x,y")
        }
        return LoupePoint(x: x, y: y)
    }

    private static func url(after option: String, in arguments: [String], index: inout Int) throws -> URL {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let url = URL(string: raw) else {
            throw CLIError("Invalid URL for \(option): \(raw)")
        }
        return url
    }
}

private struct ReplayActionOptions: ActionDispatchOptions {
    var backend: String
    var udid: String
    var endPoint: LoupePoint?
    var duration: Double?
    var text: String?
    var startSpread: Double?
    var endSpread: Double?
    var traceDirectory: URL?
}

private struct ReplayAction {
    var command: String
    var target: ActionTarget
    var endPoint: LoupePoint?
    var startSpread: Double?
    var endSpread: Double?
}

private struct ReplayOptions {
    var recordingURL: URL
    var screen: LoupeSize
    var actionOptions: ReplayActionOptions

    init(_ arguments: [String]) throws {
        guard let path = arguments.first, !path.hasPrefix("--") else {
            throw CLIError("Usage: loupe replay <recording.json> --udid <sim> --width <points> --height <points> [--backend auto|axe]")
        }

        recordingURL = URL(fileURLWithPath: path)
        var backend = "auto"
        var udid = "booted"
        var width: Double?
        var height: Double?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--backend":
                backend = try Self.value(after: "--backend", in: arguments, index: &index)
            case "--udid", "--device":
                udid = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--width":
                width = try Self.double(after: "--width", in: arguments, index: &index)
            case "--height":
                height = try Self.double(after: "--height", in: arguments, index: &index)
            default:
                throw CLIError("Unknown replay option: \(arguments[index])")
            }
            index += 1
        }

        guard let width, let height else {
            throw CLIError("replay requires --width and --height in device points")
        }

        screen = LoupeSize(width: width, height: height)
        actionOptions = ReplayActionOptions(
            backend: backend,
            udid: udid,
            endPoint: nil,
            duration: nil,
            text: nil,
            startSpread: nil,
            endSpread: nil,
            traceDirectory: nil
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

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }
}

private struct RuntimeFetchOptions {
    var host: URL
    var outputURL: URL?

    init(_ arguments: [String], usage: String) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        var outputURL: URL?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--host":
                let raw = try Self.value(after: "--host", in: arguments, index: &index)
                guard let url = URL(string: raw) else {
                    throw CLIError("Invalid --host URL: \(raw)")
                }
                host = url
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--help", "-h":
                throw CLIError(usage)
            default:
                throw CLIError("Unknown runtime option: \(arguments[index])")
            }
            index += 1
        }
        self.outputURL = outputURL
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

private struct WaitForVisibleOptions {
    var host: URL
    var selector: LoupeSelector
    var timeout: TimeInterval
    var interval: TimeInterval

    init(_ arguments: [String]) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        timeout = 10
        interval = 0.25

        var selector: LoupeSelector?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--host":
                let raw = try Self.value(after: "--host", in: arguments, index: &index)
                guard let url = URL(string: raw) else {
                    throw CLIError("Invalid --host URL: \(raw)")
                }
                host = url
            case "--test-id":
                selector = .testID(try Self.value(after: "--test-id", in: arguments, index: &index))
            case "--text":
                selector = .text(try Self.value(after: "--text", in: arguments, index: &index), exact: false)
            case "--exact-text":
                selector = .text(try Self.value(after: "--exact-text", in: arguments, index: &index), exact: true)
            case "--role":
                selector = .role(try Self.value(after: "--role", in: arguments, index: &index))
            case "--ref":
                selector = .ref(try Self.value(after: "--ref", in: arguments, index: &index))
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--interval":
                interval = try Self.double(after: "--interval", in: arguments, index: &index)
            default:
                throw CLIError("Unknown wait-for-visible option: \(arguments[index])")
            }
            index += 1
        }

        guard let selector else {
            throw CLIError("wait-for-visible requires --test-id, --text, --role, or --ref")
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        guard interval > 0 else {
            throw CLIError("--interval must be greater than 0")
        }

        self.selector = selector
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }
}

private struct ScreenshotOptions {
    var udid: String
    var outputPath: String

    init(_ arguments: [String]) throws {
        var udid = "booted"
        var outputPath: String?
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--udid", "--device":
                udid = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--output":
                outputPath = try Self.value(after: "--output", in: arguments, index: &index)
            default:
                throw CLIError("Unknown screenshot option: \(arguments[index])")
            }
            index += 1
        }
        guard let outputPath else {
            throw CLIError("screenshot requires --output <path>")
        }
        self.udid = udid
        self.outputPath = outputPath
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

private struct ActionBackend {
    var name: String
    var path: String
}

private struct LoupeCLIActionTrace: Codable {
    var command: String
    var phase: String
    var host: String
    var backend: String
    var udid: String
    var selector: String?
    var point: LoupePoint?
    var endPoint: LoupePoint?
    var duration: Double?
    var text: String?
    var resolvedPoint: LoupePoint?
    var resolvedScreen: LoupeSize?
    var resolvedSource: String?
    var resolvedTarget: ActionTargetTrace?
    var recordedAt: Date
}

private enum ActionTargetSource: CustomStringConvertible {
    case accessibility(ref: String, sourceRef: String)
    case view(ref: String)
    case coordinates
    case keyboardFocus

    var description: String {
        switch self {
        case let .accessibility(ref, sourceRef):
            return "accessibility:\(ref):source:\(sourceRef)"
        case let .view(ref):
            return "view:\(ref)"
        case .coordinates:
            return "coordinates"
        case .keyboardFocus:
            return "keyboardFocus"
        }
    }
}

private struct ActionTarget {
    var point: LoupePoint
    var screen: LoupeSize
    var screenScale: Double
    var source: ActionTargetSource
    var match: ActionTargetMatch? = nil
}

private enum ActionTargetMatch {
    case accessibility(LoupeAccessibilityQueryResult)
    case view(LoupeQueryResult)

    var trace: ActionTargetTrace {
        switch self {
        case let .accessibility(result):
            return ActionTargetTrace(
                tree: "accessibility",
                ref: result.ref,
                sourceRef: result.sourceRef,
                typeName: nil,
                role: result.role,
                testID: result.testID,
                label: nil,
                value: nil,
                text: result.text,
                frame: result.frame,
                activationPoint: result.activationPoint,
                isVisible: result.isVisible,
                isEnabled: result.isEnabled,
                isInteractive: result.isInteractive
            )
        case let .view(result):
            return ActionTargetTrace(
                tree: "view",
                ref: result.ref,
                sourceRef: nil,
                typeName: nil,
                role: result.role,
                testID: result.testID,
                label: nil,
                value: nil,
                text: result.text,
                frame: result.frame,
                activationPoint: nil,
                isVisible: result.isVisible,
                isEnabled: result.isEnabled,
                isInteractive: result.isInteractive
            )
        }
    }
}

private struct ActionTargetTrace: Codable {
    var tree: String
    var ref: String
    var sourceRef: String?
    var typeName: String?
    var role: String?
    var testID: String?
    var label: String?
    var value: String?
    var text: String?
    var frame: LoupeRect?
    var activationPoint: LoupePoint?
    var isVisible: Bool
    var isEnabled: Bool
    var isInteractive: Bool
}

private struct CLIError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
