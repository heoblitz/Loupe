import Foundation
import LoupeCore
import Testing
@testable import LoupeCLIModel

struct RuntimeActionModelsTests {
    @Test func tapParsesQuotedNumericActionTargetAlias() throws {
        let options = try ActionOptions(
            command: "tap",
            arguments: ["#2", "--udid", "SIM-1"]
        )

        #expect(options.targetAlias == 2)
        #expect(options.selector == nil)
        #expect(options.point == nil)
        #expect(options.udidWasExplicit)
    }

    @Test func tapAliasIsStrictAndCannotBeMixedWithAnotherTarget() {
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "tap", arguments: ["#0"])
        }
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "tap", arguments: ["#01"])
        }
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "tap", arguments: ["#1x"])
        }
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "tap", arguments: ["#1", "--test-id", "checkout.pay"])
        }
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "tap", arguments: ["#1", "--x", "20", "--y", "30"])
        }
    }

    @Test func actionTargetPlannerFiltersOrdersAndConservativelyDeduplicates() throws {
        let screen = LoupeScreen(size: LoupeSize(width: 400, height: 800), scale: 3)
        let snapshot = LoupeSnapshot(
            id: "snapshot",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: screen,
            rootRefs: ["a", "b", "dup", "synthetic", "backing"],
            nodes: [
                "a": viewNode(ref: "a"),
                "b": viewNode(ref: "b"),
                "dup": viewNode(ref: "dup"),
                "synthetic": viewNode(
                    ref: "synthetic",
                    custom: ["observationBackend": .string("registered-probes")]
                ),
                "backing": viewNode(ref: "backing"),
            ]
        )
        let tree = LoupeAccessibilityTree(
            snapshotID: "ax-snapshot",
            screen: screen,
            rootRefs: [],
            nodes: [
                "ax-b": axNode(ref: "ax-b", sourceRef: "b", text: "Second", frame: LoupeRect(x: 20, y: 200, width: 80, height: 44)),
                "ax-a": axNode(ref: "ax-a", sourceRef: "a", text: "First", frame: LoupeRect(x: 20, y: 100, width: 80, height: 44)),
                "ax-a-duplicate": axNode(ref: "ax-a-duplicate", sourceRef: "dup", text: "First", frame: LoupeRect(x: 20, y: 100, width: 80, height: 44)),
                "ax-hidden": axNode(ref: "ax-hidden", sourceRef: "hidden", text: "Hidden", frame: LoupeRect(x: 20, y: 10, width: 80, height: 44), visible: false),
                "ax-disabled": axNode(ref: "ax-disabled", sourceRef: "disabled", text: "Disabled", frame: LoupeRect(x: 20, y: 20, width: 80, height: 44), enabled: false),
                "ax-static": axNode(ref: "ax-static", sourceRef: "static", text: "Static", frame: LoupeRect(x: 20, y: 30, width: 80, height: 44), interactive: false),
                "ax-offscreen": axNode(ref: "ax-offscreen", sourceRef: "offscreen", text: "Offscreen", frame: LoupeRect(x: 450, y: 40, width: 80, height: 44)),
                "ax-synthetic": axNode(ref: "ax-synthetic", sourceRef: "synthetic", text: "Open", testID: "open", frame: LoupeRect(x: 20, y: 300, width: 80, height: 44)),
                "ax-backing": axNode(ref: "ax-backing", sourceRef: "backing", text: "Open", testID: "open", frame: LoupeRect(x: 220, y: 300, width: 80, height: 44)),
            ]
        )
        let identity = LoupeRuntimeIdentity(
            launchID: "launch-1",
            deviceIdentifier: "SIM-1",
            bundleIdentifier: "com.example.checkout",
            processIdentifier: 42
        )

        let cache = ActionTargetAliasPlanner.makeCache(
            snapshot: snapshot,
            accessibilityTree: tree,
            runtimeIdentity: identity,
            bundleIdentifier: "com.example.checkout",
            host: URL(string: "http://127.0.0.1:8765")!,
            cacheID: "cache-1",
            capturedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(cache.targets.map(\.index) == [1, 2, 3])
        #expect(cache.targets.map(\.text) == ["First", "Second", "Open"])
        #expect(cache.targets.last?.sourceRef == "backing")
        #expect(cache.targets[0].point == LoupePoint(x: 60, y: 122))
        #expect(cache.totalTargetCount == 3)
    }

    @Test func actionTargetTextIsCompactAndEscapesLabels() {
        let cache = aliasCache(
            targets: [
                ActionTargetAliasEntry(
                    index: 1,
                    ref: "ax-1",
                    sourceRef: "n1",
                    role: "button",
                    text: "Pay \"now\"\nplease",
                    testID: "checkout.pay",
                    frame: LoupeRect(x: 10, y: 20, width: 44, height: 44),
                    activationPoint: nil,
                    point: LoupePoint(x: 32, y: 42),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                ),
            ]
        )

        #expect(
            ActionTargetAliasText.render(cache)
                == "App: com.example.checkout\n\n#1 button \"Pay \\\"now\\\"\\nplease\""
        )
        #expect(!ActionTargetAliasText.render(cache).contains("checkout.pay"))
        #expect(!ActionTargetAliasText.render(cache).contains("frame"))
    }

    @Test func actionTargetCacheRejectsNonActionableCachedEntry() {
        let invalid = ActionTargetAliasEntry(
            index: 1,
            ref: "ax-1",
            sourceRef: "n1",
            role: "button",
            text: "Pay",
            testID: nil,
            frame: nil,
            activationPoint: nil,
            point: LoupePoint(x: 900, y: 900),
            isVisible: true,
            isEnabled: true,
            isInteractive: true
        )

        #expect(throws: CLIError.self) {
            _ = try aliasCache(targets: [invalid]).target(at: 1)
        }
    }

    @Test func actionTargetCacheRejectsRuntimeMismatches() throws {
        let cache = aliasCache(targets: [])
        let matching = LoupeRuntimeIdentity(
            launchID: "launch-1",
            deviceIdentifier: "SIM-1",
            bundleIdentifier: "com.example.checkout",
            processIdentifier: 42
        )
        try cache.validate(host: URL(string: "http://127.0.0.1:8765/")!, runtimeIdentity: matching)

        var earlierLaunch = matching
        earlierLaunch.launchID = "launch-2"
        #expect(throws: CLIError.self) {
            try cache.validate(host: URL(string: "http://127.0.0.1:8765")!, runtimeIdentity: earlierLaunch)
        }
        var otherDevice = matching
        otherDevice.deviceIdentifier = "SIM-2"
        #expect(throws: CLIError.self) {
            try cache.validate(host: URL(string: "http://127.0.0.1:8765")!, runtimeIdentity: otherDevice)
        }
        var otherApp = matching
        otherApp.bundleIdentifier = "com.example.other"
        #expect(throws: CLIError.self) {
            try cache.validate(host: URL(string: "http://127.0.0.1:8765")!, runtimeIdentity: otherApp)
        }
        #expect(throws: CLIError.self) {
            try cache.validate(host: URL(string: "http://127.0.0.1:9999")!, runtimeIdentity: matching)
        }
        var futureSchema = cache
        futureSchema.schemaVersion += 1
        #expect(throws: CLIError.self) {
            try futureSchema.validate(host: URL(string: "http://127.0.0.1:8765")!, runtimeIdentity: matching)
        }
    }

    @Test func actionTargetPlannerBoundsLightweightOutput() {
        let screen = LoupeScreen(size: LoupeSize(width: 400, height: 800), scale: 3)
        var viewNodes: [String: LoupeNode] = [:]
        var accessibilityNodes: [String: LoupeAccessibilityNode] = [:]
        for index in 0..<105 {
            let sourceRef = "n\(index)"
            viewNodes[sourceRef] = viewNode(ref: sourceRef)
            accessibilityNodes["ax-\(sourceRef)"] = axNode(
                ref: "ax-\(sourceRef)",
                sourceRef: sourceRef,
                text: "Target \(index)",
                frame: LoupeRect(x: Double(index % 10) * 30, y: Double(index / 10) * 50, width: 20, height: 20)
            )
        }
        let snapshot = LoupeSnapshot(
            id: "snapshot",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: screen,
            rootRefs: Array(viewNodes.keys),
            nodes: viewNodes
        )
        let tree = LoupeAccessibilityTree(
            snapshotID: "ax-snapshot",
            screen: screen,
            rootRefs: Array(accessibilityNodes.keys),
            nodes: accessibilityNodes
        )
        let cache = ActionTargetAliasPlanner.makeCache(
            snapshot: snapshot,
            accessibilityTree: tree,
            runtimeIdentity: LoupeRuntimeIdentity(
                launchID: "launch-1",
                deviceIdentifier: "SIM-1",
                bundleIdentifier: "com.example.checkout",
                processIdentifier: 42
            ),
            bundleIdentifier: "com.example.checkout",
            host: URL(string: "http://127.0.0.1:8765")!
        )

        #expect(cache.totalTargetCount == 105)
        #expect(cache.targets.count == ActionTargetAliasPlanner.maximumTargetCount)
        #expect(cache.targets.last?.index == ActionTargetAliasPlanner.maximumTargetCount)
    }

    @Test func actionTargetCacheIsAtomicallyReplacedAndConsumedOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-action-target-cache-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ActionTargetAliasCacheStore(url: directory.appendingPathComponent("current.json"))
        let first = aliasCache(cacheID: "first", targets: [])
        let second = aliasCache(cacheID: "second", targets: [])

        try store.store(first)
        try store.store(second)
        #expect(try store.load().cacheID == "second")

        try store.consume(cacheID: "first")
        #expect(try store.load().cacheID == "second")
        try store.consume(cacheID: "second")
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }

    @Test func coordinateSwipeKeepsPointsAndRequiresRuntimeScreenWhenNoExplicitSize() throws {
        let options = try ActionOptions(
            command: "swipe",
            arguments: [
                "--host", "http://127.0.0.1:9736",
                "--from", "201,735",
                "--to", "201,300",
                "--duration", "0.5",
                "--trace-dir", "/tmp/loupe-scroll-trace",
            ]
        )

        #expect(options.host.absoluteString == "http://127.0.0.1:9736")
        #expect(options.hostWasExplicit)
        #expect(options.point == LoupePoint(x: 201, y: 735))
        #expect(try options.requireEndPoint(command: "swipe") == LoupePoint(x: 201, y: 300))
        #expect(options.duration == 0.5)
        #expect(options.screen == LoupeSize(width: 0, height: 0))
        #expect(options.traceDirectory?.path == "/tmp/loupe-scroll-trace")
    }

    @Test func swipeCanDisableScrollVerification() throws {
        let options = try ActionOptions(
            command: "swipe",
            arguments: [
                "--from", "201,735",
                "--to", "201,300",
                "--no-verify-scroll",
            ]
        )

        #expect(options.verifyScroll == false)
    }

    @Test func pressParsesCanonicalRemoteButton() throws {
        let options = try ActionOptions(
            command: "press",
            arguments: [
                "play-pause",
                "--host", "http://127.0.0.1:9736",
                "--udid", "SIM-1",
                "--trace-dir", "/tmp/loupe-press-trace",
                "--expect-visible", "tv.example.status",
            ]
        )

        #expect(options.press == "playPause")
        #expect(options.host.absoluteString == "http://127.0.0.1:9736")
        #expect(options.udid == "SIM-1")
        #expect(options.traceDirectory?.path == "/tmp/loupe-press-trace")
        #expect(options.expectVisibleTestID == "tv.example.status")
    }

    @Test func pressRejectsMissingOrTargetedInput() throws {
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "press", arguments: ["--udid", "SIM-1"])
        }
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "press", arguments: ["home", "--udid", "SIM-1"])
        }
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "press", arguments: ["select", "--test-id", "tv.example.refresh"])
        }
        #expect(throws: CLIError.self) {
            _ = try ActionOptions(command: "press", arguments: ["select", "--x", "10", "--y", "10"])
        }
    }

    @Test func refTapCanResolveAgainstProvidedSnapshot() throws {
        let options = try ActionOptions(
            command: "tap",
            arguments: [
                "--host", "http://127.0.0.1:9736",
                "--udid", "SIM-1",
                "--snapshot", "/tmp/loupe-snapshot.json",
                "--ref", "n21",
            ]
        )

        #expect(options.host.absoluteString == "http://127.0.0.1:9736")
        #expect(options.udid == "SIM-1")
        #expect(options.snapshotURL?.path == "/tmp/loupe-snapshot.json")
        #expect(options.selector == .ref("n21"))
    }

    @Test func actionScreenResolverFallsBackToSnapshotScreenForCoordinateGestures() {
        let fallback = LoupeScreen(size: LoupeSize(width: 402, height: 874), scale: 3)

        let resolved = ActionScreenResolver.resolve(
            explicit: LoupeSize(width: 0, height: 0),
            fallback: fallback
        )

        #expect(resolved.size == LoupeSize(width: 402, height: 874))
        #expect(resolved.scale == 3)
    }

    @Test func actionScreenResolverKeepsExplicitScreenForOfflineCoordinateTap() {
        let fallback = LoupeScreen(size: LoupeSize(width: 402, height: 874), scale: 3)

        let resolved = ActionScreenResolver.resolve(
            explicit: LoupeSize(width: 390, height: 844),
            fallback: fallback
        )

        #expect(resolved.size == LoupeSize(width: 390, height: 844))
        #expect(resolved.scale == 1)
    }

    @Test func accessibilityTargetTracePreservesSourceRefAndActivationPoint() {
        let node = LoupeAccessibilityNode(
            ref: "ax-n423",
            sourceRef: "n423",
            role: "button",
            label: "Card grabber",
            testID: "example.bottomSheet.grabber",
            frame: LoupeRect(x: 163, y: 526, width: 76, height: 44),
            activationPoint: LoupePoint(x: 201, y: 548),
            isVisible: true,
            isEnabled: true,
            isInteractive: true
        )
        let result = LoupeAccessibilityQueryResult(node: node)

        let trace = ActionTargetMatch.accessibility(result).trace

        #expect(trace.tree == "accessibility")
        #expect(trace.ref == "ax-n423")
        #expect(trace.sourceRef == "n423")
        #expect(trace.role == "button")
        #expect(trace.testID == "example.bottomSheet.grabber")
        #expect(trace.activationPoint == LoupePoint(x: 201, y: 548))
        #expect(trace.isInteractive)
    }

    @Test func actionTraceEncodesResolvedCoordinateScreen() throws {
        let trace = LoupeCLIActionTrace(
            command: "swipe",
            phase: "target",
            host: "http://127.0.0.1:9736",
            backend: "auto",
            udid: "SIM-1",
            selector: nil,
            point: LoupePoint(x: 201, y: 735),
            endPoint: LoupePoint(x: 201, y: 300),
            duration: 0.5,
            text: nil,
            press: nil,
            resolvedPoint: LoupePoint(x: 201, y: 735),
            resolvedScreen: LoupeSize(width: 402, height: 874),
            coordinateUnit: "points",
            resolvedScreenScale: 3,
            resolvedSource: ActionTargetSource.coordinates.description,
            resolvedTarget: nil,
            recordedAt: Date(timeIntervalSince1970: 0)
        )

        let data = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(LoupeCLIActionTrace.self, from: data)

        #expect(decoded.command == "swipe")
        #expect(decoded.resolvedScreen == LoupeSize(width: 402, height: 874))
        #expect(decoded.coordinateUnit == "points")
        #expect(decoded.resolvedScreenScale == 3)
        #expect(decoded.resolvedSource == "coordinates")
        #expect(decoded.endPoint == LoupePoint(x: 201, y: 300))
    }

    @Test func actionTraceEncodesPressButton() throws {
        let trace = LoupeCLIActionTrace(
            command: "press",
            phase: "target",
            host: "http://127.0.0.1:9736",
            backend: "auto",
            udid: "SIM-1",
            selector: nil,
            point: nil,
            endPoint: nil,
            duration: nil,
            text: nil,
            press: "select",
            resolvedPoint: LoupePoint(x: 0, y: 0),
            resolvedScreen: LoupeSize(width: 1920, height: 1080),
            resolvedSource: ActionTargetSource.remotePress(button: "select").description,
            resolvedTarget: nil,
            recordedAt: Date(timeIntervalSince1970: 0)
        )

        let data = try JSONEncoder().encode(trace)
        let decoded = try JSONDecoder().decode(LoupeCLIActionTrace.self, from: data)

        #expect(decoded.command == "press")
        #expect(decoded.press == "select")
        #expect(decoded.resolvedSource == "remotePress:select")
        #expect(decoded.resolvedScreen == LoupeSize(width: 1920, height: 1080))
    }

    @Test func actionTraceTextRedactsTypedInput() {
        #expect(ActionTraceText.recordable(command: "type", text: "hunter2") == "<redacted>")
        #expect(ActionTraceText.recordable(command: "type", text: nil) == nil)
        #expect(ActionTraceText.recordable(command: "swipe", text: "metadata") == "metadata")
    }

    private func aliasCache(
        cacheID: String = "cache-1",
        targets: [ActionTargetAliasEntry]
    ) -> ActionTargetAliasCache {
        ActionTargetAliasCache(
            cacheID: cacheID,
            capturedAt: Date(timeIntervalSince1970: 0),
            launchID: "launch-1",
            deviceIdentifier: "SIM-1",
            bundleIdentifier: "com.example.checkout",
            host: "http://127.0.0.1:8765",
            snapshotID: "snapshot-1",
            screen: LoupeScreen(size: LoupeSize(width: 400, height: 800), scale: 3),
            targets: targets
        )
    }

    private func axNode(
        ref: String,
        sourceRef: String,
        text: String,
        testID: String? = nil,
        frame: LoupeRect,
        visible: Bool = true,
        enabled: Bool = true,
        interactive: Bool = true
    ) -> LoupeAccessibilityNode {
        LoupeAccessibilityNode(
            ref: ref,
            sourceRef: sourceRef,
            role: "button",
            label: text,
            testID: testID,
            frame: frame,
            isVisible: visible,
            isEnabled: enabled,
            isInteractive: interactive
        )
    }

    private func viewNode(
        ref: String,
        custom: [String: LoupeMetadataValue] = [:]
    ) -> LoupeNode {
        LoupeNode(
            ref: ref,
            parentRef: nil,
            kind: .view,
            typeName: "UIView",
            frame: LoupeRect(x: 0, y: 0, width: 1, height: 1),
            isVisible: true,
            isEnabled: true,
            isInteractive: true,
            custom: custom
        )
    }
}
