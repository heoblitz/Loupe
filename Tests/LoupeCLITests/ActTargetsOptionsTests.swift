@testable import LoupeCLI
import Foundation
import Testing

@Suite struct ActTargetsOptionsTests {
    @Test func omittedHostRemainsUnspecified() throws {
        let options = try ActTargetsOptions([])

        #expect(options.host == nil)
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
