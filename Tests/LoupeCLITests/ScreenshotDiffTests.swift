import CoreGraphics
import Foundation
import ImageIO
import LoupeCLIModel
import Testing
@testable import LoupeCLI

@Suite struct ScreenshotDiffTests {
    @Test func expiredNativeReadCannotReplacePreviousPixels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-late-frame-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let output = directory.appendingPathComponent("output.png")
        try writePNG([RGBA(red: 255, green: 0, blue: 0, alpha: 255)], width: 1, height: 1, to: source)
        let fresh = try Data(contentsOf: source)
        let previous = Data("previous evidence".utf8)
        try previous.write(to: output)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        #expect(throws: Error.self) {
            let frame = try SimulatorScreenshotCapture.nativeFrame(timeout: 0.05) {
                release.wait()
                defer { finished.signal() }
                return .png(fresh)
            }
            if case .png(let data) = frame { try SimulatorScreenshotCapture.publish(data, to: output) }
        }
        release.signal()
        #expect(finished.wait(timeout: .now() + 2) == .success)
        #expect(try Data(contentsOf: output) == previous)
    }

    @Test func malformedNativePNGPreservesPreviousOutput() throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-malformed-frame-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        let previous = Data("previous evidence".utf8)
        try previous.write(to: output)
        // An IEND marker alone must not be accepted as a decodable image.
        #expect(throws: Error.self) {
            try SimulatorScreenshotCapture.publish(Data([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]), to: output)
        }
        #expect(try Data(contentsOf: output) == previous)
    }

    @Test func completeNativePNGPublishesFreshPixels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-native-frame-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let output = directory.appendingPathComponent("output.png")
        try writePNG([RGBA(red: 255, green: 0, blue: 0, alpha: 255)], width: 1, height: 1, to: source)
        let fresh = try Data(contentsOf: source)
        let frame = try SimulatorScreenshotCapture.nativeFrame(timeout: 2) { .png(fresh) }
        guard case .png(let bytes) = frame else { Issue.record("Native read unexpectedly unsupported"); return }
        try SimulatorScreenshotCapture.publish(bytes, to: output)
        #expect(try Data(contentsOf: output) == fresh)
    }

    @Test func reusedActionTraceCannotPublishAPreviousCropOrFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-reused-trace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let crop = directory.appendingPathComponent("target-crop.png")
        try writePNG([RGBA(red: 0, green: 0, blue: 255, alpha: 255)], width: 1, height: 1, to: crop)
        let oldEvidence = ["after.png", "action-after.json", "action-failure.json", "error.json", "failure-logs.json"]
        for name in oldEvidence { try Data("previous action".utf8).write(to: directory.appendingPathComponent(name)) }
        let note = directory.appendingPathComponent("notes.txt")
        let preserved = Data("user notes".utf8)
        try preserved.write(to: note)
        try LoupeCLI.prepareNewActionTrace(directory)
        let state = directory.appendingPathComponent("after-snapshot.json")
        let completedState = Data("{\"counter\":2}".utf8)
        try completedState.write(to: state)
        #expect(try !LoupeCLI.finishPostActionScreenshot(.failure(CLIError("capture failed")), outputURL: directory.appendingPathComponent("after.png")))
        #expect(!FileManager.default.fileExists(atPath: crop.path))
        for name in oldEvidence { #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)) }
        #expect(try Data(contentsOf: state) == completedState)
        #expect(try Data(contentsOf: note) == preserved)
    }

    @Test func actionTraceDoesNotDeleteDirectoriesAtArtifactPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-trace-directory-\(UUID().uuidString)")
        let crop = directory.appendingPathComponent("target-crop.png")
        try FileManager.default.createDirectory(at: crop, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = crop.appendingPathComponent("notes.txt")
        try Data("preserve".utf8).write(to: note)
        #expect(throws: Error.self) { try LoupeCLI.prepareNewActionTrace(directory) }
        #expect(try String(contentsOf: note, encoding: .utf8) == "preserve")
    }

    @Test func completedActionRecordsAMissingScreenshotAndRemovesStalePixels() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-post-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("after.png")
        let state = directory.appendingPathComponent("after-snapshot.json")
        let completedState = Data("{\"counter\":2}".utf8)
        try completedState.write(to: state)
        try writePNG([RGBA(red: 0, green: 0, blue: 255, alpha: 255)], width: 1, height: 1, to: output)
        #expect(try !LoupeCLI.finishPostActionScreenshot(
            .failure(CLIError("simctl screenshot timed out after 10.0s")), outputURL: output
        ))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try Data(contentsOf: state) == completedState)
        let error = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("after.screenshot-error.json"))) as? [String: Any]
        #expect(error?["message"] as? String == "simctl screenshot timed out after 10.0s")
        #expect(error?["recordedAt"] != nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("action-failure.json").path))
        // Reusing the trace directory after a successful fresh capture must
        // not leave the previous diagnostic failure attached to the new image.
        try writePNG([RGBA(red: 255, green: 0, blue: 0, alpha: 255)], width: 1, height: 1, to: output)
        #expect(try LoupeCLI.finishPostActionScreenshot(.success(()), outputURL: output))
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("after.screenshot-error.json").path))
    }

    @Test func missingScreenshotCannotBeSilentlyAcceptedWhenItsErrorCannotBeRecorded() {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-missing-capture-directory-\(UUID().uuidString)/after.png")
        #expect(throws: Error.self) {
            try LoupeCLI.finishPostActionScreenshot(.failure(CLIError("capture failed")), outputURL: output)
        }
    }

    @Test func completeScreenshotReapsAChildStalledAfterWritingPNG() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-complete-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let temporary = directory.appendingPathComponent("fresh.png")
        let output = directory.appendingPathComponent("output.png")
        try writePNG([RGBA(red: 255, green: 0, blue: 0, alpha: 255)], width: 1, height: 1, to: source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-MFile::Copy", "-e", "$SIG{TERM}='IGNORE'; print STDERR qq(abcdefghijklmnopqrstuvwxyz0123456789\\n) x 10000; copy($ARGV[0], $ARGV[1]) or die $!; sleep 30", source.path, temporary.path]
        let started = Date()
        try SimulatorScreenshotCapture.run(process, temporaryURL: temporary, outputURL: output, timeout: 1)
        #expect(try Data(contentsOf: output) == Data(contentsOf: source))
        #expect(try Data(contentsOf: output.appendingPathExtension("stderr.log")).count == 370000)
        #expect(!process.isRunning)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func incompleteScreenshotCannotAcceptAPreviousOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-incomplete-capture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("fresh.png")
        let output = directory.appendingPathComponent("output.png")
        try writePNG([RGBA(red: 0, green: 0, blue: 255, alpha: 255)], width: 1, height: 1, to: output)
        let previous = try Data(contentsOf: output)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", "$SIG{TERM}='IGNORE'; open(my $f, '>', $ARGV[0]) or die $!; print $f pack('C*',137,80,78,71,13,10,26,10); close($f); sleep 30", temporary.path]
        #expect(throws: Error.self) {
            try SimulatorScreenshotCapture.run(process, temporaryURL: temporary, outputURL: output, timeout: 0.3)
        }
        #expect(try Data(contentsOf: output) == previous)
        #expect(!process.isRunning)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test func screenshotCropUsesTopLeftPixelCoordinates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("loupe-crop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let crop = directory.appendingPathComponent("crop.png")
        let expected = directory.appendingPathComponent("expected.png")
        let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
        let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
        try writePNG([red, blue, red, red], width: 2, height: 2, to: source)
        try writePNG([blue], width: 1, height: 1, to: expected)
        try ScreenshotCropper.write(source: source, rect: CGRect(x: 1, y: 0, width: 1, height: 1), output: crop)
        let diff = try ScreenshotDiffer.diff(before: expected, after: crop)
        #expect(diff.dimensionsMatch)
        #expect(diff.changedPixels == 0)
    }

    @Test func screenshotDifferReportsChangedPixels() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-screenshot-diff-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let beforeURL = directory.appendingPathComponent("before.png")
        let afterURL = directory.appendingPathComponent("after.png")
        try writePNG(
            [
                RGBA(red: 255, green: 0, blue: 0, alpha: 255),
                RGBA(red: 0, green: 255, blue: 0, alpha: 255),
            ],
            width: 2,
            height: 1,
            to: beforeURL
        )
        try writePNG(
            [
                RGBA(red: 255, green: 0, blue: 0, alpha: 255),
                RGBA(red: 0, green: 0, blue: 255, alpha: 255),
            ],
            width: 2,
            height: 1,
            to: afterURL
        )

        let diff = try ScreenshotDiffer.diff(before: beforeURL, after: afterURL)

        #expect(diff.beforeSize == LoupeScreenshotPixelSize(width: 2, height: 1))
        #expect(diff.afterSize == LoupeScreenshotPixelSize(width: 2, height: 1))
        #expect(diff.dimensionsMatch)
        #expect(diff.comparedPixels == 2)
        #expect(diff.changedPixels == 1)
        #expect(diff.changedPixelRatio == 0.5)
        #expect(diff.maxColorDelta > 0)
    }

    @Test func traceNotesFlagLargeVisualOnlyChanges() {
        let notes = LoupeCLI.traceNotes(
            diff: LoupeSnapshotDiff(
                beforeSnapshotID: "before",
                afterSnapshotID: "after",
                appeared: [],
                disappeared: [],
                changed: []
            ),
            screenshotDiff: screenshotDiff(changedPixelRatio: 0.98)
        )

        #expect(notes.count == 1)
        #expect(notes[0].contains("large screenshot change"))
    }

    @Test func traceNotesSkipWhenSnapshotAlsoChangedSubstantially() {
        let notes = LoupeCLI.traceNotes(
            diff: LoupeSnapshotDiff(
                beforeSnapshotID: "before",
                afterSnapshotID: "after",
                appeared: (0..<6).map { index in
                    LoupeNodeDiffSummary(
                        key: "node\(index)",
                        ref: "n\(index)",
                        typeName: "UIView",
                        role: nil,
                        testID: nil,
                        text: nil,
                        frame: nil
                    )
                },
                disappeared: [],
                changed: []
            ),
            screenshotDiff: screenshotDiff(changedPixelRatio: 0.98)
        )

        #expect(notes.isEmpty)
    }

    @Test func traceNotesTreatHiddenDiffAsMinimalSnapshotChange() {
        let notes = LoupeCLI.traceNotes(
            diff: LoupeSnapshotDiff(
                beforeSnapshotID: "before",
                afterSnapshotID: "after",
                appeared: (0..<6).map { index in
                    LoupeNodeDiffSummary(
                        key: "hidden\(index)",
                        ref: "n\(index)",
                        typeName: "UIView",
                        role: nil,
                        testID: nil,
                        text: nil,
                        frame: nil,
                        isVisible: false
                    )
                },
                disappeared: [],
                changed: []
            ),
            screenshotDiff: screenshotDiff(changedPixelRatio: 0.98)
        )

        #expect(notes.count == 1)
    }

    private struct RGBA {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8
    }

    private func writePNG(_ pixels: [RGBA], width: Int, height: Int, to url: URL) throws {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for pixel in pixels {
            bytes.append(pixel.red)
            bytes.append(pixel.green)
            bytes.append(pixel.blue)
            bytes.append(pixel.alpha)
        }

        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw TestImageError(message: "Could not create test image data provider")
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw TestImageError(message: "Could not create test image")
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw TestImageError(message: "Could not create test PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError(message: "Could not write test PNG")
        }
    }

    private struct TestImageError: Error {
        var message: String
    }

    private func screenshotDiff(changedPixelRatio: Double) -> LoupeScreenshotDiffSummary {
        LoupeScreenshotDiffSummary(
            beforePath: "/tmp/before.png",
            afterPath: "/tmp/after.png",
            beforeSize: LoupeScreenshotPixelSize(width: 10, height: 10),
            afterSize: LoupeScreenshotPixelSize(width: 10, height: 10),
            dimensionsMatch: true,
            comparedPixels: 100,
            changedPixels: Int(changedPixelRatio * 100),
            changedPixelRatio: changedPixelRatio,
            meanColorDelta: 10,
            maxColorDelta: 255
        )
    }
}
