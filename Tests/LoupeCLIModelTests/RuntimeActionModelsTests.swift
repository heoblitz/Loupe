import Foundation
import LoupeCore
import Testing
@testable import LoupeCLIModel

struct RuntimeActionModelsTests {
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
}
