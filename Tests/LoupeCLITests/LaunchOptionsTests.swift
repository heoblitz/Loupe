@testable import LoupeCLI
import Testing

@Suite struct LaunchOptionsTests {
    @Test func udidAliasesDevice() throws {
        let options = try LaunchOptions([
            "--bundle-id", "com.apple.Preferences",
            "--udid", "SIM-UDID",
        ])

        #expect(options.device == "SIM-UDID")
    }
}
