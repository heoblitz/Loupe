import Foundation
import LoupeCore
import Testing
@testable import LoupeCLI

struct RuntimeObservationTests {
    @Test func explicitBundleRejectsAReusedHostForAnotherApp() throws {
        let state = LoupeRuntimeState(identity: LoupeRuntimeIdentity(bundleIdentifier: "actual.app", processIdentifier: 1))
        try LoupeCLI.validateBundleIdentity(state: state, expectedBundleID: "actual.app")
        #expect(throws: (any Error).self) {
            try LoupeCLI.validateBundleIdentity(state: state, expectedBundleID: "other.app")
        }
    }
    @Test func liveAccessibilityQueryFindsNodesAbsentFromViewSnapshot() throws {
        let screen = LoupeScreen(size: LoupeSize(width: 400, height: 800), scale: 2)
        let node = LoupeAccessibilityNode(ref: "ax-native", sourceRef: "native-owner", role: "button",
            label: "Native button", testID: "native.button", isVisible: true, isEnabled: true, isInteractive: true)
        let tree = LoupeAccessibilityTree(snapshotID: "native", screen: screen, rootRefs: [node.ref], nodes: [node.ref: node])
        let options = try QueryOptions(["--tree", "accessibility", "--test-id", "native.button"])
        let result = try LoupeCLI.queryResultData(snapshot: nil, options: options, accessibilityTree: tree)
        #expect(result.count == 1)
        #expect(String(decoding: result.data, as: UTF8.self).contains("ax-native"))
        let snapshot = LoupeSnapshot(id: "view", capturedAt: Date(), screen: screen, rootRefs: [], nodes: [:])
        #expect(try LoupeCLI.queryResultData(snapshot: snapshot, options: options).count == 0)
    }

    @Test(arguments: [400, 401, 429, 500, 503])
    func serverErrorsDoNotFallBack(status: Int) throws {
        let response = try #require(HTTPURLResponse(url: URL(string: "http://localhost/accessibility")!,
            statusCode: status, httpVersion: nil, headerFields: nil))
        #expect(throws: (any Error).self) {
            try LoupeCLI.decodeAccessibilityResponse(data: Data(), response: response)
        }
    }

    @Test func onlyMissingEndpointAllowsFallbackAndMalformedSuccessFails() throws {
        let url = URL(string: "http://localhost/accessibility")!
        let missing = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
        #expect(try LoupeCLI.decodeAccessibilityResponse(data: Data(), response: missing) == nil)
        let success = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        #expect(throws: (any Error).self) {
            try LoupeCLI.decodeAccessibilityResponse(data: Data("{}".utf8), response: success)
        }
    }
}
