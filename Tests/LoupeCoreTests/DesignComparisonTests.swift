import Foundation
import Testing
@testable import LoupeCore

struct DesignComparisonTests {
    @Test func comparesDesignNodesByTestIDAndReportsStyleDeltas() {
        let snapshot = LoupeSnapshot(
            id: "design-1",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 402, height: 874), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 402, height: 874),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["title", "switch"]
                ),
                "title": LoupeNode(
                    ref: "title",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "bookmark.detail.title",
                    text: "Swift Documentation",
                    frame: LoupeRect(x: 16, y: 192, width: 370, height: 34),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".SFUI-Regular", fontSize: 24, textColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 1))
                ),
                "switch": LoupeNode(
                    ref: "switch",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UISwitch",
                    role: "switch",
                    testID: "bookmark.detail.favorite",
                    frame: LoupeRect(x: 266, y: 283, width: 63, height: 28),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    style: LoupeStyle(backgroundColor: LoupeColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1)),
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
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "BookmarkDetail", width: 402, height: 874),
            nodes: [
                LoupeDesignNode(
                    id: "bookmark.detail.title",
                    name: "Title",
                    role: "staticText",
                    text: "Swift Documentation",
                    frame: LoupeRect(x: 16, y: 192, width: 370, height: 34),
                    style: LoupeDesignStyle(textColor: "#000000", fontName: ".SFUI-Regular", fontSize: 24)
                ),
                LoupeDesignNode(
                    id: "bookmark.detail.favorite",
                    name: "Favorite switch",
                    role: "switch",
                    frame: LoupeRect(x: 266, y: 283, width: 63, height: 28),
                    style: LoupeDesignStyle(backgroundColor: "#34C759", cornerRadius: 14)
                ),
                LoupeDesignNode(
                    id: "bookmark.detail.missing",
                    name: "Missing chip",
                    role: "button",
                    frame: LoupeRect(x: 20, y: 520, width: 120, height: 40)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 2)
        #expect(comparison.matches.map { $0.strategy } == ["testID", "testID"])
        #expect(comparison.issues.contains { issue in
            issue.kind == LoupeDesignComparisonIssueKind.missingDesignNode
                && issue.designID == "bookmark.detail.missing"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == LoupeDesignComparisonIssueKind.cornerRadiusDelta
                && issue.testID == "bookmark.detail.favorite"
        })
        let unexpectedWithoutTestID = comparison.issues.contains { issue in
            issue.kind == LoupeDesignComparisonIssueKind.unexpectedAppNode && issue.testID == nil
        }
        #expect(unexpectedWithoutTestID == false)
    }
}
