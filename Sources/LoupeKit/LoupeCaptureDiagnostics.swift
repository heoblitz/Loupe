#if canImport(UIKit)
import Foundation

/// Opt-in progress for diagnosing a main-thread capture that outlives its
/// client deadline. Keep this on disk so a stuck runtime cannot hide the phase.
@MainActor
enum LoupeCaptureDiagnostics {
    private static let enabled = ProcessInfo.processInfo.environment["LOUPE_CAPTURE_DIAGNOSTICS"] == "1"
    private static let outputURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first?.appendingPathComponent("loupe-capture-progress.txt")
    private static var remainingLines = 8192
    private static var output: FileHandle?

    static func record(_ phase: String, object: AnyObject? = nil) {
        guard enabled, let outputURL else { return }
        if output == nil {
            _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            output = try? FileHandle(forWritingTo: outputURL)
        }
        guard let output else { return }
        if phase == "snapshot.begin" {
            remainingLines = 8192
            try? output.truncate(atOffset: 0)
            try? output.seek(toOffset: 0)
        }
        guard remainingLines > 0 else { return }
        remainingLines -= 1
        let typeName = object.map { _typeName(type(of: $0), qualified: true).prefix(512) } ?? ""
        let line = "\(Date().timeIntervalSince1970) \(phase) \(typeName)\n"
        try? output.write(contentsOf: Data(line.utf8))
    }
}
#endif
