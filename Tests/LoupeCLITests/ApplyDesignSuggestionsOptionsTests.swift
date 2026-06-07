@testable import LoupeCLI
import LoupeCLIModel
import LoupeCore
import Testing

@Suite struct ApplyDesignSuggestionsOptionsTests {
    @Test func parsesRuntimeAndSelectionOptions() throws {
        let options = try ApplyDesignSuggestionsOptions([
            "/tmp/compare.json",
            "--host", "http://127.0.0.1:9999",
            "--snapshot", "/tmp/report/snapshot.json",
            "--output-dir", "/tmp/design-probes",
            "--max", "2",
            "--properties", "textColor,cornerRadius",
            "--dry-run",
        ])

        #expect(options.compareURL.path == "/tmp/compare.json")
        #expect(options.host.absoluteString == "http://127.0.0.1:9999")
        #expect(options.hostWasExplicit)
        #expect(options.snapshotURL?.path == "/tmp/report/snapshot.json")
        #expect(options.outputDirectory.path == "/tmp/design-probes")
        #expect(options.maxSuggestions == 2)
        #expect(options.allowedProperties == ["textColor", "cornerRadius"])
        #expect(options.propertyFilterWasExplicit)
        #expect(options.dryRun)
    }

    @Test func defaultSelectedSuggestionsPreferScalarChangesBeforeFrames() throws {
        let options = try ApplyDesignSuggestionsOptions([
            "/tmp/compare.json",
            "--max", "3",
        ])
        let suggestions = [
            suggestion(ref: "n1", property: "frame"),
            suggestion(ref: "n2", property: "text"),
            suggestion(ref: "n3", property: "backgroundColor"),
            suggestion(ref: "n4", property: "frame"),
            suggestion(ref: "n5", property: "cornerRadius"),
        ]

        let selected = options.selectedSuggestions(from: suggestions)

        #expect(selected.map(\.ref) == ["n2", "n3", "n5"])
    }

    @Test func defaultSelectionIsSmallEnoughForPreRebuildProbe() throws {
        let options = try ApplyDesignSuggestionsOptions([
            "/tmp/compare.json",
        ])
        let suggestions = [
            suggestion(ref: "n1", property: "frame"),
            suggestion(ref: "n2", property: "text"),
            suggestion(ref: "n3", property: "backgroundColor"),
            suggestion(ref: "n4", property: "cornerRadius"),
            suggestion(ref: "n5", property: "fontSize"),
        ]

        let selected = options.selectedSuggestions(from: suggestions)

        #expect(options.maxSuggestions == 3)
        #expect(selected.map(\.ref) == ["n2", "n3", "n4"])
    }

    @Test func defaultSelectedSuggestionsLimitFrameProbesWhenScalarChangesExist() throws {
        let options = try ApplyDesignSuggestionsOptions([
            "/tmp/compare.json",
            "--max", "4",
        ])
        let suggestions = [
            suggestion(ref: "n1", property: "frame"),
            suggestion(ref: "n2", property: "text"),
            suggestion(ref: "n3", property: "frame"),
            suggestion(ref: "n4", property: "frame"),
        ]

        let selected = options.selectedSuggestions(from: suggestions)

        #expect(selected.map(\.ref) == ["n2", "n1"])
    }

    @Test func selectedSuggestionsUsePropertyFilterAndLimit() throws {
        let options = try ApplyDesignSuggestionsOptions([
            "/tmp/compare.json",
            "--max", "2",
            "--properties", "textColor,frame",
        ])
        let suggestions = [
            suggestion(ref: "n1", property: "textColor"),
            suggestion(ref: "n2", property: "cornerRadius"),
            suggestion(ref: "n3", property: "frame"),
            suggestion(ref: "n4", property: "textColor"),
        ]

        let selected = options.selectedSuggestions(from: suggestions)

        #expect(selected.map(\.ref) == ["n1", "n3"])
    }

    @Test func rejectsEmptyPropertyFilter() throws {
        #expect(throws: CLIError.self) {
            _ = try ApplyDesignSuggestionsOptions([
                "/tmp/compare.json",
                "--properties", ",,,",
            ])
        }
    }

    @Test func changedCountTreatsEquivalentNumericEffectiveValuesAsChanged() {
        let node = LoupeNode(
            ref: "n1",
            parentRef: nil,
            kind: .view,
            typeName: "UIView",
            isVisible: true,
            isEnabled: true,
            isInteractive: false
        )
        let response = LoupeMutationResponse(
            property: "cornerRadius",
            selector: LoupeMutationSelector(kind: .ref, value: "n1"),
            value: .int(22),
            target: LoupeQueryResult(node: node),
            before: node,
            after: node,
            requested: .int(22),
            effective: .double(22),
            changed: false,
            warning: "stale runtime warning",
            snapshotID: "snapshot"
        )

        #expect(LoupeCLI.mutationResponseChanged(response))
    }

    @Test func designSuggestionMutationSelectorPrefersTestID() {
        let selector = LoupeCLI.mutationSelector(for: suggestion(
            ref: "n1",
            testID: "checkout.totalLabel",
            property: "textColor"
        ))

        #expect(selector.kind == .testID)
        #expect(selector.value == "checkout.totalLabel")
    }

    @Test func designSuggestionMutationSelectorFallsBackToRef() {
        let selector = LoupeCLI.mutationSelector(for: suggestion(
            ref: "n1",
            property: "textColor"
        ))

        #expect(selector.kind == .ref)
        #expect(selector.value == "n1")
    }

    private func suggestion(
        ref: String,
        testID: String? = nil,
        property: String
    ) -> LoupeDesignMutationSuggestion {
        LoupeDesignMutationSuggestion(
            issueKind: .textColorDelta,
            designID: "design.\(ref)",
            designName: "Node \(ref)",
            ref: ref,
            testID: testID,
            property: property,
            value: .color(LoupeColor(red: 1, green: 0, blue: 0, alpha: 1)),
            valueType: "color",
            valueLabel: "#ff0000",
            reason: "test"
        )
    }
}
