@testable import LoupeCLI
import Testing

@Suite struct InspectOptionsTests {
    @Test func parsesFieldFilter() throws {
        let options = try InspectOptions([
            "/tmp/snapshot.json",
            "--ref", "n1",
            "--fields", "node,children",
        ])

        #expect(options.fields == ["node", "children"])
    }

    @Test func nodeOnlyIsFieldShortcut() throws {
        let options = try InspectOptions([
            "/tmp/snapshot.json",
            "--ref", "n1",
            "--node-only",
        ])

        #expect(options.fields == ["node"])
    }
}
