import Foundation
@testable import LoupeCore

enum InspectionSnapshotFixture {
    static func makeSnapshot() -> LoupeSnapshot {
        LoupeSnapshot(
            id: "inspect-1",
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
                    children: ["row", "scroll"]
                ),
                "row": LoupeNode(
                    ref: "row",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIStackView",
                    testID: "components.row",
                    frame: LoupeRect(x: 20, y: 100, width: 350, height: 44),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["label", "switch"]
                ),
                "label": LoupeNode(
                    ref: "label",
                    parentRef: "row",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "components.label",
                    text: "Enabled",
                    frame: LoupeRect(x: 20, y: 100, width: 120, height: 44),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "switch": LoupeNode(
                    ref: "switch",
                    parentRef: "row",
                    kind: .view,
                    typeName: "UISwitch",
                    role: "switch",
                    testID: "components.switch",
                    frame: LoupeRect(x: 300, y: 100, width: 51, height: 31),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    uiKit: LoupeUIKitProperties(
                        className: "UISwitch",
                        tag: 0,
                        alpha: 1,
                        isHidden: false,
                        isOpaque: false,
                        clipsToBounds: false,
                        userInteractionEnabled: true,
                        isFirstResponder: false,
                        switchControl: LoupeUISwitchProperties(isOn: true)
                    )
                ),
                "scroll": LoupeNode(
                    ref: "scroll",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIScrollView",
                    role: "scrollView",
                    testID: "bottomSheet.results",
                    frame: LoupeRect(x: 20, y: 220, width: 350, height: 420),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    uiKit: LoupeUIKitProperties(
                        className: "UIScrollView",
                        tag: 0,
                        alpha: 1,
                        isHidden: false,
                        isOpaque: false,
                        clipsToBounds: true,
                        userInteractionEnabled: true,
                        gestureRecognizers: ["UIScrollViewPanGestureRecognizer"],
                        isFirstResponder: false,
                        scrollView: LoupeUIScrollViewProperties(
                            contentOffset: LoupePoint(x: 0, y: 240),
                            contentSize: LoupeSize(width: 350, height: 1_240),
                            adjustedContentInset: LoupeInsets(top: 0, left: 0, bottom: 34, right: 0),
                            isScrollEnabled: true,
                            alwaysBounceVertical: true,
                            alwaysBounceHorizontal: false
                        )
                    )
                ),
            ]
        )
    }
}
