import Foundation
import LoupeCore
import Testing
@testable import LoupeKit

struct TouchDeclarationTests {
    @Test func descendantSemanticsMergeWithGestureDeclarations() {
        let frame = LoupeRect(x: 24, y: 285.33, width: 354, height: 45)
        var nodes = [
            "container": LoupeNode(ref: "container", parentRef: "host", kind: .view,
                                  typeName: "PlatformGroupContainer", isVisible: true, isEnabled: true,
                                  isInteractive: false, children: ["native"]),
            "native": LoupeNode(ref: "native", parentRef: "container", kind: .view,
                               typeName: "SwiftUI.Text", role: "staticText", testID: "gesture.tap", frame: frame,
                               isVisible: true, isEnabled: true, isInteractive: false),
            "tap": LoupeNode(ref: "tap", parentRef: "host", kind: .view, typeName: "SwiftUI.Gesture",
                            testID: "gesture.tap", frame: frame, isVisible: true, isEnabled: true,
                            isInteractive: true, touchActions: [.tap]),
            "hold": LoupeNode(ref: "hold", parentRef: "host", kind: .view, typeName: "SwiftUI.Gesture",
                             testID: "gesture.tap", frame: frame, isVisible: true, isEnabled: true,
                             isInteractive: true, touchActions: [.longPress]),
            "otherHost": LoupeNode(ref: "otherHost", parentRef: "another-host", kind: .view,
                                  typeName: "SwiftUI.Text", testID: "gesture.tap", frame: frame,
                                  isVisible: true, isEnabled: true, isInteractive: false),
        ]
        var refs = ["container", "tap", "hold"]
        loupeMergeSwiftUIGestureNodes(childRefs: &refs, nodes: &nodes)
        #expect(refs == ["container"])
        #expect(nodes["container"]?.children == ["native"])
        #expect(nodes["native"]?.parentRef == "container")
        #expect(nodes["native"]?.touchActions == [.tap, .longPress])
        #expect(nodes["native"]?.isInteractive == true)
        #expect(nodes["tap"] == nil && nodes["hold"] == nil)
        #expect(nodes["otherHost"]?.touchActions == nil)
    }

    @Test func distinctSemanticElementsRemainAmbiguous() {
        let frame = LoupeRect(x: 20, y: 30, width: 100, height: 45)
        var nodes = [
            "first": LoupeNode(ref: "first", parentRef: "host", kind: .view, typeName: "SwiftUI.Text",
                               testID: "duplicate", frame: frame, isVisible: true, isEnabled: true, isInteractive: false),
            "second": LoupeNode(ref: "second", parentRef: "host", kind: .view, typeName: "SwiftUI.Text",
                                testID: "duplicate", frame: frame, isVisible: true, isEnabled: true, isInteractive: false),
            "gesture": LoupeNode(ref: "gesture", parentRef: "host", kind: .view, typeName: "SwiftUI.Gesture",
                                 testID: "duplicate", frame: frame, isVisible: true, isEnabled: true,
                                 isInteractive: true, touchActions: [.tap]),
        ]
        var refs = ["first", "second", "gesture"]
        loupeMergeSwiftUIGestureNodes(childRefs: &refs, nodes: &nodes)
        #expect(refs.count == 3 && nodes.count == 3)
        #expect(nodes["first"]?.touchActions == nil)
        #expect(nodes["second"]?.touchActions == nil)
    }

    @Test func concreteModifiersExcludeParentTypeNoiseAndDisabledMasks() {
        func gesture(count: Int, mask: UInt32, handled: Bool = true) -> LoupeSwiftUITouchDebugNode {
            let type = handled ? "SwiftUI._EndedGesture<SwiftUI.TapGesture>" : "SwiftUI.TapGesture"
            return .init(typeName: "SwiftUI.AddGestureModifier<\(type), SwiftUI.DefaultGestureCombiner>",
                value: ["subattributes": [
                    ["type": "SwiftUI.TapGesture", "subattributes": [["name": "count", "value": count]]],
                    ["type": "SwiftUI.GestureMask", "subattributes": [["name": "rawValue", "value": mask]]],
                ]], frame: nil, children: [
                    .init(typeName: "SwiftUI.Text", value: ["subattributes": [["name": "verbatim", "value": "Double only"]]], frame: nil, children: [])
                ])
        }
        let root = LoupeSwiftUITouchDebugNode(
            typeName: "SwiftUI.ModifiedContent<Text, AddGestureModifier<TapGesture, DefaultGestureCombiner>>",
            value: ["subattributes": [["type": "SwiftUI.AccessibilityIdentifierStorage", "subattributes": [["name": "rawValue", "value": "gesture.double"]]]]],
            frame: LoupeRect(x: 20, y: 30, width: 100, height: 45),
            children: [gesture(count: 2, mask: 3), gesture(count: 1, mask: 0), gesture(count: 3, mask: 3),
                gesture(count: 1, mask: 3, handled: false),
                .init(typeName: "SwiftUI._AllowsHitTestingModifier",
                      value: ["subattributes": [["name": "allowsHitTesting", "value": false]]], frame: nil,
                      children: [gesture(count: 1, mask: 3)])])
        let parsed = LoupeSwiftUITouchDeclarations.parse([root])
        #expect(parsed.targets.count == 1)
        #expect(parsed.targets.first?.actions == [.doubleTap])
        #expect(parsed.targets.first?.frame == LoupeRect(x: 20, y: 30, width: 100, height: 45))
        #expect(parsed.targets.first?.testID == "gesture.double")
        #expect(parsed.targets.first?.label == "Double only")
    }
}
