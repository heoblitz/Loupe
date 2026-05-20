@testable import LoupeCLI
import Foundation
import LoupeCore
import Testing

@Suite struct BatchMutationPlannerTests {
    @Test func parsesSpaceSeparatedColorSequence() throws {
        let options = try BatchMutationOptions([
            "--refs", "n1,n2",
            "backgroundColor",
            "--colors", "FFE4E6_1", "255,232,204,1", "1,0.894,0.902,1",
        ])

        #expect(options.values.count == 3)
    }

    @Test func parsesNumericBatchValue() throws {
        let options = try BatchMutationOptions([
            "--refs", "n1,n2",
            "alpha",
            "--number", "0.5",
        ])

        #expect(options.values == [.double(0.5)])
    }

    @Test func plansTypeNameMatchesInFrameOrderWithOptionalChildRefs() throws {
        let options = try BatchMutationOptions([
            "--type-name", "ListCollectionViewCell",
            "backgroundColor",
            "--colors", "#111111", "#222222",
            "--include-children", "2",
        ])
        let snapshot = LoupeSnapshot(
            id: "snapshot",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "cell2": Self.cell("cell2", y: 200, children: ["cell2-bg", "cell2-content", "cell2-label"]),
                "cell1": Self.cell("cell1", y: 100, children: ["cell1-bg", "cell1-content"]),
                "hidden": Self.cell("hidden", y: 50, visible: false, children: []),
                "label": LoupeNode(
                    ref: "label",
                    parentRef: nil,
                    kind: .view,
                    typeName: "UILabel",
                    frame: LoupeRect(x: 0, y: 0, width: 10, height: 10),
                    isVisible: true,
                    isEnabled: true,
                    isInteractive: false
                ),
            ]
        )

        let plan = BatchMutationPlanner.makePlan(snapshot: snapshot, options: options)

        #expect(plan.map { $0.targetRef } == ["cell1", "cell2"])
        #expect(plan[0].mutationRefs == ["cell1", "cell1-bg", "cell1-content"])
        #expect(plan[1].mutationRefs == ["cell2", "cell2-bg", "cell2-content"])
    }

    @Test func refsPreserveFilterAndYRange() throws {
        let options = try BatchMutationOptions([
            "--refs", "cell1,cell2",
            "--y-range", "150,250",
            "alpha",
            "--value", "0.5",
        ])
        let snapshot = LoupeSnapshot(
            id: "snapshot",
            capturedAt: Date(timeIntervalSince1970: 0),
            screen: LoupeScreen(size: LoupeSize(width: 390, height: 844), scale: 3),
            rootRefs: ["root"],
            nodes: [
                "cell1": Self.cell("cell1", y: 100, children: []),
                "cell2": Self.cell("cell2", y: 200, children: []),
            ]
        )

        let plan = BatchMutationPlanner.makePlan(snapshot: snapshot, options: options)

        #expect(plan.map { $0.targetRef } == ["cell2"])
    }

    private static func cell(
        _ ref: String,
        y: Double,
        visible: Bool = true,
        children: [String]
    ) -> LoupeNode {
        LoupeNode(
            ref: ref,
            parentRef: nil,
            kind: .view,
            typeName: "ListCollectionViewCell",
            frame: LoupeRect(x: 16, y: y, width: 370, height: 52),
            isVisible: visible,
            isEnabled: true,
            isInteractive: true,
            children: children
        )
    }
}
