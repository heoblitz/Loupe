import Foundation
import Testing
import LoupeCore
@testable import LoupeKit

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
import SwiftUI
#endif

#if canImport(UIKit) || canImport(AppKit)
@Suite struct LoupeRuntimeBridgeTests {
    @MainActor
    @Test func runtimeLogBridgeKeepsMostRecentFiveHundredEntries() {
        let runtime = LoupeRuntime()
        runtime.activateBridge()

        for index in 0...500 {
            NotificationCenter.default.post(
                name: .loupeLog,
                object: nil,
                userInfo: [
                    "level": "debug",
                    "message": "platform-log-\(index)",
                    "metadata": ["index": index]
                ]
            )
        }

        let logs = runtime.runtimeLogs()

        #expect(logs.count == 500)
        #expect(!logs.contains { $0.message == "platform-log-0" })
        #expect(logs.contains { log in
            log.level == "debug"
                && log.message == "platform-log-500"
                && log.metadata["index"] == .int(500)
        })
    }

    @MainActor
    @Test func runtimeReferenceBridgeRecordsAppAuthoredEvidence() {
        let runtime = LoupeRuntime()
        runtime.activateBridge()

        NotificationCenter.default.post(
            name: .loupeReference,
            object: nil,
            userInfo: [
                "owner": "PlatformFixtureController",
                "target": "DeviceActuationService",
                "kind": "strong",
                "label": "test fixture reference",
                "metadata": ["screen": "platform"]
            ]
        )

        #expect(runtime.runtimeReferenceEvidence().contains { evidence in
            evidence.owner == "PlatformFixtureController"
                && evidence.target == "DeviceActuationService"
                && evidence.kind == "strong"
                && evidence.label == "test fixture reference"
                && evidence.metadata["screen"] == .string("platform")
        })
    }

    @MainActor
    @Test func runtimeRegisteredProbesKeepFrameAndMetadataForProbeSnapshots() {
        let runtime = LoupeRuntime()
        let id = "platform.registered.probe"

        runtime.registerProbe(
            id: id,
            label: "Registered probe",
            role: "button",
            frame: LoupeRect(x: 4, y: 8, width: 44, height: 22),
            isInteractive: true,
            metadata: ["screen": .string("platform")]
        )

        let probe = runtime.registeredProbes().first { $0.id == id }

        #expect(probe?.label == "Registered probe")
        #expect(probe?.role == "button")
        #expect(probe?.frame == LoupeRect(x: 4, y: 8, width: 44, height: 22))
        #expect(probe?.isInteractive == true)
        #expect(probe?.metadata["screen"] == .string("platform"))
        #expect(probe?.metadata["loupe.probe"] == .bool(true))
    }

    @MainActor
    @Test func runtimeProbeBridgeRegistersAndRemovesProbeWithoutImportingLoupeAPI() {
        let runtime = LoupeRuntime()
        runtime.activateBridge()
        let id = "platform.notification.probe"

        NotificationCenter.default.post(
            name: .loupeProbe,
            object: nil,
            userInfo: [
                "id": id,
                "label": "Notification probe",
                "role": "button",
                "frame": [
                    "x": 11,
                    "y": 22,
                    "width": 33,
                    "height": 44,
                ],
                "isInteractive": true,
                "metadata": ["screen": "platform"],
            ]
        )

        let probe = runtime.registeredProbes().first { $0.id == id }
        #expect(probe?.label == "Notification probe")
        #expect(probe?.role == "button")
        #expect(probe?.frame == LoupeRect(x: 11, y: 22, width: 33, height: 44))
        #expect(probe?.isInteractive == true)
        #expect(probe?.metadata["screen"] == .string("platform"))
        #expect(probe?.metadata["loupe.probe"] == .bool(true))

        NotificationCenter.default.post(
            name: .loupeRemoveProbe,
            object: nil,
            userInfo: ["id": id]
        )
        #expect(runtime.registeredProbes().contains { $0.id == id } == false)
    }

    @Test func registeredProbeNodeIsQueryableInSnapshots() {
        let probe = LoupeRegisteredProbe(
            id: "platform.notification.probe",
            label: "Notification probe",
            role: "button",
            frame: LoupeRect(x: 11, y: 22, width: 33, height: 44),
            isVisible: true,
            isEnabled: true,
            isInteractive: true,
            metadata: ["loupe.probe": .bool(true)]
        )
        let root = LoupeNode(
            ref: "n1",
            parentRef: nil,
            kind: .application,
            typeName: "UIApplication",
            role: "application",
            frame: LoupeRect(x: 0, y: 0, width: 390, height: 844),
            isVisible: true,
            isEnabled: true,
            isInteractive: false,
            children: ["n2"]
        )
        let node = loupeRegisteredProbeNode(
            probe,
            ref: "n2",
            parentRef: "n1",
            runtimeMetadata: ["screen": .string("platform")]
        )
        let snapshot = LoupeSnapshot(
            id: "s1",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["n1"],
            nodes: [
                "n1": root,
                "n2": node,
            ]
        )

        #expect(LoupeSnapshotQuery.find(.testID("platform.notification.probe"), in: snapshot).map(\.ref) == ["n2"])
        #expect(LoupeSnapshotQuery.find(.role("button"), in: snapshot).map(\.ref) == ["n2"])
        #expect(node.custom["screen"] == .string("platform"))
        #expect(node.custom["synthetic"] == .bool(true))
        #expect(node.custom["observationBackend"] == .string("registered-probes"))
    }

    @Test func swiftUIPrivateReflectionExtractsMeaningfulSummary() {
        struct ProfileView {
            var enabled = true
            var mode = "Save"
        }
        final class FixtureHost: NSObject {
            let rootView = ProfileView()
        }

        let summary = loupeSwiftUIPrivateSummary(from: FixtureHost())

        #expect(summary?.rootTypeName == "ProfileView")
        #expect(summary?.properties.contains { $0.name == "enabled" && $0.value == .bool(true) } == true)
        #expect(summary?.properties.contains { $0.name == "mode" && $0.value == .string("Save") } == true)
    }

    @MainActor
    @Test func runtimeReferenceEvidenceKeepsMostRecentFiveHundredEntries() {
        let runtime = LoupeRuntime()

        for index in 0...500 {
            runtime.recordReference(
                LoupeReferenceEvidence(
                    owner: "retention-owner-\(index)",
                    target: "DeviceActuationService"
                )
            )
        }

        let refs = runtime.runtimeReferenceEvidence()

        #expect(refs.count == 500)
        #expect(!refs.contains { $0.owner == "retention-owner-0" })
        #expect(refs.contains { $0.owner == "retention-owner-500" })
    }

    @MainActor
    @Test func runtimeObjectClassesExposeObjectiveCRuntimeMetadata() throws {
        let runtime = LoupeRuntime()
        let classes = runtime.runtimeObjectClasses(matching: "NSObject", limit: 20)

        #expect(classes.evidenceKind == "objc-runtime-class-list")
        #expect(classes.totalCount >= classes.returnedCount)
        #expect(classes.classes.contains { $0.name == "NSObject" })

        let description = try runtime.runtimeObjectDescription(className: "NSObject")
        #expect(description.evidenceKind == "objc-runtime-class-description")
        #expect(description.name == "NSObject")
    }

    @MainActor
    @Test func lifetimeProbesTrackAliveAndReleasedObjects() {
        let runtime = LoupeRuntime()
        let aliveObject = NSObject()
        let aliveID = runtime.watchLifetime(aliveObject, name: "alive fixture")

        var releasedID = ""
        do {
            let releasedObject = NSObject()
            releasedID = runtime.watchLifetime(releasedObject, name: "released fixture")
        }

        let report = runtime.runtimeLifetimeProbes()
        let aliveProbe = report.probes.first { $0.id == aliveID }
        let releasedProbe = report.probes.first { $0.id == releasedID }

        #expect(report.evidenceKind == "weak-lifetime-probe")
        #expect(aliveProbe?.isAlive == true)
        #expect(releasedProbe?.isAlive == false)
    }

    @MainActor
    @Test func lifetimeProbeBridgeRecordsObjectWithoutImportingLoupeAPI() {
        let runtime = LoupeRuntime()
        runtime.activateBridge()
        let object = NSObject()

        NotificationCenter.default.post(
            name: .loupeLifetimeProbe,
            object: object,
            userInfo: [
                "name": "notification lifetime fixture",
                "expectedDeallocated": true,
                "metadata": ["screen": "platform"]
            ]
        )

        #expect(runtime.runtimeLifetimeProbes().probes.contains { probe in
            probe.name == "notification lifetime fixture"
                && probe.objectType == "NSObject"
                && probe.isAlive
                && probe.metadata["screen"] == .string("platform")
        })
    }
}
#endif

#if canImport(AppKit) && !canImport(UIKit)
// These tests create real NSWindow instances and exercise AppKit's global
// application/accessibility state. Keep them out of the default SwiftPM unit
// pass; runtime AppKit coverage lives in the CLI-driven macOS E2E harness.
@Suite(.serialized) struct LoupeAgentAppKitTests {
    @MainActor
    @Test func loupeKitSwiftUIProbeBackingViewAppearsInSnapshotWithMetadata() throws {
        guard runLiveAppKitSwiftPMTests else {
            return
        }

        let runtime = LoupeRuntime()
        let fixture = LoupeKitSwiftUIProbeBackingViewFixture()
        defer { fixture.tearDown() }

        let agent = LoupeAgent(runtime: runtime)
        let snapshot = agent.captureSnapshot()
        let probe = try #require(snapshot.nodes.values.first { $0.testID == fixture.probeTestID })

        #expect(probe.platform?.className == "NSView")
        #expect(probe.custom["loupe.probe"] == .bool(true))
        let frame = try #require(probe.frame)
        #expect(frame.width > 100)
        #expect(frame.height > 80)

        let accessibilityTree = agent.captureAccessibilityTree()
        let match = try #require(LoupeAccessibilityTreeQuery.first(.testID(fixture.probeTestID), in: accessibilityTree))
        let accessibilityNode = try #require(accessibilityTree.nodes[match.ref])

        #expect(accessibilityNode.label == "Imported LoupeKit SwiftUI probe")
        #expect(accessibilityNode.sourceRef == probe.ref)
    }

    @MainActor
    @Test func appKitSnapshotCapturesWindowTestIDMetadataAndDiagnostics() throws {
        guard runLiveAppKitSwiftPMTests else {
            return
        }

        let runtime = LoupeRuntime()
        let fixture = AppKitFixture()
        defer { fixture.tearDown() }

        runtime.activateBridge()
        NotificationCenter.default.post(
            name: .loupeViewMetadata,
            object: nil,
            userInfo: [
                "testID": fixture.buttonTestID,
                "metadata": [
                    "runtimeTag": "posted-by-test-id",
                    "priority": 7
                ]
            ]
        )

        let agent = LoupeAgent(runtime: runtime)
        let snapshot = agent.captureSnapshot()
        let appNode = try #require(snapshot.rootRefs.compactMap { snapshot.nodes[$0] }.first)
        let windowNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.windowTestID })
        let labelNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.labelTestID })
        let buttonNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.buttonTestID })
        let segmentedNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.segmentedTestID })
        let sliderNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.sliderTestID })
        let stepperNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.stepperTestID })
        let progressNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.progressTestID })
        let imageNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.imageTestID })
        let nativeAXHostNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.nativeAXHostTestID })
        let customAXTextNode = try #require(snapshot.nodes.values.first { $0.testID == fixture.customAXTextTestID })

        #expect(appNode.kind == .application)
        #expect(appNode.typeName == "NSApplication")
        #expect(windowNode.kind == .window)
        #expect(windowNode.typeName == "NSWindow")
        #expect(labelNode.typeName == "NSTextField")
        #expect(labelNode.role == "staticText")
        #expect(labelNode.isInteractive == false)
        #expect(buttonNode.typeName == "NSButton")
        #expect(buttonNode.isInteractive == true)
        #expect(buttonNode.text == "Run")
        let buttonLayout = try #require(buttonNode.platform?.layout)
        #expect(buttonLayout.hugging.horizontal > 0)
        #expect(buttonLayout.hugging.vertical > 0)
        #expect(buttonLayout.compressionResistance.horizontal > 0)
        #expect(buttonLayout.compressionResistance.vertical > 0)
        #expect(buttonNode.custom["fixture"] == .string("appkit"))
        #expect(buttonNode.custom["runtimeTag"] == .string("posted-by-test-id"))
        #expect(buttonNode.custom["priority"] == .int(7))
        #expect(segmentedNode.role == "segmentedControl")
        #expect(segmentedNode.platform?.segmentedControl?.selectedSegmentIndex == 1)
        #expect(segmentedNode.platform?.segmentedControl?.segments == ["One", "Two"])
        #expect(sliderNode.role == "slider")
        #expect(sliderNode.platform?.slider?.value == 25)
        #expect(sliderNode.platform?.slider?.minimumValue == 0)
        #expect(sliderNode.platform?.slider?.maximumValue == 50)
        #expect(stepperNode.role == "stepper")
        #expect(stepperNode.platform?.stepper?.value == 4)
        #expect(stepperNode.platform?.stepper?.stepValue == 2)
        #expect(progressNode.role == "progress")
        #expect(progressNode.platform?.progressView?.value == 0.75)
        #expect(imageNode.role == "image")
        #expect(imageNode.platform?.imageView?.imageSize == LoupeSize(width: 18, height: 18))
        #expect(customAXTextNode.typeName == "AccessibilityRoleTextView")
        #expect(customAXTextNode.role == "staticText")
        #expect(customAXTextNode.semanticText == "Custom accessible text")
        #expect(customAXTextNode.accessibility?.traits == ["staticText"])
        #expect(snapshot.nodes.values.first { $0.testID == fixture.nativeAXActionTestID } == nil)

        let accessibilityTree = agent.captureAccessibilityTree()
        let nativeAXMatch = try #require(
            LoupeAccessibilityTreeQuery.first(.testID(fixture.nativeAXActionTestID), in: accessibilityTree)
        )
        let nativeAXNode = try #require(accessibilityTree.nodes[nativeAXMatch.ref])
        #expect(nativeAXNode.ref.hasPrefix("ax-native-\(nativeAXHostNode.ref)-"))
        #expect(nativeAXNode.sourceRef == nativeAXHostNode.ref)
        #expect(nativeAXNode.parentRef == "ax-\(nativeAXHostNode.ref)")
        #expect(nativeAXNode.role == "button")
        #expect(nativeAXNode.label == "Native AX Action")
        #expect(nativeAXNode.value == "available")
        #expect(nativeAXNode.hint == "Runs the native accessibility fixture")
        #expect(nativeAXNode.testID == fixture.nativeAXActionTestID)
        #expect(nativeAXNode.activationPoint == nativeAXNode.frame?.center)
        #expect(nativeAXMatch.text == "Native AX Action")
        #expect(nativeAXMatch.isInteractive == true)

        let buttonFrame = try #require(buttonNode.frame)
        let hitTest = agent.hitTest(point: buttonFrame.center)

        #expect(hitTest.hitRef == buttonNode.ref)
        #expect(hitTest.hitTestID == fixture.buttonTestID)
        #expect(hitTest.hitTypeName == "NSButton")
        #expect(hitTest.responderChain.contains { $0.ref == buttonNode.ref })

        let responderReport = try #require(agent.responderChain(selector: .testID(fixture.buttonTestID)))

        #expect(responderReport.hitRef == buttonNode.ref)
        #expect(responderReport.hitTestID == fixture.buttonTestID)
        #expect(responderReport.responderChain.contains { $0.testID == fixture.buttonTestID })
        #expect(!agent.mutationCapabilities().isEmpty)

        let activation = try agent.activate(
            LoupeActivationRequest(
                selector: LoupeMutationSelector(kind: .testID, value: fixture.buttonTestID)
            )
        )
        #expect(activation.target.testID == fixture.buttonTestID)
        #expect(activation.before.testID == fixture.buttonTestID)
        #expect(activation.after?.testID == fixture.buttonTestID)
        #expect(activation.actionElapsed >= 0)
        #expect(fixture.activationCount == 1)

        let accessibilityActivation = try agent.activate(
            LoupeActivationRequest(
                selector: LoupeMutationSelector(kind: .testID, value: fixture.buttonTestID),
                action: .press
            )
        )
        #expect(accessibilityActivation.action == .press)
        #expect(accessibilityActivation.accessibilityTarget?.actions?.contains(.press) == true)
        #expect(fixture.activationCount == 2)

        let enabledMutation = try agent.mutate(
            LoupeMutationRequest(
                selector: LoupeMutationSelector(kind: .testID, value: fixture.buttonTestID),
                property: "enabled",
                value: .bool(false)
            )
        )
        #expect(enabledMutation.effective == .bool(false))
        #expect(enabledMutation.changed == true)

        let segmentedMutation = try agent.mutate(
            LoupeMutationRequest(
                selector: LoupeMutationSelector(kind: .testID, value: fixture.segmentedTestID),
                property: "segmentedControl.selectedSegmentIndex",
                value: .int(0)
            )
        )
        #expect(segmentedMutation.effective == .int(0))
        #expect(segmentedMutation.changed == true)

        let sliderMutation = try agent.mutate(
            LoupeMutationRequest(
                selector: LoupeMutationSelector(kind: .testID, value: fixture.sliderTestID),
                property: "slider.value",
                value: .double(30)
            )
        )
        #expect(sliderMutation.effective == .double(30))
        #expect(sliderMutation.changed == true)

        let cornerRadiusMutation = try agent.mutate(
            LoupeMutationRequest(
                selector: LoupeMutationSelector(kind: .testID, value: fixture.nativeAXHostTestID),
                property: "cornerRadius",
                value: .int(8)
            )
        )
        #expect(cornerRadiusMutation.effective == .double(8))
        #expect(cornerRadiusMutation.changed == true)
    }
}

private var runLiveAppKitSwiftPMTests: Bool {
    ProcessInfo.processInfo.environment["LOUPE_RUN_APPKIT_SWIFTPM_TESTS"] == "1"
}

@MainActor
private final class AppKitFixture {
    let windowTestID = "platform.window"
    let labelTestID = "platform.staticLabel"
    let buttonTestID = "platform.primaryButton"
    let segmentedTestID = "platform.segmented"
    let sliderTestID = "platform.slider"
    let stepperTestID = "platform.stepper"
    let progressTestID = "platform.progress"
    let imageTestID = "platform.image"
    let nativeAXHostTestID = "platform.nativeAX.host"
    let nativeAXActionTestID = "platform.nativeAX.action"
    let customAXTextTestID = "platform.customAXText"

    private let window: NSWindow
    private let nativeAXHost: NativeAccessibilityHostView
    private let activationTarget = AppKitActivationTarget()
    var activationCount: Int { activationTarget.count }

    init() {
        _ = NSApplication.shared

        window = NSWindow(
            contentRect: NSRect(x: 120, y: 140, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier(windowTestID)
        window.title = "Loupe Platform Fixture"

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 240))
        contentView.identifier = NSUserInterfaceItemIdentifier("platform.content")

        let label = NSTextField(labelWithString: "Static platform label")
        label.frame = NSRect(x: 80, y: 196, width: 180, height: 24)
        label.testID(labelTestID)

        let button = NSButton(frame: NSRect(x: 80, y: 96, width: 120, height: 44))
        button.title = "Run"
        button.bezelStyle = .rounded
        button.testID(buttonTestID)
        button.testProperty("fixture", "appkit")
        button.target = activationTarget
        button.action = #selector(AppKitActivationTarget.runButton)

        let segmented = NSSegmentedControl(frame: NSRect(x: 80, y: 52, width: 140, height: 28))
        segmented.segmentCount = 2
        segmented.setLabel("One", forSegment: 0)
        segmented.setLabel("Two", forSegment: 1)
        segmented.selectedSegment = 1
        segmented.testID(segmentedTestID)

        let slider = NSSlider(frame: NSRect(x: 80, y: 24, width: 120, height: 24))
        slider.minValue = 0
        slider.maxValue = 50
        slider.doubleValue = 25
        slider.testID(sliderTestID)

        let stepper = NSStepper(frame: NSRect(x: 220, y: 24, width: 24, height: 24))
        stepper.minValue = 0
        stepper.maxValue = 10
        stepper.increment = 2
        stepper.doubleValue = 4
        stepper.testID(stepperTestID)

        let progress = NSProgressIndicator(frame: NSRect(x: 80, y: 12, width: 120, height: 10))
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 100
        progress.doubleValue = 75
        progress.testID(progressTestID)

        let image = NSImage(size: NSSize(width: 18, height: 18))
        let imageView = NSImageView(frame: NSRect(x: 260, y: 24, width: 18, height: 18))
        imageView.image = image
        imageView.testID(imageTestID)

        nativeAXHost = NativeAccessibilityHostView(
            frame: NSRect(x: 80, y: 150, width: 180, height: 36),
            actionTestID: nativeAXActionTestID
        )
        nativeAXHost.testID(nativeAXHostTestID)
        let customAXText = AccessibilityRoleTextView(frame: NSRect(x: 210, y: 96, width: 130, height: 24))
        customAXText.testID(customAXTextTestID)

        contentView.addSubview(label)
        contentView.addSubview(button)
        contentView.addSubview(segmented)
        contentView.addSubview(slider)
        contentView.addSubview(stepper)
        contentView.addSubview(progress)
        contentView.addSubview(imageView)
        contentView.addSubview(nativeAXHost)
        contentView.addSubview(customAXText)
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        contentView.layoutSubtreeIfNeeded()
        nativeAXHost.updateAccessibilityFrame()
    }

    func tearDown() {
        nativeAXHost.tearDownAccessibilityElement()
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }
}

@MainActor
private final class LoupeKitSwiftUIProbeBackingViewFixture {
    let probeTestID = "platform.importedSwiftUI.probe"

    private let window: NSWindow

    init() {
        _ = NSApplication.shared

        window = NSWindow(
            contentRect: NSRect(x: 180, y: 180, width: 280, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("platform.importedSwiftUI.window")
        window.title = "Imported SwiftUI Probe"

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 160))
        contentView.identifier = NSUserInterfaceItemIdentifier("platform.importedSwiftUI.content")

        let probe = LoupeAppKitSwiftUIProbeBackingView.make(
            id: probeTestID,
            label: "Imported LoupeKit SwiftUI probe"
        )
        probe.frame = NSRect(x: 20, y: 20, width: 240, height: 120)
        contentView.addSubview(probe)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        contentView.layoutSubtreeIfNeeded()
    }

    func tearDown() {
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }
}

private struct ImportedLoupeSwiftUIProbeView: View {
    let probeTestID: String

    var body: some View {
        VStack {
            Text("Imported SwiftUI Probe")
                .accessibilityIdentifier("platform.importedSwiftUI.title")
        }
        .frame(width: 240, height: 120)
        .accessibilityIdentifier("platform.importedSwiftUI.root")
        .loupeProbe(probeTestID, label: "Imported LoupeKit SwiftUI probe")
    }
}

private final class AppKitActivationTarget: NSObject {
    private(set) var count = 0

    @objc func runButton() {
        count += 1
    }
}

private final class NativeAccessibilityHostView: NSView {
    private let actionElement = NSAccessibilityElement()

    init(frame: NSRect, actionTestID: String) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        actionElement.setAccessibilityIdentifier(actionTestID)
        actionElement.setAccessibilityLabel("Native AX Action")
        actionElement.setAccessibilityValue("available")
        actionElement.setAccessibilityHelp("Runs the native accessibility fixture")
        actionElement.setAccessibilityRole(.button)
        actionElement.setAccessibilityElement(true)
        actionElement.setAccessibilityEnabled(true)
        actionElement.setAccessibilityParent(self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func isAccessibilityElement() -> Bool {
        false
    }

    override func accessibilityChildren() -> [Any]? {
        [actionElement]
    }

    func updateAccessibilityFrame() {
        guard let window else {
            return
        }
        let localFrame = NSRect(x: 12, y: 8, width: 156, height: 24)
        let frameInWindow = convert(localFrame, to: nil)
        let frameInScreen = window.convertToScreen(frameInWindow)
        actionElement.setAccessibilityFrame(frameInScreen)
        actionElement.setAccessibilityActivationPoint(NSPoint(x: frameInScreen.midX, y: frameInScreen.midY))
    }

    func tearDownAccessibilityElement() {
        actionElement.setAccessibilityParent(nil)
        actionElement.setAccessibilityElement(false)
    }
}

private final class AccessibilityRoleTextView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Custom accessible text")
        setAccessibilityValue("Custom accessible text")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
