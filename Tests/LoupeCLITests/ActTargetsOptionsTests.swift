@testable import LoupeCLI
import Foundation
import Testing

@Suite struct ActTargetsOptionsTests {
    @Test func omittedHostRemainsUnspecified() throws {
        let options = try ActTargetsOptions([])

        #expect(options.host == nil)
        #expect(!options.includeAll)
        #expect(!options.includeWeb)
    }

    @Test func allIncludesAuxiliaryTargets() throws {
        #expect(try ActTargetsOptions(["--all"]).includeAll)
        #expect(try ActTargetsOptions(["--include-web"]).includeWeb)
    }

    @Test func webSearchHasItsOwnDefaultDeadlineAndRespectsExplicitTimeout() throws {
        #expect(try ActTargetsOptions([]).timeout == 5)
        #expect(try ActTargetsOptions(["--include-web"]).timeout == 15)
        #expect(try ActTargetsOptions(["--timeout", "2", "--include-web"]).timeout == 2)
        #expect(try ActTargetsOptions(["--include-web", "--timeout", "3"]).timeout == 3)
        #expect(try RuntimeFetchOptions([], usage: "web", defaultTimeout: 15).timeout == 15)
        #expect(try RuntimeFetchOptions(["--timeout", "1"], usage: "web", defaultTimeout: 15).timeout == 1)
    }

    @Test func supportsBundleSelection() throws {
        #expect(try ActTargetsOptions(["--bundle-id", "test.app"]).bundleID == "test.app")
    }

    @Test func rejectsRemovedUnverifiedOption() {
        #expect(throws: (any Error).self) {
            _ = try ActTargetsOptions(["--include-unverified"])
        }
    }

    @Test func parsesExplicitHost() throws {
        let options = try ActTargetsOptions([
            "--host", "http://127.0.0.1:30632",
        ])

        #expect(options.host?.absoluteString == "http://127.0.0.1:30632")
    }

    @Test func optionalResolverPreservesExplicitHost() async throws {
        let explicitHost = try #require(URL(string: "http://127.0.0.1:30632"))

        let resolvedHost = try await LoupeCLI.resolvedRuntimeHost(
            requestedHost: explicitHost,
            udid: nil
        )

        #expect(resolvedHost == explicitHost)
    }
}
