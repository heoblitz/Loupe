import Foundation
import LoupeCore
import Testing

@Suite struct MutationTests {
    @Test func mutationRequestRoundTripsTypedValues() throws {
        let request = LoupeMutationRequest(
            selector: LoupeMutationSelector(kind: .testID, value: "example.card"),
            property: "backgroundColor",
            value: .color(LoupeColor(red: 1, green: 0.2, blue: 0.4, alpha: 1))
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(LoupeMutationRequest.self, from: data)

        #expect(decoded == request)
    }

    @Test func mutationReflectionKeepsHierarchyContextAndSourceCandidates() throws {
        let target = LoupeMutationNodeSummary(
            ref: "n3",
            typeName: "UIView",
            role: nil,
            testID: "example.card",
            frame: LoupeRect(x: 10, y: 20, width: 100, height: 60)
        )
        let reflection = LoupeMutationReflection(
            selector: LoupeMutationSelector(kind: .testID, value: "example.card"),
            property: "cornerRadius",
            value: .double(12),
            targetType: "UIView",
            testID: "example.card",
            before: target,
            after: target,
            targetMatchesHierarchy: true,
            hierarchy: LoupeMutationHierarchyContext(target: target),
            sourceCandidates: [
                LoupeMutationSourceCandidate(path: "ViewController.swift", line: 42, text: "card.accessibilityIdentifier = \"example.card\"")
            ]
        )

        let data = try JSONEncoder().encode(reflection)
        let decoded = try JSONDecoder().decode(LoupeMutationReflection.self, from: data)

        #expect(decoded == reflection)
    }

    @Test func mutationResponseKeepsBeforeAndAfterNodes() throws {
        let before = mutationNode(text: "Before")
        let after = mutationNode(text: "After")
        let response = LoupeMutationResponse(
            property: "text",
            selector: LoupeMutationSelector(kind: .testID, value: "example.label"),
            value: .string("After"),
            target: LoupeQueryResult(node: before),
            before: before,
            after: after,
            hierarchy: LoupeMutationHierarchyContext(target: LoupeMutationNodeSummary(ref: "n3", typeName: "UILabel")),
            snapshotID: "snapshot-2"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LoupeMutationResponse.self, from: data)

        #expect(decoded.property == "text")
        #expect(decoded.before.text == "Before")
        #expect(decoded.after.text == "After")
        #expect(decoded.hierarchy?.target.typeName == "UILabel")
    }

    @Test func constraintMutationResponseRoundTripsEffectiveState() throws {
        let before = LoupeUILayoutConstraintProperties(
            id: "c123",
            identifier: "button.height",
            firstItem: "UIButton#primary",
            firstAttribute: "height",
            relation: "equal",
            secondItem: nil,
            secondAttribute: "notAnAttribute",
            multiplier: 1,
            constant: 44,
            priority: 1000,
            isActive: true
        )
        let after = LoupeUILayoutConstraintProperties(
            id: "c123",
            identifier: "button.height",
            firstItem: "UIButton#primary",
            firstAttribute: "height",
            relation: "equal",
            secondItem: nil,
            secondAttribute: "notAnAttribute",
            multiplier: 1,
            constant: 56,
            priority: 999,
            isActive: true
        )
        let request = LoupeConstraintMutationRequest(id: "c123", constant: 56, priority: 999)
        let response = LoupeConstraintMutationResponse(
            id: "c123",
            before: before,
            after: after,
            requested: request,
            changed: true,
            snapshotID: "snapshot-constraints"
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(LoupeConstraintMutationResponse.self, from: data)

        #expect(decoded.id == "c123")
        #expect(decoded.before.constant == 44)
        #expect(decoded.after.constant == 56)
        #expect(decoded.effective.constant == 56)
        #expect(decoded.after.priority == 999)
        #expect(decoded.changed)
    }

    private func mutationNode(text: String) -> LoupeNode {
        LoupeNode(
            ref: "n3",
            parentRef: "n2",
            kind: .view,
            typeName: "UILabel",
            role: "staticText",
            testID: "example.label",
            text: text,
            frame: LoupeRect(x: 10, y: 20, width: 100, height: 30),
            isVisible: true,
            isEnabled: true,
            isInteractive: false
        )
    }
}
