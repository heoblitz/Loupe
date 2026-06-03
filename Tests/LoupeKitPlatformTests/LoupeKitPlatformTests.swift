import Foundation
import Testing
import LoupeCore
import LoupeKit

#if canImport(AppKit) && !canImport(UIKit)
import AppKit
#endif

#if canImport(UIKit) || canImport(AppKit)
@Suite struct LoupeRuntimeBridgeTests {
    @MainActor
    @Test func runtimeLogBridgeKeepsMostRecentFiveHundredEntries() {
        let runtime = LoupeRuntime.shared
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
        let runtime = LoupeRuntime.shared
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
    @Test func runtimeReferenceEvidenceKeepsMostRecentFiveHundredEntries() {
        let runtime = LoupeRuntime.shared

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
}
#endif

#if canImport(AppKit) && !canImport(UIKit)
@Suite struct LoupeAgentAppKitTests {
    @MainActor
    @Test func appKitSnapshotCapturesWindowTestIDMetadataAndDiagnostics() throws {
        let fixture = AppKitFixture()
        defer { fixture.tearDown() }

        LoupeRuntime.shared.activateBridge()
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

        let agent = LoupeAgent()
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
        let buttonLayout = try #require(buttonNode.uiKit?.layout)
        #expect(buttonLayout.hugging.horizontal > 0)
        #expect(buttonLayout.hugging.vertical > 0)
        #expect(buttonLayout.compressionResistance.horizontal > 0)
        #expect(buttonLayout.compressionResistance.vertical > 0)
        #expect(buttonNode.custom["fixture"] == .string("appkit"))
        #expect(buttonNode.custom["runtimeTag"] == .string("posted-by-test-id"))
        #expect(buttonNode.custom["priority"] == .int(7))
        #expect(segmentedNode.role == "segmentedControl")
        #expect(segmentedNode.uiKit?.segmentedControl?.selectedSegmentIndex == 1)
        #expect(segmentedNode.uiKit?.segmentedControl?.segments == ["One", "Two"])
        #expect(sliderNode.role == "slider")
        #expect(sliderNode.uiKit?.slider?.value == 25)
        #expect(sliderNode.uiKit?.slider?.minimumValue == 0)
        #expect(sliderNode.uiKit?.slider?.maximumValue == 50)
        #expect(stepperNode.role == "stepper")
        #expect(stepperNode.uiKit?.stepper?.value == 4)
        #expect(stepperNode.uiKit?.stepper?.stepValue == 2)
        #expect(progressNode.role == "progress")
        #expect(progressNode.uiKit?.progressView?.value == 0.75)
        #expect(imageNode.role == "image")
        #expect(imageNode.uiKit?.imageView?.imageSize == LoupeSize(width: 18, height: 18))
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
    }
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

    private let window: NSWindow
    private let nativeAXHost: NativeAccessibilityHostView

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

        contentView.addSubview(label)
        contentView.addSubview(button)
        contentView.addSubview(segmented)
        contentView.addSubview(slider)
        contentView.addSubview(stepper)
        contentView.addSubview(progress)
        contentView.addSubview(imageView)
        contentView.addSubview(nativeAXHost)
        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        contentView.layoutSubtreeIfNeeded()
        nativeAXHost.updateAccessibilityFrame()
    }

    func tearDown() {
        window.orderOut(nil)
        window.close()
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
}
#endif
