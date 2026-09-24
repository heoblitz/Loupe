import Foundation

enum TreeOutput {
    /// A display budget only. Full snapshot data remains available for inspection.
    static func bounded(_ output: String, limit: Int?) -> String {
        guard let limit else { return output }
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        var shortened = false
        var shown = lines.prefix(limit).map { line -> String in
            guard line.count > 240 else { return String(line) }
            shortened = true
            return String(line.prefix(239)) + "…"
        }
        let omitted = max(0, lines.count - limit)
        if omitted > 0 || shortened {
            shown.append("[omitted \(omitted) lines\(shortened ? "; long lines shortened" : ""); use --all for full output or --ref to focus]")
        }
        return shown.joined(separator: "\n")
    }
}
