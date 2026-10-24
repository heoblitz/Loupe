import Foundation
import LoupeCore
import Testing
@testable import LoupeCLI

struct TreeRenderingTests {
    @Test func viewTreeTraversesHiddenStructuralContainers() {
        let snapshot = LoupeSnapshot(
            id: "tree-hidden-container",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 320, height: 640), scale: 2),
            rootRefs: ["app"],
            nodes: [
                "app": LoupeNode(
                    ref: "app",
                    parentRef: nil,
                    kind: .application,
                    typeName: "UIApplication",
                    frame: LoupeRect(x: 0, y: 0, width: 320, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["scene"]
                ),
                "scene": LoupeNode(
                    ref: "scene",
                    parentRef: "app",
                    kind: .scene,
                    typeName: "UIWindowScene",
                    isVisible: false,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["window"]
                ),
                "window": LoupeNode(
                    ref: "window",
                    parentRef: "scene",
                    kind: .window,
                    typeName: "UIWindow",
                    frame: LoupeRect(x: 0, y: 0, width: 320, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    children: ["label"]
                ),
                "label": LoupeNode(
                    ref: "label",
                    parentRef: "window",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    text: "Account",
                    frame: LoupeRect(x: 20, y: 40, width: 90, height: 22),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )

        let output = LoupeCLI.renderViewTree(
            snapshot,
            selector: nil,
            depth: 2,
            includeHidden: false
        )

        #expect(output.contains("app UIApplication"))
        #expect(!output.contains("scene UIWindowScene"))
        #expect(output.contains("  window UIWindow"))
        #expect(output.contains("    label UILabel role=staticText text=\"Account\""))
    }

    @Test func accessibilityTreeCanRenderOffscreenProbeEvidenceWithoutCoveredNodes() {
        let snapshot = LoupeSnapshot(
            id: "tree-offscreen-accessibility",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 320, height: 640), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 320, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["probe"]
                ),
                "probe": LoupeNode(
                    ref: "probe",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIView",
                    role: "staticText",
                    testID: "example.offscreen.probe",
                    label: "Offscreen probe",
                    frame: LoupeRect(x: 20, y: 700, width: 180, height: 40),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    accessibility: LoupeAccessibility(
                        identifier: "example.offscreen.probe",
                        label: "Offscreen probe",
                        isElement: true
                    )
                ),
            ]
        )

        let surfaceTree = LoupeAccessibilityTree.build(from: snapshot, visibilityMode: .surface)
        let occlusionTree = LoupeAccessibilityTree.build(from: snapshot, visibilityMode: .occlusion)

        #expect(surfaceTree.nodes.values.allSatisfy { $0.testID != "example.offscreen.probe" })
        #expect(occlusionTree.nodes.values.contains { $0.testID == "example.offscreen.probe" })
    }

    @Test func viewTreeMarksSwiftUIHostSummary() {
        let snapshot = LoupeSnapshot(
            id: "tree-swiftui-private",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 320, height: 640), scale: 2),
            rootRefs: ["host"],
            nodes: [
                "host": LoupeNode(
                    ref: "host",
                    parentRef: nil,
                    kind: .view,
                    typeName: "_UIHostingView<ProfileView>",
                    frame: LoupeRect(x: 0, y: 0, width: 320, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    swiftui: LoupeSwiftUIProperties(
                        origin: "host",
                        backingTypeName: "_UIHostingView<ProfileView>",
                        rootTypeName: "ProfileView",
                        properties: [
                            LoupeSwiftUIProperty(
                                name: "mode",
                                typeName: "String",
                                value: .string("Profile"),
                                evidence: ["privateReflection", "propertyName"]
                            ),
                            LoupeSwiftUIProperty(
                                name: "pending",
                                typeName: "SwiftUI.LazyState<String>",
                                valueUnavailableReason: "deferredInitializer",
                                evidence: ["privateReflection", "propertyName"]
                            ),
                        ],
                        evidence: ["backingTypeName"]
                    )
                ),
            ]
        )

        let output = LoupeCLI.renderViewTree(
            snapshot,
            selector: nil,
            depth: nil,
            includeHidden: false
        )

        #expect(output.contains("host _UIHostingView<ProfileView> swiftui=host root=ProfileView props=mode=\"Profile\""))
        #expect(!output.contains("swiftui=private"))
        #expect(output.contains("pending=<unavailable:deferredInitializer>"))
    }
}
