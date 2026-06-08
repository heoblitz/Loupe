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
        #expect(comparison.suggestions.contains { suggestion in
            suggestion.issueKind == .cornerRadiusDelta
                && suggestion.ref == "switch"
                && suggestion.property == "cornerRadius"
                && suggestion.value == .int(14)
        })
        let unexpectedWithoutTestID = comparison.issues.contains { issue in
            issue.kind == LoupeDesignComparisonIssueKind.unexpectedAppNode && issue.testID == nil
        }
        #expect(unexpectedWithoutTestID == false)
    }

    @Test func hairlineDividerCornerRadiusDoesNotCreateStyleDelta() {
        let snapshot = LoupeSnapshot(
            id: "design-hairline-radius",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1440, height: 900), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["line"]
                ),
                "line": LoupeNode(
                    ref: "line",
                    parentRef: "root",
                    kind: .view,
                    typeName: "ShapeView",
                    role: "Unknown",
                    testID: "dashboard.divider",
                    frame: LoupeRect(x: 268, y: 550, width: 552, height: 1),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1),
                        cornerRadius: 0
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Dashboard", width: 1440, height: 900),
            nodes: [
                LoupeDesignNode(
                    id: "dashboard.divider",
                    name: "line",
                    role: "view",
                    frame: LoupeRect(x: 268, y: 550, width: 552, height: 1),
                    style: LoupeDesignStyle(backgroundColor: "#E6E6E6", cornerRadius: 5)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { $0.kind == .cornerRadiusDelta })
    }

    @Test func testIDMatchesStillReportRoleAndTextDeltas() {
        let snapshot = LoupeSnapshot(
            id: "design-copy",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["cta"]
                ),
                "cta": LoupeNode(
                    ref: "cta",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "travel.searchButton",
                    text: "Book trip",
                    frame: LoupeRect(x: 24, y: 732, width: 345, height: 54),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Travel", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "travel.searchButton",
                    name: "Search trips button",
                    role: "staticText",
                    text: "Search trips",
                    frame: LoupeRect(x: 24, y: 732, width: 345, height: 54)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(comparison.issues.contains { issue in
            issue.kind == .roleDelta
                && issue.property == "role"
                && issue.expected == "staticText"
                && issue.actual == "button"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .textDelta
                && issue.property == "text"
                && issue.expected == "Search trips"
                && issue.actual == "Book trip"
        })
        #expect(comparison.suggestions.contains { suggestion in
            suggestion.issueKind == .textDelta
                && suggestion.ref == "cta"
                && suggestion.property == "text"
                && suggestion.value == .string("Search trips")
        })
    }

    @Test func wrappedTextWithSameWordsDoesNotReportTextDelta() {
        let snapshot = LoupeSnapshot(
            id: "design-wrapped-text",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["message"]
                ),
                "message": LoupeNode(
                    ref: "message",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "support.message.bot.prompt",
                    text: "Hello!, please choose the\nnumber corresponding to your\nneeds for a more efficient\nservice.",
                    frame: LoupeRect(x: 60, y: 266, width: 178, height: 41),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Support", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "support.message.bot.prompt",
                    name: "Bot prompt",
                    role: "staticText",
                    text: "Hello!, please choose the number corresponding to your needs for a more efficient service.",
                    frame: LoupeRect(x: 60, y: 266, width: 178, height: 41)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { issue in
            issue.kind == .textDelta
        })
        #expect(!comparison.suggestions.contains { suggestion in
            suggestion.issueKind == .textDelta
        })
    }

    @Test func truncatedNativeDisplayTextCanMatchFullDesignText() {
        let snapshot = LoupeSnapshot(
            id: "design-truncated-display-text",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1440, height: 900), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["total", "page-count"]
                ),
                "total": LoupeNode(
                    ref: "total",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "dashboard.total",
                    text: "$302...",
                    renderedText: "$302...",
                    semanticText: "$302...",
                    frame: LoupeRect(x: 1064, y: 170, width: 124, height: 33),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontSize: 24)
                ),
                "page-count": LoupeNode(
                    ref: "page-count",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "dashboard.page-count",
                    text: "290…",
                    renderedText: "290…",
                    semanticText: "290…",
                    frame: LoupeRect(x: 1259, y: 170, width: 123, height: 33),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontSize: 24)
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Dashboard", width: 1440, height: 900),
            nodes: [
                LoupeDesignNode(
                    id: "dashboard.total",
                    name: "Total",
                    role: "staticText",
                    text: "$30200",
                    frame: LoupeRect(x: 1064, y: 170, width: 83, height: 33),
                    style: LoupeDesignStyle(fontSize: 24)
                ),
                LoupeDesignNode(
                    id: "dashboard.page-count",
                    name: "Page Count",
                    role: "staticText",
                    text: "290+",
                    frame: LoupeRect(x: 1259, y: 170, width: 55, height: 33),
                    style: LoupeDesignStyle(fontSize: 24)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 2)
        #expect(!comparison.issues.contains { $0.kind == .textDelta })
        #expect(!comparison.issues.contains { $0.kind == .frameDelta })
    }

    @Test func truncatedNativeDisplayTextDoesNotHideDifferentText() {
        let snapshot = LoupeSnapshot(
            id: "design-truncated-display-text-different-prefix",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1440, height: 900), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["wrong-prefix", "no-ellipsis", "ellipsis-only"]
                ),
                "wrong-prefix": LoupeNode(
                    ref: "wrong-prefix",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "dashboard.wrong-prefix",
                    text: "$402...",
                    renderedText: "$402...",
                    semanticText: "$402...",
                    frame: LoupeRect(x: 1064, y: 170, width: 124, height: 33),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontSize: 24)
                ),
                "no-ellipsis": LoupeNode(
                    ref: "no-ellipsis",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "dashboard.no-ellipsis",
                    text: "5",
                    renderedText: "5",
                    semanticText: "5",
                    frame: LoupeRect(x: 1258, y: 338, width: 42, height: 33),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontSize: 24)
                ),
                "ellipsis-only": LoupeNode(
                    ref: "ellipsis-only",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "dashboard.ellipsis-only",
                    text: "...",
                    renderedText: "...",
                    semanticText: "...",
                    frame: LoupeRect(x: 1260, y: 390, width: 42, height: 33),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontSize: 24)
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Dashboard", width: 1440, height: 900),
            nodes: [
                LoupeDesignNode(
                    id: "dashboard.wrong-prefix",
                    name: "Total",
                    role: "staticText",
                    text: "$30200",
                    frame: LoupeRect(x: 1064, y: 170, width: 83, height: 33),
                    style: LoupeDesignStyle(fontSize: 24)
                ),
                LoupeDesignNode(
                    id: "dashboard.no-ellipsis",
                    name: "Download",
                    role: "staticText",
                    text: "500",
                    frame: LoupeRect(x: 1258, y: 338, width: 42, height: 33),
                    style: LoupeDesignStyle(fontSize: 24)
                ),
                LoupeDesignNode(
                    id: "dashboard.ellipsis-only",
                    name: "Ellipsis",
                    role: "staticText",
                    text: "500",
                    frame: LoupeRect(x: 1260, y: 390, width: 42, height: 33),
                    style: LoupeDesignStyle(fontSize: 24)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.issues.filter { $0.kind == .textDelta }.count == 3)
    }

    @Test func genericViewWithRuntimeContainerRoleDoesNotReportRoleDelta() {
        let snapshot = LoupeSnapshot(
            id: "design-container-role-view",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1200, height: 800), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSHostingView",
                    frame: LoupeRect(x: 0, y: 0, width: 1200, height: 800),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["sidebar", "background"]
                ),
                "sidebar": LoupeNode(
                    ref: "sidebar",
                    parentRef: "root",
                    kind: .view,
                    typeName: "LoupeProbeView",
                    role: "Group",
                    testID: "admin.sidebar",
                    frame: LoupeRect(x: 0, y: 99, width: 250, height: 701),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "background": LoupeNode(
                    ref: "background",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSView",
                    role: "Unknown",
                    testID: "admin.background",
                    frame: LoupeRect(x: 250, y: 99, width: 950, height: 701),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Admin", width: 1200, height: 800),
            nodes: [
                LoupeDesignNode(
                    id: "admin.sidebar",
                    name: "Sidebar",
                    role: "view",
                    frame: LoupeRect(x: 0, y: 99, width: 250, height: 701)
                ),
                LoupeDesignNode(
                    id: "admin.background",
                    name: "Background",
                    role: "view",
                    frame: LoupeRect(x: 250, y: 99, width: 950, height: 701)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 2)
        #expect(!comparison.issues.contains { issue in
            issue.kind == .roleDelta
        })
    }

    @Test func nativeTextLabelsCanUseWiderFramesWithoutLayoutDelta() {
        let snapshot = LoupeSnapshot(
            id: "native-text-frame-width",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1440, height: 900), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["wide", "centered", "taller", "offcenter", "tooTall"]
                ),
                "wide": LoupeNode(
                    ref: "wide",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "admin.sidebar.dashboard",
                    text: "Dashboard",
                    frame: LoupeRect(x: 55, y: 226, width: 130, height: 19),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "centered": LoupeNode(
                    ref: "centered",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "admin.priority.low",
                    text: "Low",
                    frame: LoupeRect(x: 763, y: 628, width: 35, height: 15),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "taller": LoupeNode(
                    ref: "taller",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "signup.field.fullName.label",
                    text: "Full name",
                    frame: LoupeRect(x: 36, y: 195, width: 214, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "offcenter": LoupeNode(
                    ref: "offcenter",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    testID: "admin.priority.offcenter",
                    text: "Low",
                    frame: LoupeRect(x: 750, y: 656, width: 35, height: 15),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "tooTall": LoupeNode(
                    ref: "tooTall",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "signup.field.email.label",
                    text: "Email address",
                    frame: LoupeRect(x: 36, y: 356, width: 214, height: 28),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Admin", width: 1440, height: 900),
            nodes: [
                LoupeDesignNode(
                    id: "admin.sidebar.dashboard",
                    name: "Dashboard",
                    role: "staticText",
                    text: "Dashboard",
                    frame: LoupeRect(x: 55, y: 226, width: 73, height: 19)
                ),
                LoupeDesignNode(
                    id: "admin.priority.low",
                    name: "Low badge",
                    role: "staticText",
                    text: "Low",
                    frame: LoupeRect(x: 770, y: 628, width: 22, height: 15)
                ),
                LoupeDesignNode(
                    id: "admin.priority.offcenter",
                    name: "Off-center Low badge",
                    role: "staticText",
                    text: "Low",
                    frame: LoupeRect(x: 770, y: 656, width: 22, height: 15)
                ),
                LoupeDesignNode(
                    id: "signup.field.fullName.label",
                    name: "Full name label",
                    role: "staticText",
                    text: "Full name",
                    frame: LoupeRect(x: 36, y: 195, width: 214, height: 14)
                ),
                LoupeDesignNode(
                    id: "signup.field.email.label",
                    name: "Email label",
                    role: "staticText",
                    text: "Email address",
                    frame: LoupeRect(x: 36, y: 356, width: 214, height: 14)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 5)
        #expect(!comparison.issues.contains { issue in
            issue.kind == .frameDelta && issue.designID == "admin.sidebar.dashboard"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .frameDelta && issue.designID == "admin.priority.low"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .frameDelta && issue.designID == "signup.field.fullName.label"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .frameDelta && issue.designID == "admin.priority.offcenter"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .frameDelta && issue.designID == "signup.field.email.label"
        })
    }

    @Test func iconTextColorCanUseTintOrChildForegroundColor() {
        let orange = LoupeColor(red: 0.9569, green: 0.3176, blue: 0.1412, alpha: 1)
        let snapshot = LoupeSnapshot(
            id: "icon-foreground-color",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["image", "social", "socialText", "mismatch", "mismatchText"]
                ),
                "image": LoupeNode(
                    ref: "image",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIImageView",
                    role: "image",
                    testID: "signup.field.password.visibility",
                    frame: LoupeRect(x: 325, y: 313, width: 17, height: 14),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(tintColor: orange)
                ),
                "social": LoupeNode(
                    ref: "social",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIView",
                    testID: "signup.social.google",
                    frame: LoupeRect(x: 136, y: 714, width: 34, height: 34),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["socialText"]
                ),
                "socialText": LoupeNode(
                    ref: "socialText",
                    parentRef: "social",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    text: "G",
                    frame: LoupeRect(x: 136, y: 714, width: 34, height: 34),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(textColor: orange)
                ),
                "mismatch": LoupeNode(
                    ref: "mismatch",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIView",
                    testID: "signup.social.facebook",
                    frame: LoupeRect(x: 179, y: 714, width: 34, height: 34),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["mismatchText"]
                ),
                "mismatchText": LoupeNode(
                    ref: "mismatchText",
                    parentRef: "mismatch",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    text: "f",
                    frame: LoupeRect(x: 179, y: 714, width: 34, height: 34),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(textColor: LoupeColor(red: 0, green: 0, blue: 1, alpha: 1))
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "YumQuick", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "signup.field.password.visibility",
                    name: "Password visibility",
                    role: "image",
                    frame: LoupeRect(x: 325, y: 313, width: 17, height: 14),
                    style: LoupeDesignStyle(textColor: "#F45124")
                ),
                LoupeDesignNode(
                    id: "signup.social.google",
                    name: "Google sign-up",
                    role: "view",
                    frame: LoupeRect(x: 136, y: 714, width: 34, height: 34),
                    style: LoupeDesignStyle(textColor: "#F45124")
                ),
                LoupeDesignNode(
                    id: "signup.social.facebook",
                    name: "Facebook sign-up",
                    role: "view",
                    frame: LoupeRect(x: 179, y: 714, width: 34, height: 34),
                    style: LoupeDesignStyle(textColor: "#F45124")
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 3)
        #expect(!comparison.issues.contains { issue in
            issue.kind == .textColorDelta && issue.designID == "signup.field.password.visibility"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .textColorDelta && issue.designID == "signup.social.google"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .textColorDelta && issue.designID == "signup.social.facebook"
        })
    }

    @Test func viewportClippedRootFrameDoesNotReportFrameDelta() {
        let snapshot = LoupeSnapshot(
            id: "viewport-clipped-root",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1440, height: 900), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    role: "Unknown",
                    testID: "admin.dashboard.root",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Admin", width: 1440, height: 900),
            nodes: [
                LoupeDesignNode(
                    id: "admin.dashboard.root",
                    name: "Dashboard root",
                    role: "view",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 2000)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { issue in
            issue.kind == .frameDelta
        })
    }

    @Test func viewportClippedNonRootFrameStillReportsFrameDelta() {
        let snapshot = LoupeSnapshot(
            id: "viewport-clipped-non-root",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1440, height: 900), scale: 2),
            rootRefs: ["window"],
            nodes: [
                "window": LoupeNode(
                    ref: "window",
                    parentRef: nil,
                    kind: .window,
                    typeName: "NSWindow",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["content"]
                ),
                "content": LoupeNode(
                    ref: "content",
                    parentRef: "window",
                    kind: .view,
                    typeName: "NSView",
                    role: "Unknown",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["panel"]
                ),
                "panel": LoupeNode(
                    ref: "panel",
                    parentRef: "content",
                    kind: .view,
                    typeName: "NSView",
                    role: "Unknown",
                    testID: "admin.scroll.content",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 900),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Admin", width: 1440, height: 900),
            nodes: [
                LoupeDesignNode(
                    id: "admin.scroll.content",
                    name: "Scrollable content",
                    role: "view",
                    frame: LoupeRect(x: 0, y: 0, width: 1440, height: 2000)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(comparison.issues.contains { issue in
            issue.kind == .frameDelta && issue.designID == "admin.scroll.content"
        })
    }

    @Test func macOSSystemFontAliasesDoNotCreateFontNameNoise() {
        let snapshot = LoupeSnapshot(
            id: "design-macos-fonts",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 960, height: 640), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSHostingView",
                    frame: LoupeRect(x: 0, y: 0, width: 960, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["title", "cta", "caption", "body", "axis", "mono"]
                ),
                "title": LoupeNode(
                    ref: "title",
                    parentRef: "root",
                    kind: .view,
                    typeName: "Text",
                    role: "staticText",
                    testID: "platform.mac.title",
                    text: "Team Inbox",
                    frame: LoupeRect(x: 52, y: 56, width: 160, height: 32),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".AppleSystemUIFontBold", fontSize: 24)
                ),
                "cta": LoupeNode(
                    ref: "cta",
                    parentRef: "root",
                    kind: .view,
                    typeName: "PillButton",
                    role: "button",
                    testID: "platform.mac.reply",
                    text: "Reply",
                    frame: LoupeRect(x: 604, y: 236, width: 96, height: 36),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    style: LoupeStyle(fontName: ".AppleSystemUIFontDemi", fontSize: 14)
                ),
                "caption": LoupeNode(
                    ref: "caption",
                    parentRef: "root",
                    kind: .view,
                    typeName: "Text",
                    role: "staticText",
                    testID: "platform.mac.caption",
                    text: "Small",
                    frame: LoupeRect(x: 52, y: 108, width: 80, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".AppleSystemUIFontBold", fontSize: 13)
                ),
                "body": LoupeNode(
                    ref: "body",
                    parentRef: "root",
                    kind: .view,
                    typeName: "Text",
                    role: "staticText",
                    testID: "platform.mac.body",
                    text: "Native body",
                    frame: LoupeRect(x: 52, y: 136, width: 120, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".AppleSystemUIFontMedium", fontSize: 16)
                ),
                "axis": LoupeNode(
                    ref: "axis",
                    parentRef: "root",
                    kind: .view,
                    typeName: "Text",
                    role: "staticText",
                    testID: "platform.mac.axis",
                    text: "01 Apr",
                    frame: LoupeRect(x: 52, y: 164, width: 80, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".AppleSystemUIFontDemi", fontSize: 15)
                ),
                "mono": LoupeNode(
                    ref: "mono",
                    parentRef: "root",
                    kind: .view,
                    typeName: "Text",
                    role: "staticText",
                    testID: "platform.mac.mono",
                    text: "Different family",
                    frame: LoupeRect(x: 52, y: 192, width: 160, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: "Courier", fontSize: 13)
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Mac", width: 960, height: 640),
            nodes: [
                LoupeDesignNode(
                    id: "platform.mac.title",
                    name: "Title",
                    role: "staticText",
                    text: "Team Inbox",
                    frame: LoupeRect(x: 52, y: 56, width: 160, height: 32),
                    style: LoupeDesignStyle(fontName: ".SFUI-Bold", fontSize: 24)
                ),
                LoupeDesignNode(
                    id: "platform.mac.reply",
                    name: "Reply button",
                    role: "button",
                    text: "Reply",
                    frame: LoupeRect(x: 604, y: 236, width: 96, height: 36),
                    style: LoupeDesignStyle(fontName: ".SFUI-Semibold", fontSize: 14)
                ),
                LoupeDesignNode(
                    id: "platform.mac.caption",
                    name: "Caption",
                    role: "staticText",
                    text: "Small",
                    frame: LoupeRect(x: 52, y: 108, width: 80, height: 18),
                    style: LoupeDesignStyle(fontName: ".SFUI-Regular", fontSize: 13)
                ),
                LoupeDesignNode(
                    id: "platform.mac.body",
                    name: "Body",
                    role: "staticText",
                    text: "Native body",
                    frame: LoupeRect(x: 52, y: 136, width: 120, height: 18),
                    style: LoupeDesignStyle(fontName: "Inter", fontSize: 16)
                ),
                LoupeDesignNode(
                    id: "platform.mac.axis",
                    name: "Axis",
                    role: "staticText",
                    text: "01 Apr",
                    frame: LoupeRect(x: 52, y: 164, width: 80, height: 18),
                    style: LoupeDesignStyle(fontName: "Inter Bold", fontSize: 15)
                ),
                LoupeDesignNode(
                    id: "platform.mac.mono",
                    name: "Mono",
                    role: "staticText",
                    text: "Different family",
                    frame: LoupeRect(x: 52, y: 192, width: 160, height: 18),
                    style: LoupeDesignStyle(fontName: "Inter", fontSize: 13)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 6)
        #expect(!comparison.issues.contains { issue in
            issue.kind == .fontNameDelta && issue.designID == "platform.mac.title"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .fontNameDelta && issue.designID == "platform.mac.reply"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .fontNameDelta && issue.designID == "platform.mac.caption"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .fontNameDelta && issue.designID == "platform.mac.body"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .fontNameDelta && issue.designID == "platform.mac.axis"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .fontNameDelta && issue.designID == "platform.mac.mono"
        })
    }

    @Test func figmaSystemFontLabelsMatchNativeSFUIRuntimeFonts() {
        let snapshot = LoupeSnapshot(
            id: "figma-system-fonts",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["title", "subtitle", "chip", "body"]
                ),
                "title": LoupeNode(
                    ref: "title",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "faq.title",
                    text: "Help Center",
                    frame: LoupeRect(x: 124, y: 74, width: 145, height: 26),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".SFUI-Bold", fontSize: 24)
                ),
                "subtitle": LoupeNode(
                    ref: "subtitle",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "faq.subtitle",
                    text: "How Can We Help You?",
                    frame: LoupeRect(x: 119, y: 108, width: 156, height: 23),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".SFUI-Medium", fontSize: 14)
                ),
                "chip": LoupeNode(
                    ref: "chip",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "faq.category.general",
                    text: "General",
                    frame: LoupeRect(x: 35, y: 200, width: 102, height: 28),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    style: LoupeStyle(fontName: ".SFUI-Semibold", fontSize: 13)
                ),
                "body": LoupeNode(
                    ref: "body",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "faq.item.0.answer",
                    text: "Answer",
                    frame: LoupeRect(x: 35, y: 378, width: 324, height: 80),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".SFUI-Regular", fontSize: 11)
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "FAQ", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "faq.title",
                    name: "Title",
                    role: "staticText",
                    text: "Help Center",
                    frame: LoupeRect(x: 124, y: 74, width: 145, height: 26),
                    style: LoupeDesignStyle(fontName: "System Bold", fontSize: 24)
                ),
                LoupeDesignNode(
                    id: "faq.subtitle",
                    name: "Subtitle",
                    role: "staticText",
                    text: "How Can We Help You?",
                    frame: LoupeRect(x: 119, y: 108, width: 156, height: 23),
                    style: LoupeDesignStyle(fontName: "System Medium", fontSize: 14)
                ),
                LoupeDesignNode(
                    id: "faq.category.general",
                    name: "General",
                    role: "button",
                    text: "General",
                    frame: LoupeRect(x: 35, y: 200, width: 102, height: 28),
                    style: LoupeDesignStyle(fontName: "System Semibold", fontSize: 13)
                ),
                LoupeDesignNode(
                    id: "faq.item.0.answer",
                    name: "Answer",
                    role: "staticText",
                    text: "Answer",
                    frame: LoupeRect(x: 35, y: 378, width: 324, height: 80),
                    style: LoupeDesignStyle(fontName: "System Regular", fontSize: 11)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 4)
        #expect(!comparison.issues.contains { $0.kind == .fontNameDelta })
    }

    @Test func designRootViewCanMatchRuntimeWindowWithoutRoleNoise() {
        let snapshot = LoupeSnapshot(
            id: "design-root-window",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["app"],
            nodes: [
                "app": LoupeNode(
                    ref: "app",
                    parentRef: nil,
                    kind: .application,
                    typeName: "UIApplication",
                    role: "application",
                    frame: LoupeRect(x: 0, y: 0, width: 390, height: 844),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["window", "transition"]
                ),
                "window": LoupeNode(
                    ref: "window",
                    parentRef: "app",
                    kind: .window,
                    typeName: "UIWindow",
                    role: "window",
                    frame: LoupeRect(x: 0, y: 0, width: 390, height: 844),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 1, green: 1, blue: 1, alpha: 1),
                        cornerRadius: 0
                    )
                ),
                "transition": LoupeNode(
                    ref: "transition",
                    parentRef: "app",
                    kind: .view,
                    typeName: "UITransitionView",
                    frame: LoupeRect(x: 0, y: 0, width: 390, height: 844),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Productivity", width: 390, height: 844),
            nodes: [
                LoupeDesignNode(
                    id: "figma.productivity.date.root",
                    name: "Screen root",
                    role: "view",
                    frame: LoupeRect(x: 0, y: 0, width: 390, height: 844),
                    style: LoupeDesignStyle(backgroundColor: "#FFFFFF", cornerRadius: 0)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { $0.kind == .roleDelta })
        #expect(!comparison.issues.contains { $0.kind == .backgroundColorDelta })
        #expect(!comparison.issues.contains { $0.kind == .cornerRadiusDelta })
    }

    @Test func repeatedRoleTextMatchesNearestFrame() {
        let snapshot = LoupeSnapshot(
            id: "design-repeated-text",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 960, height: 640), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSHostingView",
                    frame: LoupeRect(x: 0, y: 0, width: 960, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["detail", "subject"]
                ),
                "detail": LoupeNode(
                    ref: "detail",
                    parentRef: "root",
                    kind: .view,
                    typeName: "Text",
                    role: "staticText",
                    text: "Launch review notes",
                    frame: LoupeRect(x: 604, y: 58, width: 260, height: 28),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".AppleSystemUIFontBold", fontSize: 22)
                ),
                "subject": LoupeNode(
                    ref: "subject",
                    parentRef: "root",
                    kind: .view,
                    typeName: "Text",
                    role: "staticText",
                    text: "Launch review notes",
                    frame: LoupeRect(x: 296, y: 146, width: 220, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(fontName: ".AppleSystemUIFont", fontSize: 13)
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Mac", width: 960, height: 640),
            nodes: [
                LoupeDesignNode(
                    id: "platform.mac.message.one.subject",
                    name: "Selected subject",
                    role: "staticText",
                    text: "Launch review notes",
                    frame: LoupeRect(x: 296, y: 146, width: 220, height: 18),
                    style: LoupeDesignStyle(fontName: ".SFUI-Regular", fontSize: 13)
                ),
                LoupeDesignNode(
                    id: "platform.mac.detail.title",
                    name: "Detail title",
                    role: "staticText",
                    text: "Launch review notes",
                    frame: LoupeRect(x: 604, y: 58, width: 260, height: 28),
                    style: LoupeDesignStyle(fontName: ".SFUI-Bold", fontSize: 22)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matches.contains { match in
            match.designID == "platform.mac.message.one.subject" && match.ref == "subject"
        })
        #expect(comparison.matches.contains { match in
            match.designID == "platform.mac.detail.title" && match.ref == "detail"
        })
        #expect(!comparison.issues.contains { $0.kind == .frameDelta })
    }

    @Test func designNodeAliasesMatchAppTestIDsWithoutChangingDesignID() {
        let snapshot = LoupeSnapshot(
            id: "design-alias",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["button"]
                ),
                "button": LoupeNode(
                    ref: "button",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "travel.searchTrips",
                    text: "Search trips",
                    frame: LoupeRect(x: 24, y: 732, width: 345, height: 54),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Travel", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "synthetic.travel.searchButton",
                    aliases: ["travel.searchTrips"],
                    name: "Search trips button",
                    role: "button",
                    text: "Search trips",
                    frame: LoupeRect(x: 24, y: 732, width: 345, height: 54)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(comparison.matches.first?.designID == "synthetic.travel.searchButton")
        #expect(comparison.matches.first?.testID == "travel.searchTrips")
        #expect(!comparison.issues.contains { $0.kind == .missingDesignNode })
    }

    @Test func fullScreenWrapperWithTestIDDoesNotCountAsUnexpectedNode() {
        let snapshot = LoupeSnapshot(
            id: "design-wrapper",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    testID: "synthetic.banking.transfer.screen",
                    semanticText: "Review transfer Unexpected copy",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["cta", "extra"]
                ),
                "cta": LoupeNode(
                    ref: "cta",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "synthetic.banking.transfer.cta",
                    text: "Review transfer",
                    frame: LoupeRect(x: 24, y: 732, width: 345, height: 54),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true
                ),
                "extra": LoupeNode(
                    ref: "extra",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "synthetic.banking.transfer.extra",
                    text: "Unexpected copy",
                    frame: LoupeRect(x: 24, y: 680, width: 200, height: 24),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Banking", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "synthetic.banking.transfer.cta",
                    name: "CTA",
                    role: "button",
                    text: "Review transfer",
                    frame: LoupeRect(x: 24, y: 732, width: 345, height: 54)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(!comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode
                && issue.testID == "synthetic.banking.transfer.screen"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode
                && issue.testID == "synthetic.banking.transfer.extra"
        })
    }

    @Test func matchedAggregateSplitTextChildrenDoNotCountAsUnexpectedNodes() {
        let snapshot = LoupeSnapshot(
            id: "split-static-text",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["terms", "terms-prefix", "terms-link", "extra"]
                ),
                "terms": LoupeNode(
                    ref: "terms",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIView",
                    testID: "signup.terms",
                    semanticText: "By continuing, you agree to Terms of Use and Privacy Policy.",
                    frame: LoupeRect(x: 60, y: 608, width: 273, height: 28),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "terms-prefix": LoupeNode(
                    ref: "terms-prefix",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "signup.terms.prefix",
                    text: "By continuing, you agree to",
                    frame: LoupeRect(x: 60, y: 611, width: 273, height: 11),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "terms-link": LoupeNode(
                    ref: "terms-link",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "signup.terms.link",
                    text: "Terms of Use and Privacy Policy.",
                    frame: LoupeRect(x: 60, y: 621, width: 273, height: 12),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "extra": LoupeNode(
                    ref: "extra",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "signup.extra.copy",
                    text: "Extra copy",
                    frame: LoupeRect(x: 60, y: 660, width: 273, height: 12),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Sign Up", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "signup.terms",
                    name: "Terms copy",
                    role: "staticText",
                    text: "By continuing, you agree to Terms of Use and Privacy Policy.",
                    frame: LoupeRect(x: 60, y: 608, width: 273, height: 28)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode
                && issue.testID == "signup.terms.prefix"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode
                && issue.testID == "signup.terms.link"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode
                && issue.testID == "signup.extra.copy"
        })
    }

    @Test func statusChromeImagesDoNotCountAsUnexpectedNodes() {
        let snapshot = LoupeSnapshot(
            id: "status-noise",
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
                    children: ["time", "battery", "signal", "photo"]
                ),
                "time": LoupeNode(
                    ref: "time",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "figma.productivity.date.status.time",
                    text: "9:41",
                    frame: LoupeRect(x: 21, y: 14, width: 40, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "battery": LoupeNode(
                    ref: "battery",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIImageView",
                    role: "image",
                    testID: "status-battery",
                    frame: LoupeRect(x: 344, y: 15, width: 25, height: 14),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "signal": LoupeNode(
                    ref: "signal",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIImageView",
                    role: nil,
                    testID: "status.signal",
                    frame: LoupeRect(x: 280, y: 14, width: 24, height: 18),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
                "photo": LoupeNode(
                    ref: "photo",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIImageView",
                    role: "image",
                    testID: "product.hero.photo",
                    frame: LoupeRect(x: 24, y: 120, width: 120, height: 120),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Productivity", width: 390, height: 844),
            nodes: [
                LoupeDesignNode(
                    id: "figma.productivity.date.status.time",
                    name: "Status time",
                    role: "staticText",
                    text: "9:41",
                    frame: LoupeRect(x: 21, y: 14, width: 40, height: 18)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(!comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode && issue.testID == "status-battery"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode && issue.testID == "status.signal"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode && issue.testID == "product.hero.photo"
        })
    }

    @Test func passiveViewsAndSwitchVisualDescendantsAvoidNoisyDeltas() {
        let snapshot = LoupeSnapshot(
            id: "design-switch",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UIView",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["card", "switch"]
                ),
                "card": LoupeNode(
                    ref: "card",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIView",
                    testID: "banking.transfer.review.card",
                    frame: LoupeRect(x: 24, y: 640, width: 345, height: 72),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 1, green: 0.88, blue: 0.78, alpha: 1),
                        cornerRadius: 18
                    )
                ),
                "switch": LoupeNode(
                    ref: "switch",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UISwitch",
                    role: "switch",
                    testID: "banking.transfer.schedule.toggle",
                    frame: LoupeRect(x: 296, y: 546, width: 63, height: 28),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    style: LoupeStyle(cornerRadius: 0),
                    uiKit: LoupeUIKitProperties(
                        className: "UISwitch",
                        tag: 0,
                        alpha: 1,
                        isHidden: false,
                        isOpaque: true,
                        clipsToBounds: false,
                        userInteractionEnabled: true,
                        isFirstResponder: false,
                        switchControl: LoupeUISwitchProperties(isOn: true)
                    ),
                    children: ["switchVisual"]
                ),
                "switchVisual": LoupeNode(
                    ref: "switchVisual",
                    parentRef: "switch",
                    kind: .view,
                    typeName: "UISwitchModernVisualElement",
                    frame: LoupeRect(x: 296, y: 546, width: 51.66, height: 22.96),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0.05098, green: 0.47843, blue: 0.36078, alpha: 1),
                        cornerRadius: 14
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Transfer", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "banking.transfer.review.card",
                    name: "Review card",
                    role: "view",
                    frame: LoupeRect(x: 24, y: 640, width: 345, height: 72),
                    style: LoupeDesignStyle(backgroundColor: "#FFE0C7", cornerRadius: 18)
                ),
                LoupeDesignNode(
                    id: "banking.transfer.schedule.toggle",
                    name: "Schedule toggle",
                    role: "switch",
                    frame: LoupeRect(x: 296, y: 546, width: 46, height: 26),
                    style: LoupeDesignStyle(backgroundColor: "#0D7A5C", cornerRadius: 13)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 2)
        #expect(!comparison.issues.contains { $0.kind == .roleDelta })
        #expect(!comparison.issues.contains { $0.kind == .frameDelta })
        #expect(!comparison.issues.contains { $0.kind == .backgroundColorDelta })
        #expect(!comparison.issues.contains { $0.kind == .cornerRadiusDelta })
        #expect(comparison.suggestions.isEmpty)
    }

    @Test func appKitWindowOffsetFramesAreComparedInWindowCoordinates() {
        let snapshot = LoupeSnapshot(
            id: "appkit-window-offset",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1920, height: 1080), scale: 2),
            rootRefs: ["app"],
            nodes: [
                "app": LoupeNode(
                    ref: "app",
                    parentRef: nil,
                    kind: .application,
                    typeName: "NSApplication",
                    role: "application",
                    frame: LoupeRect(x: 0, y: 0, width: 1920, height: 1080),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["window"]
                ),
                "window": LoupeNode(
                    ref: "window",
                    parentRef: "app",
                    kind: .window,
                    typeName: "NSWindow",
                    role: "window",
                    frame: LoupeRect(x: 360, y: 93, width: 1200, height: 800),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["title", "wideNav"]
                ),
                "title": LoupeNode(
                    ref: "title",
                    parentRef: "window",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    text: "Overview",
                    frame: LoupeRect(x: 420, y: 178, width: 100, height: 24),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        fontName: "Inter",
                        fontSize: 16,
                        textColor: LoupeColor(red: 0.11, green: 0.39, blue: 0.95, alpha: 1)
                    )
                ),
                "wideNav": LoupeNode(
                    ref: "wideNav",
                    parentRef: "window",
                    kind: .view,
                    typeName: "NSView",
                    role: "Group",
                    testID: "desktop.nav",
                    frame: LoupeRect(x: 360, y: 93, width: 1600, height: 70),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Desktop", width: 1200, height: 800),
            nodes: [
                LoupeDesignNode(
                    id: "overview",
                    name: "Overview",
                    role: "staticText",
                    text: "Overview",
                    frame: LoupeRect(x: 60, y: 85, width: 100, height: 24),
                    style: LoupeDesignStyle(textColor: "#1c64f2", fontName: "Inter", fontSize: 16)
                ),
                LoupeDesignNode(
                    id: "desktop.nav",
                    name: "Wide nav",
                    role: "view",
                    frame: LoupeRect(x: 0, y: 0, width: 1600, height: 70)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 2)
        #expect(!comparison.issues.contains { $0.kind == .frameDelta })
    }

    @Test func accessibilityBackedTextDoesNotEmitUnobservableStyleSuggestions() {
        let snapshot = LoupeSnapshot(
            id: "custom-accessibility-text",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1200, height: 800), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 1200, height: 800),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["customText"]
                ),
                "customText": LoupeNode(
                    ref: "customText",
                    parentRef: "root",
                    kind: .view,
                    typeName: "TextView",
                    role: "staticText",
                    label: "Search",
                    value: "Search",
                    semanticText: "Search",
                    frame: LoupeRect(x: 132, y: 25, width: 325, height: 24),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(alpha: 1),
                    accessibility: LoupeAccessibility(label: "Search", value: "Search", traits: ["staticText"])
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Desktop", width: 1200, height: 800),
            nodes: [
                LoupeDesignNode(
                    id: "desktop.search",
                    name: "Search",
                    role: "staticText",
                    text: "Search",
                    frame: LoupeRect(x: 132, y: 25, width: 325, height: 24),
                    style: LoupeDesignStyle(textColor: "#6b7280", fontName: "Inter", fontSize: 16)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(comparison.issues.isEmpty)
        #expect(comparison.suggestions.isEmpty)
    }

    @Test func staticTextWithVisualParentUsesParentForFrameAndBackgroundStyle() {
        let snapshot = LoupeSnapshot(
            id: "macos-selected-row",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 960, height: 640), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 960, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["pill"]
                ),
                "pill": LoupeNode(
                    ref: "pill",
                    parentRef: "root",
                    kind: .view,
                    typeName: "RoundedView",
                    role: "Group",
                    label: "Needs action",
                    semanticText: "Needs action",
                    frame: LoupeRect(x: 52, y: 208, width: 150, height: 22),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0.862745098, green: 0.921568627, blue: 1, alpha: 1),
                        cornerRadius: 8
                    ),
                    children: ["label"]
                ),
                "label": LoupeNode(
                    ref: "label",
                    parentRef: "pill",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    text: "Needs action",
                    renderedText: "Needs action",
                    semanticText: "Needs action",
                    frame: LoupeRect(x: 52, y: 209, width: 150, height: 20),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        fontName: ".AppleSystemUIFontDemi",
                        fontSize: 14,
                        textColor: LoupeColor(red: 0.0784313725, green: 0.349019608, blue: 0.721568627, alpha: 1)
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Mac", width: 960, height: 640),
            nodes: [
                LoupeDesignNode(
                    id: "platform.mac.folder.action",
                    name: "Needs action item",
                    role: "staticText",
                    text: "Needs action",
                    frame: LoupeRect(x: 52, y: 208, width: 150, height: 22),
                    style: LoupeDesignStyle(
                        backgroundColor: "#DCEBFF",
                        textColor: "#1459B8",
                        cornerRadius: 8,
                        fontName: ".SFUI-Semibold",
                        fontSize: 14
                    )
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { $0.kind == .frameDelta })
        #expect(!comparison.issues.contains { $0.kind == .backgroundColorDelta })
        #expect(!comparison.issues.contains { $0.kind == .cornerRadiusDelta })
    }

    @Test func appKitTextFieldExposedAsStaticTextCanMatchTextFieldRole() {
        let snapshot = LoupeSnapshot(
            id: "macos-search-field",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 960, height: 640), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSView",
                    frame: LoupeRect(x: 0, y: 0, width: 960, height: 640),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["search"]
                ),
                "search": LoupeNode(
                    ref: "search",
                    parentRef: "root",
                    kind: .view,
                    typeName: "NSTextField",
                    role: "staticText",
                    text: "Search conversations",
                    renderedText: "Search conversations",
                    semanticText: "Search conversations",
                    frame: LoupeRect(x: 52, y: 108, width: 164, height: 34),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0.898039216, green: 0.91372549, blue: 0.937254902, alpha: 1),
                        cornerRadius: 9,
                        fontSize: 13,
                        textColor: LoupeColor(red: 0.42745098, green: 0.462745098, blue: 0.517647059, alpha: 1)
                    ),
                    uiKit: LoupeUIKitProperties(
                        className: "NSTextField",
                        tag: 0,
                        alpha: 1,
                        isHidden: false,
                        isOpaque: false,
                        clipsToBounds: true,
                        userInteractionEnabled: false,
                        isFirstResponder: false,
                        textField: LoupeUITextFieldProperties(textAlignment: "left", borderStyle: "none")
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Mac", width: 960, height: 640),
            nodes: [
                LoupeDesignNode(
                    id: "platform.mac.search",
                    name: "Search field",
                    role: "textField",
                    text: "Search conversations",
                    frame: LoupeRect(x: 52, y: 108, width: 164, height: 34),
                    style: LoupeDesignStyle(
                        backgroundColor: "#E5E9EF",
                        textColor: "#6D7684",
                        cornerRadius: 9,
                        fontSize: 13
                    )
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { $0.kind == .roleDelta })
    }

    @Test func staticTextCanMatchWatchProbeTextWithoutExactRole() {
        let snapshot = LoupeSnapshot(
            id: "watch-probe-text",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 198, height: 242), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .application,
                    typeName: "WatchApp",
                    frame: LoupeRect(x: 0, y: 0, width: 198, height: 242),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["title"]
                ),
                "title": LoupeNode(
                    ref: "title",
                    parentRef: "root",
                    kind: .view,
                    typeName: "LoupeWatchProbe",
                    role: "group",
                    testID: "workout.title",
                    label: "Run",
                    text: "Run",
                    frame: LoupeRect(x: 18, y: 16, width: 42, height: 24),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    custom: ["loupe.probe": .bool(true)]
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Watch", width: 198, height: 242),
            nodes: [
                LoupeDesignNode(
                    id: "platform.watch.title",
                    name: "Workout title",
                    role: "staticText",
                    text: "Run",
                    frame: LoupeRect(x: 18, y: 16, width: 42, height: 24),
                    style: LoupeDesignStyle(textColor: "#FFFFFF", fontName: ".SFUI-Bold", fontSize: 21)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(comparison.matches.first?.strategy == "roleText")
        #expect(!comparison.issues.contains { $0.kind == .missingDesignNode })
        #expect(!comparison.issues.contains { $0.kind == .roleDelta })
        #expect(!comparison.issues.contains { $0.kind == .textColorDelta })
        #expect(!comparison.issues.contains { $0.kind == .fontNameDelta })
        #expect(!comparison.issues.contains { $0.kind == .fontSizeDelta })
    }

    @Test func watchProbeMissingStyleDoesNotCreateVisualStyleNoise() {
        let snapshot = LoupeSnapshot(
            id: "watch-probe-card",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 198, height: 242), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .application,
                    typeName: "WatchApp",
                    frame: LoupeRect(x: 0, y: 0, width: 198, height: 242),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["card"]
                ),
                "card": LoupeNode(
                    ref: "card",
                    parentRef: "root",
                    kind: .view,
                    typeName: "LoupeWatchProbe",
                    role: "group",
                    testID: "workout.distance.card",
                    label: "Distance 4.82 km",
                    text: "Distance 4.82 km",
                    frame: LoupeRect(x: 16, y: 62, width: 166, height: 73),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    custom: ["loupe.probe": .bool(true)]
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Watch", width: 198, height: 242),
            nodes: [
                LoupeDesignNode(
                    id: "platform.watch.metric.card",
                    name: "Metric card",
                    frame: LoupeRect(x: 16, y: 54, width: 166, height: 74),
                    style: LoupeDesignStyle(backgroundColor: "#111821", cornerRadius: 18)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(comparison.issues.contains { $0.kind == .frameDelta })
        #expect(!comparison.issues.contains { $0.kind == .backgroundColorDelta })
        #expect(!comparison.issues.contains { $0.kind == .cornerRadiusDelta })
    }

    @Test func swiftUIProbeBackingLeafTransparentStyleDoesNotCreateVisualStyleNoise() {
        let snapshot = LoupeSnapshot(
            id: "swiftui-probe-transparent-style",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1200, height: 800), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .view,
                    typeName: "NSHostingView<Dashboard>",
                    frame: LoupeRect(x: 0, y: 0, width: 1200, height: 800),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["host"]
                ),
                "host": LoupeNode(
                    ref: "host",
                    parentRef: "root",
                    kind: .view,
                    typeName: "AppKitPlatformViewHost<PlatformViewRepresentableAdaptor<LoupeProbeView>>",
                    frame: LoupeRect(x: 87, y: 12, width: 402, height: 45),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["probeLeaf"]
                ),
                "probeLeaf": LoupeNode(
                    ref: "probeLeaf",
                    parentRef: "host",
                    kind: .view,
                    typeName: "NSView",
                    role: "Group",
                    testID: "dashboard.search.background",
                    frame: LoupeRect(x: 87, y: 12, width: 402, height: 45),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0),
                        cornerRadius: 0
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Dashboard", width: 1200, height: 800),
            nodes: [
                LoupeDesignNode(
                    id: "dashboard.search.background",
                    name: "Search background",
                    role: "view",
                    frame: LoupeRect(x: 87, y: 12, width: 402, height: 45),
                    style: LoupeDesignStyle(backgroundColor: "#F9FAFB", cornerRadius: 16)
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 1)
        #expect(!comparison.issues.contains { $0.kind == .backgroundColorDelta })
        #expect(!comparison.issues.contains { $0.kind == .cornerRadiusDelta })
    }

    @Test func swiftUIRepresentableProbeLayerDoesNotCreatePlaceholderStyleNoise() {
        let snapshot = LoupeSnapshot(
            id: "swiftui-representable-probe-placeholder-style",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .application,
                    typeName: "YumQuick",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["adapter"]
                ),
                "adapter": LoupeNode(
                    ref: "adapter",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIKitPlatformViewHost<PlatformViewRepresentableAdaptor<ContactProbeLayer>>",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["probeLayer"]
                ),
                "probeLayer": LoupeNode(
                    ref: "probeLayer",
                    parentRef: "adapter",
                    kind: .view,
                    typeName: "UIView",
                    testID: "contact.probeLayer",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    children: ["header", "title", "tab"]
                ),
                "header": LoupeNode(
                    ref: "header",
                    parentRef: "probeLayer",
                    kind: .view,
                    typeName: "UIView",
                    testID: "contact.header",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 130),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0),
                        cornerRadius: 0
                    )
                ),
                "title": LoupeNode(
                    ref: "title",
                    parentRef: "probeLayer",
                    kind: .view,
                    typeName: "UILabel",
                    role: "staticText",
                    testID: "contact.title",
                    label: "Help Center",
                    text: "Help Center",
                    frame: LoupeRect(x: 124, y: 74, width: 145, height: 26),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0),
                        cornerRadius: 0,
                        fontName: ".SFUI-Regular",
                        fontSize: 1,
                        textColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0)
                    )
                ),
                "tab": LoupeNode(
                    ref: "tab",
                    parentRef: "probeLayer",
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "contact.tab.faq",
                    label: "FAQ",
                    text: "FAQ",
                    frame: LoupeRect(x: 35, y: 161, width: 155, height: 28),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0),
                        cornerRadius: 0,
                        fontName: ".SFUI-Regular",
                        fontSize: 1,
                        textColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0)
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Contact", width: 393, height: 852),
            nodes: [
                LoupeDesignNode(
                    id: "contact.header",
                    name: "Header background",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 130),
                    style: LoupeDesignStyle(backgroundColor: "#FFD65A")
                ),
                LoupeDesignNode(
                    id: "contact.title",
                    name: "Help Center",
                    role: "staticText",
                    text: "Help Center",
                    frame: LoupeRect(x: 124, y: 74, width: 145, height: 26),
                    style: LoupeDesignStyle(textColor: "#FFFFFF", fontName: "System Bold", fontSize: 24)
                ),
                LoupeDesignNode(
                    id: "contact.tab.faq",
                    name: "FAQ tab",
                    role: "button",
                    text: "FAQ",
                    frame: LoupeRect(x: 35, y: 161, width: 155, height: 28),
                    style: LoupeDesignStyle(
                        backgroundColor: "#F9D8CE",
                        textColor: "#F45124",
                        cornerRadius: 14,
                        fontName: "System Medium",
                        fontSize: 14
                    )
                ),
            ]
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.matchedCount == 3)
        #expect(comparison.issues.isEmpty)
    }

    @Test func probeBackedMeaningfulUnexpectedChildStillReportsUnexpectedNode() {
        let snapshot = LoupeSnapshot(
            id: "probe-backed-unexpected-child",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 393, height: 852), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .application,
                    typeName: "YumQuick",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["adapter"]
                ),
                "adapter": LoupeNode(
                    ref: "adapter",
                    parentRef: "root",
                    kind: .view,
                    typeName: "UIKitPlatformViewHost<PlatformViewRepresentableAdaptor<ContactProbeLayer>>",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["probeLayer"]
                ),
                "probeLayer": LoupeNode(
                    ref: "probeLayer",
                    parentRef: "adapter",
                    kind: .view,
                    typeName: "UIView",
                    testID: "contact.probeLayer",
                    frame: LoupeRect(x: 0, y: 0, width: 393, height: 852),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    children: ["extraButton"]
                ),
                "extraButton": LoupeNode(
                    ref: "extraButton",
                    parentRef: "probeLayer",
                    kind: .view,
                    typeName: "UIButton",
                    role: "button",
                    testID: "contact.extra.button",
                    text: "Extra",
                    frame: LoupeRect(x: 24, y: 720, width: 120, height: 44),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: true,
                    accessibility: LoupeAccessibility(
                        identifier: "contact.extra.button",
                        label: "Extra",
                        traits: ["button"],
                        frame: LoupeRect(x: 24, y: 720, width: 120, height: 44),
                        isElement: true
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Contact", width: 393, height: 852),
            nodes: []
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode && issue.testID == "contact.extra.button"
        })
        #expect(!comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode && issue.testID == "contact.probeLayer"
        })
    }

    @Test func fullFrameProbeLabelSurfaceDoesNotCountAsUnexpectedNode() {
        let snapshot = LoupeSnapshot(
            id: "full-frame-probe-label",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 1200, height: 800), scale: 2),
            rootRefs: ["root"],
            nodes: [
                "root": LoupeNode(
                    ref: "root",
                    parentRef: nil,
                    kind: .application,
                    typeName: "Admin",
                    frame: LoupeRect(x: 0, y: 0, width: 1200, height: 800),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["adapter", "small-adapter"]
                ),
                "adapter": LoupeNode(
                    ref: "adapter",
                    parentRef: "root",
                    kind: .view,
                    typeName: "AppKitPlatformViewHost<PlatformViewRepresentableAdaptor<LoupeProbeView>>",
                    frame: LoupeRect(x: 0, y: 0, width: 1200, height: 800),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["background"]
                ),
                "background": LoupeNode(
                    ref: "background",
                    parentRef: "adapter",
                    kind: .view,
                    typeName: "NSView",
                    role: "Group",
                    testID: "admin.background",
                    label: "Dashboard background",
                    semanticText: "Dashboard background",
                    frame: LoupeRect(x: 0, y: 0, width: 1200, height: 800),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0),
                        cornerRadius: 0
                    ),
                    accessibility: LoupeAccessibility(
                        identifier: "admin.background",
                        label: "Dashboard background",
                        traits: ["Group"],
                        frame: LoupeRect(x: 0, y: 0, width: 1200, height: 800),
                        isElement: true
                    )
                ),
                "small-adapter": LoupeNode(
                    ref: "small-adapter",
                    parentRef: "root",
                    kind: .view,
                    typeName: "AppKitPlatformViewHost<PlatformViewRepresentableAdaptor<LoupeProbeView>>",
                    frame: LoupeRect(x: 24, y: 24, width: 200, height: 44),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    children: ["small-group"]
                ),
                "small-group": LoupeNode(
                    ref: "small-group",
                    parentRef: "small-adapter",
                    kind: .view,
                    typeName: "NSView",
                    role: "Group",
                    testID: "admin.unexpected.group",
                    label: "Unexpected group",
                    semanticText: "Unexpected group",
                    frame: LoupeRect(x: 24, y: 24, width: 200, height: 44),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false,
                    style: LoupeStyle(
                        backgroundColor: LoupeColor(red: 0, green: 0, blue: 0, alpha: 0),
                        cornerRadius: 0
                    )
                ),
            ]
        )
        let design = LoupeDesignDocument(
            frame: LoupeDesignFrame(name: "Admin", width: 1200, height: 800),
            nodes: []
        )

        let comparison = LoupeDesignComparator.compare(snapshot: snapshot, design: design)

        #expect(!comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode && issue.testID == "admin.background"
        })
        #expect(comparison.issues.contains { issue in
            issue.kind == .unexpectedAppNode && issue.testID == "admin.unexpected.group"
        })
    }
}
