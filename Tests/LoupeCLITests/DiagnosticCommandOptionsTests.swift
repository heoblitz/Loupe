@testable import LoupeCLI
import Foundation
import LoupeCore
import Testing

@Suite struct DiagnosticCommandOptionsTests {
    @Test func parsesRoleSelector() throws {
        let options = try DiagnosticRuntimeOptions(["--role", "button"], usage: "usage")

        #expect(try options.selectorQuery() == "role=button")
    }

    @Test func parsesTypedBooleanValueWithoutPositionalValue() throws {
        let options = try DiagnosticRuntimeOptions(["--bool", "false"], usage: "usage")

        #expect(options.value == .bool(false))
    }

    @Test func parsesTypedNumberValueWithoutPositionalValue() throws {
        let options = try DiagnosticRuntimeOptions(["--number", "42"], usage: "usage")

        #expect(options.value == .int(42))
    }

    @Test func referenceGraphOptionsKeepTargetSeparateFromRuntimeOptions() throws {
        let options = try LoupeCLI.ReferenceGraphOptions([
            "DeviceActuationService",
            "--host", "http://127.0.0.1:9876",
            "--udid", "SIM-1",
            "--output", "/tmp/loupe-reference-graph.json"
        ], commandName: "object-graph")

        #expect(options.target == "DeviceActuationService")
        #expect(options.runtimeOptions.host.absoluteString == "http://127.0.0.1:9876")
        #expect(options.runtimeOptions.udid == "SIM-1")
        #expect(options.runtimeOptions.outputURL?.path == "/tmp/loupe-reference-graph.json")
    }

    @Test func referenceGraphOptionsParseExplicitTargetWithoutTreatingOptionValuesAsTargets() throws {
        let options = try LoupeCLI.ReferenceGraphOptions([
            "--output", "/tmp/loupe-reference-graph.json",
            "--target", "DeviceActuationService",
            "--host", "http://127.0.0.1:9876"
        ], commandName: "heap")

        #expect(options.target == "DeviceActuationService")
        #expect(options.runtimeOptions.host.absoluteString == "http://127.0.0.1:9876")
        #expect(options.runtimeOptions.outputURL?.path == "/tmp/loupe-reference-graph.json")
    }

    @Test func referenceGraphBuildsOwnersNodesEdgesAndUsesDeterministicOrdering() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let refs = [
            LoupeReferenceEvidence(
                id: "edge-z",
                timestamp: timestamp,
                owner: "DeviceActuationService",
                target: "RuntimeDispatcher",
                kind: "strong",
                label: "dispatcher"
            ),
            LoupeReferenceEvidence(
                id: "edge-b",
                timestamp: timestamp,
                owner: "WorkbenchController",
                target: "DeviceActuationService",
                kind: "strong",
                label: "service"
            ),
            LoupeReferenceEvidence(
                id: "edge-a",
                timestamp: timestamp,
                owner: "WorkbenchController",
                target: "DeviceActuationService",
                kind: "strong",
                label: "service"
            ),
            LoupeReferenceEvidence(
                id: "edge-hidden",
                timestamp: timestamp,
                owner: "UnrelatedOwner",
                target: "UnrelatedTarget",
                kind: "strong",
                label: "ignored"
            )
        ]

        let graph = LoupeCLI.makeReferenceGraph(from: refs, target: "DeviceActuationService")

        #expect(graph.target == "DeviceActuationService")
        #expect(graph.evidenceKind == "app-authored-reference-evidence")
        #expect(graph.edges.map(\.evidenceID) == ["edge-z", "edge-a", "edge-b"])
        #expect(graph.owners.map(\.evidenceID) == ["edge-a", "edge-b"])
        #expect(graph.nodes.first { $0.name == "DeviceActuationService" }?.incomingCount == 2)
        #expect(graph.nodes.first { $0.name == "DeviceActuationService" }?.outgoingCount == 1)
        #expect(graph.nodes.contains { $0.name == "UnrelatedOwner" } == false)
    }
}
