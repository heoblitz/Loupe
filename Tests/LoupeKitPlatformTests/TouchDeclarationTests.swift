import Foundation
import LoupeCore
import Testing
@testable import LoupeKit

struct TouchDeclarationTests {
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
