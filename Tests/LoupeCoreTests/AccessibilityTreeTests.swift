import Foundation
import Testing
@testable import LoupeCore

struct AccessibilityTreeTests {
    @Test func accessibilityTreeBuildsFromInteractiveAndAccessibleNodes() {
        let snapshot = LoupeSnapshot(
            id: "s1",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 390, height: 844),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["container"]
                ),
                "container": LoupeNode(
                    ref: "container",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIStackView",
                    testID: "checkout.form",
                    frame: LoupeRect(x: 20, y: 100, width: 350, height: 200),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    accessibility: LoupeAccessibility(identifier: "checkout.form"),
                    children: ["label", "button"]
                ),
                "label": LoupeNode(
                    ref: "label",
                    parentRef: "container",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    text: "Checkout",
                    frame: LoupeRect(x: 32, y: 120, width: 120, height: 30),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    accessibility: LoupeAccessibility(label: "Checkout", traits: ["staticText"])
                ),
                "button": LoupeNode(
                    ref: "button",
                    parentRef: "container",
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "checkout.payButton",
                    text: "Pay now",
                    frame: LoupeRect(x: 32, y: 240, width: 326, height: 52),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    accessibility: LoupeAccessibility(
                        identifier: "checkout.payButton",
                        label: "Pay now",
                        traits: ["button"],
                        activationPoint: LoupePoint(x: 195, y: 266),
                        isElement: true
                    ),
                    uikit: LoupeUIKitProperties(
                        className: "UIButton",
                        tag: 0,
                        alpha: 1,
                        isHidden: false,
                        isOpaque: false,
                        clipsToBounds: false,
                        userInteractionEnabled: true,
                        isFirstResponder: false,
                        isFocused: true,
                        canBecomeFocused: true
                    )
                ),
            ]
        )

        let tree = LoupeAccessibilityTree.build(from: snapshot)

        #expect(tree.snapshotID == "s1")
        #expect(tree.rootRefs == ["ax-container"])
        #expect(tree.nodes["ax-container"]?.children == ["ax-label", "ax-button"])
        #expect(tree.nodes["ax-button"]?.sourceRef == "button")
        #expect(tree.nodes["ax-button"]?.activationPoint == LoupePoint(x: 195, y: 266))
        #expect(tree.nodes["ax-button"]?.isFocused == true)
        #expect(tree.nodes["ax-button"]?.canBecomeFocused == true)
    }

    @Test func accessibilityQueryMatchesTestIDTextRoleAndSourceRef() {
        let tree = LoupeAccessibilityTree(
            snapshotID: "s1",
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["ax-button"],
            nodes: [
                "ax-button": LoupeAccessibilityNode(
                    ref: "ax-button",
                    sourceRef: "button",
                    role: "button",
                    label: "Pay now",
                    testID: "checkout.payButton",
                    traits: ["button"],
                    frame: LoupeRect(x: 32, y: 240, width: 326, height: 52),
                    activationPoint: LoupePoint(x: 195, y: 266),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                ),
            ]
        )

        #expect(LoupeAccessibilityTreeQuery.find(.testID("checkout.payButton"), in: tree).map { $0.sourceRef } == ["button"])
        #expect(LoupeAccessibilityTreeQuery.find(.text("pay", exact: false), in: tree).map { $0.ref } == ["ax-button"])
        #expect(LoupeAccessibilityTreeQuery.find(.role("button"), in: tree).map { $0.ref } == ["ax-button"])
        #expect(LoupeAccessibilityTreeQuery.find(.ref("button"), in: tree).map { $0.ref } == ["ax-button"])
    }

    @Test func accessibilityTreeDropsActivationPointOutsideFrame() {
        let snapshot = LoupeSnapshot(
            id: "s1",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["button"],
            nodes: [
                "button": LoupeNode(
                    ref: "button",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "checkout.payButton",
                    text: "Pay now",
                    frame: LoupeRect(x: 32, y: 240, width: 326, height: 52),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    accessibility: LoupeAccessibility(
                        identifier: "checkout.payButton",
                        label: "Pay now",
                        traits: ["button"],
                        activationPoint: LoupePoint(x: 0, y: 0),
                        isElement: false
                    )
                ),
            ]
        )

        let tree = LoupeAccessibilityTree.build(from: snapshot)

        #expect(tree.nodes["ax-button"]?.activationPoint == nil)
    }

    @Test func accessibilityTreeKeepsVisibleAppAuthoredProbeWhenSurfaceOccluded() throws {
        let probeFrame = LoupeRect(x: 0, y: 143, width: 390, height: 600)
        let snapshot = LoupeSnapshot(
            id: "s1",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 390, height: 844),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["probe", "cover"]
                ),
                "probe": LoupeNode(
                    ref: "probe",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIView",
                    testID: "example.fixtures.swiftui.probe",
                    label: "iOS SwiftUI probe",
                    frame: probeFrame,
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    accessibility: LoupeAccessibility(
                        identifier: "example.fixtures.swiftui.probe",
                        label: "iOS SwiftUI probe",
                        frame: probeFrame,
                        isElement: true
                    ),
                    custom: [
                        "loupe.probe": .bool(true),
                        "loupe.swiftUI": .bool(true),
                    ]
                ),
                "cover": LoupeNode(
                    ref: "cover",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIView",
                    frame: probeFrame,
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 1, green: 1, blue: 1, alpha: 1)
                    )
                ),
            ]
        )

        #expect(!LoupeSurfaceVisibility.visibleNodeRefs(in: snapshot, includesOffscreen: true).contains("probe"))

        let tree = LoupeAccessibilityTree.build(from: snapshot)
        let probeNode = try #require(tree.nodes["ax-probe"])
        #expect(probeNode.sourceRef == "probe")
        #expect(probeNode.testID == "example.fixtures.swiftui.probe")
        #expect(probeNode.label == "iOS SwiftUI probe")
    }

    @Test func accessibilityTreeKeepsAccessibilityValueAndHintOnlyNodes() throws {
        let snapshot = LoupeSnapshot(
            id: "s1",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["host"],
            nodes: [
                "host": LoupeNode(
                    ref: "host",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 390, height: 120),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["valueOnly", "hintOnly"]
                ),
                "valueOnly": LoupeNode(
                    ref: "valueOnly",
                    parentRef: "host",
                    kind: .view,
                    typeName: "NSTextField",
                    frame: LoupeRect(x: 20, y: 20, width: 180, height: 24),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    accessibility: LoupeAccessibility(value: "Value only")
                ),
                "hintOnly": LoupeNode(
                    ref: "hintOnly",
                    parentRef: "host",
                    kind: .view,
                    typeName: "NSAccessibilityElement",
                    frame: LoupeRect(x: 20, y: 52, width: 180, height: 24),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    accessibility: LoupeAccessibility(hint: "Hint only")
                ),
            ]
        )

        let tree = LoupeAccessibilityTree.build(from: snapshot)

        let valueNode = try #require(tree.nodes["ax-valueOnly"])
        #expect(valueNode.value == "Value only")
        #expect(LoupeAccessibilityTreeQuery.find(.text("Value only", exact: true), in: tree).map(\.ref) == ["ax-valueOnly"])

        let hintNode = try #require(tree.nodes["ax-hintOnly"])
        #expect(hintNode.hint == "Hint only")
        #expect(LoupeAccessibilityTreeQuery.find(.text("Hint only", exact: true), in: tree).map(\.ref) == ["ax-hintOnly"])
    }
}
