@testable import LoupeCLI
import Foundation
import Testing

@Suite struct CaptureReportOptionsTests {
    @Test func parsesRuntimeAndOutputOptions() throws {
        let options = try CaptureReportOptions([
            "--bundle-id", "dev.loupe.example",
            "--udid", "SIM-1",
            "--output", "/tmp/report",
            "--screen-map-limit", "40",
            "--timeout", "3",
        ])

        #expect(options.bundleID == "dev.loupe.example")
        #expect(options.udid == "SIM-1")
        #expect(options.outputDirectory.path == "/tmp/report")
        #expect(options.screenMapLimit == 40)
        #expect(options.timeout == 3)
    }

    @Test func defaultsToCurrentRuntimeAndTemporaryReportDirectory() throws {
        let options = try CaptureReportOptions([])

        #expect(options.bundleID == nil)
        #expect(options.udid == nil)
        #expect(options.outputDirectory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(options.outputDirectory.lastPathComponent.hasPrefix("loupe-report-"))
        #expect(options.screenMapLimit == 120)
    }

    @Test func rejectsInvalidScreenMapLimit() {
        #expect(throws: (any Error).self) {
            _ = try CaptureReportOptions(["--screen-map-limit", "0"])
        }
    }
}
