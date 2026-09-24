import Foundation
import Testing
@testable import LoupeCLI

struct OfflineUIOutputOptionsTests {
    @Test func liveAccessibilityAcceptsHiddenNodesAndOutputWithoutLosingRuntimeSelection() throws {
        let options = try LiveAccessibilityOptions([
            "--host", "http://127.0.0.1:9000", "--bundle-id", "test.app",
            "--include-hidden", "--output", "/tmp/accessibility.json",
        ])
        #expect(options.includeHidden)
        #expect(options.runtime.bundleID == "test.app")
        #expect(options.runtime.host.absoluteString == "http://127.0.0.1:9000")
        #expect(options.runtime.outputURL?.path == "/tmp/accessibility.json")
    }
    @Test func compactSnapshotModeAcceptsOutputPath() throws {
        let options = try CompactOptions([
            "/tmp/loupe-snapshot.json",
            "--output", "/tmp/loupe-compact.json",
        ])

        #expect(options.snapshotURL.path == "/tmp/loupe-snapshot.json")
        #expect(options.outputURL?.path == "/tmp/loupe-compact.json")
    }

    @Test func compactSnapshotModeRejectsRuntimeSelection() {
        #expect(throws: (any Error).self) {
            try CompactOptions([
                "/tmp/loupe-snapshot.json",
                "--host", "http://127.0.0.1:28823",
            ])
        }
    }

    @Test func accessibilitySnapshotModeAcceptsOutputPathAndIncludeHidden() throws {
        let options = try AccessibilityOptions([
            "/tmp/loupe-snapshot.json",
            "--include-hidden",
            "--output", "/tmp/loupe-accessibility.json",
        ])

        #expect(options.snapshotURL.path == "/tmp/loupe-snapshot.json")
        #expect(options.includeHidden)
        #expect(options.outputURL?.path == "/tmp/loupe-accessibility.json")
    }
}
