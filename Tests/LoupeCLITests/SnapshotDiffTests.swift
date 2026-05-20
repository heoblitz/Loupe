@testable import LoupeCLI
import Foundation
import LoupeCore
import Testing

@Suite struct SnapshotDiffTests {
    @Test func reportsStyleColorChanges() {
        let before = snapshot(
            id: "before",
            node: node(style: LoupeStyle())
        )
        let after = snapshot(
            id: "after",
            node: node(style: LoupeStyle(backgroundColor: LoupeColor(red: 1, green: 0.894, blue: 0.902, alpha: 1)))
        )

        let diff = LoupeCLI.snapshotDiff(before: before, after: after)

        #expect(diff.changed.count == 1)
        #expect(diff.changed[0].changes.contains { change in
            change.field == "style.backgroundColor"
                && change.before == nil
                && change.after == "rgba(1,0.894,0.902,1)"
        })
    }

    private func snapshot(id: String, node: LoupeNode) -> LoupeSnapshot {
        LoupeSnapshot(
            id: id,
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: [node.ref],
            nodes: [node.ref: node]
        )
    }

    private func node(style: LoupeStyle?) -> LoupeNode {
        LoupeNode(
            ref: "n1",
            parentRef: nil,
            kind: .view,
            typeName: "UIView",
            testID: "settings.cell.background",
            frame: LoupeRect(x: 0, y: 100, width: 390, height: 44),
            isVisible: true,
            isEnabled: true,
            isInteractive: false,
            style: style
        )
    }
}
