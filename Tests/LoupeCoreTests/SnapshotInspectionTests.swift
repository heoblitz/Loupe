import Foundation
import Testing
@testable import LoupeCore

struct SnapshotInspectionTests {
    @Test func inspectReturnsFullNodeAndLocalTreeContext() throws {
        let snapshot = InspectionSnapshotFixture.makeSnapshot()

        let inspection = try #require(
            LoupeSnapshotInspector.inspect(.testID("components.switch"), in: snapshot)
        )

        #expect(inspection.node.testID == "components.switch")
        #expect(inspection.node.uiKit?.className == "UISwitch")
        #expect(inspection.node.uiKit?.switchControl?.isOn == true)
        #expect(inspection.parent?.testID == "components.row")
        #expect(inspection.siblings.map { $0.testID } == ["components.label"])
    }

    @Test func subtreeReturnsBoundedDescendants() throws {
        let snapshot = InspectionSnapshotFixture.makeSnapshot()

        let subtree = try #require(
            LoupeSnapshotInspector.subtree(.testID("components.row"), in: snapshot, maxDepth: 1)
        )

        #expect(subtree.root.testID == "components.row")
        #expect(Set(subtree.nodes.keys) == Set(["row", "label", "switch"]))
    }

    @Test func inspectPreservesScrollViewMetricsForGestureVerification() throws {
        let snapshot = InspectionSnapshotFixture.makeSnapshot()

        let inspection = try #require(
            LoupeSnapshotInspector.inspect(.testID("bottomSheet.results"), in: snapshot)
        )
        let scrollView = try #require(inspection.node.uiKit?.scrollView)

        #expect(inspection.node.role == "scrollView")
        #expect(inspection.node.frame?.height == 420)
        #expect(scrollView.contentOffset == LoupePoint(x: 0, y: 240))
        #expect(scrollView.contentSize == LoupeSize(width: 350, height: 1_240))
        #expect(scrollView.adjustedContentInset.bottom == 34)
        #expect(scrollView.isScrollEnabled)
        #expect(scrollView.alwaysBounceVertical)
        #expect(!scrollView.alwaysBounceHorizontal)
        #expect(scrollView.contentSize.height > inspection.node.frame!.height)
    }

}
