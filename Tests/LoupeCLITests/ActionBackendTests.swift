@testable import LoupeCLI
@testable import LoupeCLIModel
import Foundation
import LoupeCore
import Testing

struct ActionBackendTests {
    @Test func autoTapUsesRuntimeForExplicitNonSimulatorHost() {
        let identity = LoupeRuntimeIdentity(
            platform: "macOS",
            processIdentifier: 1234
        )

        let backend = LoupeCLI.resolvedActionBackend(
            requested: "auto",
            command: "tap",
            hostWasExplicit: true,
            runtimeIdentity: identity
        )

        #expect(backend == "runtime")
    }

    @Test func autoTapKeepsNativePathForSimulatorRuntime() {
        let identity = LoupeRuntimeIdentity(
            platform: "iOS",
            processIdentifier: 1234,
            simulatorUDID: "SIM-1",
            simulatorName: "iPhone 17 Pro"
        )

        let backend = LoupeCLI.resolvedActionBackend(
            requested: "auto",
            command: "tap",
            hostWasExplicit: true,
            runtimeIdentity: identity
        )

        #expect(backend == "auto")
    }

    @Test func explicitBackendAndNonTapCommandsAreNotRewritten() {
        let identity = LoupeRuntimeIdentity(
            platform: "macOS",
            processIdentifier: 1234
        )

        #expect(
            LoupeCLI.resolvedActionBackend(
                requested: "native",
                command: "tap",
                hostWasExplicit: true,
                runtimeIdentity: identity
            ) == "native"
        )
        #expect(
            LoupeCLI.resolvedActionBackend(
                requested: "auto",
                command: "swipe",
                hostWasExplicit: true,
                runtimeIdentity: identity
            ) == "auto"
        )
    }

    @Test func actionResolutionPrefersPlatformBackedViewOverSyntheticProbe() {
        let snapshot = openImmersiveDuplicateProbeSnapshot()
        let matches = [
            LoupeQueryResult(node: snapshot.nodes["synthetic"]!),
            LoupeQueryResult(node: snapshot.nodes["backing"]!),
        ]

        let filtered = LoupeCLI.preferPlatformBackedActionMatches(matches, snapshot: snapshot)

        #expect(filtered.map(\.ref) == ["backing"])
    }

    @Test func actionResolutionPrefersPlatformBackedAccessibilityNodeOverSyntheticProbe() {
        let snapshot = openImmersiveDuplicateProbeSnapshot()
        let matches = [
            LoupeAccessibilityQueryResult(
                node: LoupeAccessibilityNode(
                    ref: "ax-synthetic",
                    sourceRef: "synthetic",
                    role: "button",
                    label: "Enter Stream URL",
                    testID: "openimmersive.enterStreamURL",
                    traits: ["button"],
                    frame: snapshot.nodes["synthetic"]!.frame,
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                )
            ),
            LoupeAccessibilityQueryResult(
                node: LoupeAccessibilityNode(
                    ref: "ax-backing",
                    sourceRef: "backing",
                    role: "button",
                    label: "Enter Stream URL",
                    testID: "openimmersive.enterStreamURL",
                    traits: ["button"],
                    frame: snapshot.nodes["backing"]!.frame,
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                )
            ),
        ]

        let filtered = LoupeCLI.preferPlatformBackedActionMatches(matches, snapshot: snapshot)

        #expect(filtered.map(\.sourceRef) == ["backing"])
    }

    @Test func cachedAliasTargetKeepsAccessibilityTraceProvenance() throws {
        let entry = ActionTargetAliasEntry(
            index: 2,
            ref: "ax-n42",
            sourceRef: "n42",
            role: "button",
            text: "Pay",
            testID: "checkout.pay",
            frame: LoupeRect(x: 20, y: 100, width: 80, height: 44),
            activationPoint: LoupePoint(x: 60, y: 122),
            point: LoupePoint(x: 60, y: 122),
            isVisible: true,
            isEnabled: true,
            isInteractive: true
        )
        let cache = ActionTargetAliasCache(
            launchID: "launch-1",
            deviceIdentifier: "SIM-1",
            bundleIdentifier: "com.example.checkout",
            host: "http://127.0.0.1:8765",
            snapshotID: "snapshot-1",
            screen: LoupeScreen(size: LoupeSize(width: 400, height: 800), scale: 3),
            targets: [entry]
        )

        let target = try LoupeCLI.actionTarget(alias: 2, cache: cache)

        #expect(target.source.description == "accessibility:ax-n42:source:n42")
        #expect(target.match?.trace.tree == "accessibility")
        #expect(target.match?.trace.testID == "checkout.pay")
        #expect(target.point == LoupePoint(x: 60, y: 122))
    }

    private func openImmersiveDuplicateProbeSnapshot() -> LoupeSnapshot {
        LoupeSnapshot(
            id: "openimmersive",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 800, height: 850), scale: 1),
            rootRefs: ["backing", "synthetic"],
            nodes: [
                "synthetic": LoupeNode(
                    ref: "synthetic",
                    parentRef: nil,
                    kind: .view,
                    typeName: "LoupeRegisteredProbe",
                    role: "button",
                    testID: "openimmersive.enterStreamURL",
                    text: "Enter Stream URL",
                    frame: LoupeRect(x: 725.5, y: 526, width: 207.5, height: 44),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    custom: [
                        "synthetic": .bool(true),
                        "observationBackend": .string("registered-probes"),
                    ]
                ),
                "backing": LoupeNode(
                    ref: "backing",
                    parentRef: nil,
                    kind: .view,
                    typeName: "LoupeFallbackFrameView",
                    role: "button",
                    testID: "openimmersive.enterStreamURL",
                    text: "Enter Stream URL",
                    frame: LoupeRect(x: 485.5, y: 591, width: 207.5, height: 44),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                ),
            ]
        )
    }
}
