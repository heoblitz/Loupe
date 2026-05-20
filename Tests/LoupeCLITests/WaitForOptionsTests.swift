@testable import LoupeCLI
import Testing

@Suite struct WaitForOptionsTests {
    @Test func defaultsToCurrentRuntimeResolution() throws {
        let options = try WaitForOptions([
            "--test-id", "example.status",
            "--key", "text",
            "--equals", "Ready",
        ], mode: .value)

        #expect(options.host.absoluteString == "http://127.0.0.1:8765")
        #expect(options.hostWasExplicit == false)
        #expect(options.udid == nil)
        #expect(options.bundleID == nil)
    }

    @Test func parsesRuntimeSelection() throws {
        let options = try WaitForOptions([
            "--bundle-id", "dev.loupe.example",
            "--udid", "SIM-UDID",
            "--test-id", "example.status",
            "--timeout", "3",
            "--output", "/tmp/loupe-wait.json",
        ], mode: .visible)

        #expect(options.bundleID == "dev.loupe.example")
        #expect(options.udid == "SIM-UDID")
        #expect(options.timeout == 3)
        #expect(options.outputURL?.path == "/tmp/loupe-wait.json")
        #expect(options.hostWasExplicit == false)
    }

    @Test func explicitHostBypassesRuntimeSelection() throws {
        let options = try WaitForOptions([
            "--host", "http://127.0.0.1:30632",
            "--ref", "n1",
        ], mode: .gone)

        #expect(options.host.absoluteString == "http://127.0.0.1:30632")
        #expect(options.hostWasExplicit == true)
    }

    @Test func valueModeSuggestsKeyEqualsSyntaxForBareValue() {
        do {
            _ = try WaitForOptions([
                "--test-id", "example.status",
                "Done",
            ], mode: .value)
            #expect(Bool(false), "Expected wait-for-value parsing to fail")
        } catch {
            #expect(String(describing: error).contains("--key <path> --equals <value>"))
        }
    }
}
