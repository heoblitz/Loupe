import Foundation
import LoupeCLIModel
import LoupeCore
import LoupeHID
#if canImport(Darwin)
import Darwin
#endif

@main
struct LoupeCLI {
    static func main() async {
        do {
            try await runMain()
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }

    private static func runMain() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty {
            printSummaryHelp()
            return
        }

        let command = arguments.removeFirst()

        if command == "help" {
            if let deprecatedCommand = arguments.first,
               let replacement = deprecatedCommandReplacement(deprecatedCommand) {
                printDeprecatedCommandWarning(command: deprecatedCommand, replacement: replacement)
                printCommandHelp(replacement)
                return
            }
            printCommandHelp(arguments)
            return
        }

        if command != "--help", command != "-h", arguments.contains("--help") || arguments.contains("-h") {
            if let replacement = deprecatedCommandReplacement(command) {
                printDeprecatedCommandWarning(command: command, replacement: replacement)
                printCommandHelp(replacement)
                return
            }
            printCommandHelp(helpPath(command: command, arguments: arguments))
            return
        }

        switch command {
        case "doctor":
            try doctor(arguments)
        case "app":
            try await app(arguments)
        case "debug":
            try await debug(arguments)
        case "act":
            try await act(arguments)
        case "ui":
            try await ui(arguments)
        case "injector-path":
            try injectorPath(arguments)
        case "skills":
            try skills(arguments)
        case "version", "--version":
            printVersion()
        case "--help", "-h":
            printHelp()
        default:
            if try await runDeprecatedTopLevelCommand(command, arguments: arguments) {
                return
            }
            throw CLIError("Unknown command: \(command)")
        }
    }

    static func compact(_ arguments: [String]) throws {
        let options = try CompactOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
        let observation = LoupeObservationCompactor.compact(LoupeSnapshotContext(snapshot: snapshot))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try write(data: encoder.encode(observation), outputURL: options.outputURL)
    }

    static func screenMap(_ arguments: [String]) async throws {
        let options = try ScreenMapOptions(arguments)
        let snapshot: LoupeSnapshot
        if let snapshotURL = options.snapshotURL {
            snapshot = try decodeSnapshot(from: snapshotURL)
        } else {
            let host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid,
                bundleID: options.bundleID
            )
            if let udid = options.udid {
                try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
            }
            snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        }

        let context = LoupeSnapshotContext(snapshot: snapshot)
        let map = LoupeScreenMapper.map(
            context,
            options: LoupeScreenMapOptions(
                includeHidden: options.includeHidden,
                includeContainers: options.includeContainers,
                maxElements: options.maxElements
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        FileHandle.standardOutput.write(try encoder.encode(map))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func captureReport(_ arguments: [String]) async throws {
        let options = try CaptureReportOptions(arguments)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }

        try FileManager.default.createDirectory(
            at: options.outputDirectory,
            withIntermediateDirectories: true
        )

        let runtimeState = try? await fetchRuntimeState(host: host, timeout: options.timeout)
        let snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        let accessibilityTree = try await fetchAccessibilityTree(
            host: host,
            fallbackSnapshot: snapshot,
            timeout: options.timeout
        )
        let context = LoupeSnapshotContext(snapshot: snapshot)
        let compact = LoupeObservationCompactor.compact(context)
        let screenMap = LoupeScreenMapper.map(
            context,
            options: LoupeScreenMapOptions(maxElements: options.screenMapLimit)
        )
        let audit = LoupeLayoutAuditor.audit(snapshot)
        let scrollViews = captureReportScrollViews(snapshot)

        let screenshotURL = options.outputDirectory.appendingPathComponent("screenshot.png")
        let snapshotURL = options.outputDirectory.appendingPathComponent("snapshot.json")
        let screenMapURL = options.outputDirectory.appendingPathComponent("screen-map.json")
        let accessibilityURL = options.outputDirectory.appendingPathComponent("accessibility.json")
        let compactURL = options.outputDirectory.appendingPathComponent("compact.json")
        let auditURL = options.outputDirectory.appendingPathComponent("audit.json")
        let runtimeURL = options.outputDirectory.appendingPathComponent("runtime.json")
        let logsURL = options.outputDirectory.appendingPathComponent("logs.json")
        let summaryURL = options.outputDirectory.appendingPathComponent("summary.json")
        let summaryMarkdownURL = options.outputDirectory.appendingPathComponent("summary.md")

        try writeJSON(snapshot, to: snapshotURL)
        try writeJSON(screenMap, to: screenMapURL)
        try writeJSON(accessibilityTree, to: accessibilityURL)
        try writeJSON(compact, to: compactURL)
        try writeJSON(audit, to: auditURL)
        if let runtimeState {
            try writeJSON(runtimeState, to: runtimeURL)
        }
        let didWriteLogs: Bool
        do {
            try await writeRuntimeTracePayload(host: host, path: "logs", to: logsURL)
            didWriteLogs = true
        } catch {
            didWriteLogs = false
        }

        let screenshotPath: String?
        if let screenshotUDID = captureReportScreenshotUDID(options: options, runtimeState: runtimeState) {
            try captureSimulatorScreenshot(udid: screenshotUDID, outputURL: screenshotURL)
            screenshotPath = screenshotURL.path
        } else {
            screenshotPath = nil
        }

        let report = CaptureReport(
            capturedAt: Date(),
            host: host.absoluteString,
            udid: runtimeState?.identity.simulatorUDID ?? options.udid,
            bundleID: runtimeState?.identity.bundleIdentifier ?? options.bundleID,
            snapshotID: snapshot.id,
            screen: snapshot.screen,
            artifacts: CaptureReportArtifacts(
                screenshot: screenshotPath,
                snapshot: snapshotURL.path,
                screenMap: screenMapURL.path,
                accessibility: accessibilityURL.path,
                compact: compactURL.path,
                audit: auditURL.path,
                runtime: runtimeState == nil ? nil : runtimeURL.path,
                logs: didWriteLogs ? logsURL.path : nil,
                summaryMarkdown: summaryMarkdownURL.path
            ),
            counts: CaptureReportCounts(
                nodes: snapshot.nodes.count,
                screenMapElements: screenMap.elements.count,
                visibleTexts: compact.visibleTexts.count,
                interactiveElements: compact.interactive.count,
                accessibilityNodes: accessibilityTree.nodes.count,
                auditIssues: audit.issueCount,
                scrollViews: scrollViews.count,
                scrollableScrollViews: scrollViews.filter { !$0.scrollableAxes.isEmpty }.count
            ),
            scrollViews: scrollViews,
            auditIssuesByKind: Dictionary(
                grouping: audit.issues,
                by: { $0.kind.rawValue }
            ).mapValues(\.count),
            topAuditIssues: audit.issues.prefix(10).map { issue in
                CaptureReportAuditIssue(issue: issue, node: snapshot.nodes[issue.ref])
            }
        )

        try writeJSON(report, to: summaryURL)
        try renderCaptureReportMarkdown(report).write(to: summaryMarkdownURL, atomically: true, encoding: .utf8)
        print("report: \(options.outputDirectory.path)")
        if let screenshotPath {
            print("screenshot: \(screenshotPath)")
        } else {
            print("screenshot: unavailable for this runtime")
        }
        print("summary: \(summaryURL.path)")
        print("screen-map: \(screenMapURL.path)")
        if didWriteLogs {
            print("logs: \(logsURL.path)")
        }
    }

    private static func captureReportScreenshotUDID(
        options: CaptureReportOptions,
        runtimeState: LoupeRuntimeState?
    ) -> String? {
        if let udid = options.udid {
            return udid
        }
        if let runtimeState {
            return runtimeState.identity.simulatorUDID
        }
        return "booted"
    }

    private static func captureReportScrollViews(_ snapshot: LoupeSnapshot) -> [CaptureReportScrollView] {
        snapshot.nodes.values
            .compactMap { node -> CaptureReportScrollView? in
                guard let scrollView = node.platform?.scrollView else { return nil }
                return CaptureReportScrollView(node: node, scrollView: scrollView)
            }
            .sorted { lhs, rhs in
                if lhs.scrollableAxes.isEmpty != rhs.scrollableAxes.isEmpty {
                    return !lhs.scrollableAxes.isEmpty
                }
                let lhsFrame = lhs.frame
                let rhsFrame = rhs.frame
                if let lhsFrame, let rhsFrame, abs(lhsFrame.y - rhsFrame.y) > 0.5 {
                    return lhsFrame.y < rhsFrame.y
                }
                return lhs.ref < rhs.ref
            }
    }

    static func paintStack(_ arguments: [String]) async throws {
        let options = try PaintStackOptions(arguments)
        let snapshot: LoupeSnapshot
        if let snapshotURL = options.snapshotURL {
            snapshot = try decodeSnapshot(from: snapshotURL)
        } else {
            let host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid,
                bundleID: options.bundleID
            )
            if let udid = options.udid {
                try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
            }
            snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        }

        let stack: LoupePaintStack
        if let point = options.point {
            stack = LoupePaintStackBuilder.stack(
                in: snapshot,
                at: point,
                maxEntries: options.maxEntries
            )
        } else if let ref = options.ref {
            stack = try LoupePaintStackBuilder.stack(
                in: snapshot,
                centeredOn: ref,
                maxEntries: options.maxEntries
            )
        } else {
            throw CLIError("paint-stack requires --point x,y or --ref <ref>")
        }

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(stack))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            printPaintStack(stack)
        }
    }

    static func query(_ arguments: [String]) async throws {
        let options = try QueryOptions(arguments)
        if let snapshotURL = options.snapshotURL {
            let data = try Data(contentsOf: snapshotURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
            let result = try queryResultData(snapshot: snapshot, options: options)
            FileHandle.standardOutput.write(result.data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }
        let deadline = Date().addingTimeInterval(options.timeout)
        while true {
            let fetchTimeout = options.waitForMatch
                ? min(3, max(0.1, deadline.timeIntervalSinceNow))
                : options.timeout
            let snapshot = try await fetchSnapshot(host: host, timeout: fetchTimeout)
            let result = try queryResultData(snapshot: snapshot, options: options)
            if !options.waitForMatch || result.count > 0 || Date() >= deadline {
                FileHandle.standardOutput.write(result.data)
                FileHandle.standardOutput.write(Data("\n".utf8))
                return
            }
            try await sleep(seconds: min(0.25, max(0.01, deadline.timeIntervalSinceNow)))
        }
    }

    private static func queryResultData(
        snapshot: LoupeSnapshot,
        options: QueryOptions
    ) throws -> (data: Data, count: Int) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let context = LoupeSnapshotContext(snapshot: snapshot)
        switch options.tree {
        case .view:
            let results = LoupeSnapshotQuery.find(
                options.selector,
                in: context,
                options: LoupeQueryOptions(
                    includeHidden: options.includeHidden,
                    includeDisabled: true,
                    maxResults: options.maxResults
                )
            )
            return (try encoder.encode(results), results.count)
        case .accessibility:
            let tree = LoupeAccessibilityTree.build(from: context, includeHidden: options.includeHidden)
            let results = LoupeAccessibilityTreeQuery.find(
                options.selector,
                in: tree,
                options: LoupeQueryOptions(
                    includeHidden: options.includeHidden,
                    includeDisabled: true,
                    maxResults: options.maxResults
                )
            )
            return (try encoder.encode(results), results.count)
        }
    }

    static func accessibility(_ arguments: [String]) throws {
        let options = try AccessibilityOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
        let context = LoupeSnapshotContext(snapshot: snapshot)
        let tree = LoupeAccessibilityTree.build(from: context, includeHidden: options.includeHidden)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try write(data: encoder.encode(tree), outputURL: options.outputURL)
    }

    static func inspect(_ arguments: [String]) throws {
        let options = try InspectOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)

        guard let inspection = LoupeSnapshotInspector.inspect(
            options.selector,
            in: snapshot,
            options: LoupeQueryOptions(includeHidden: options.includeHidden)
        ) else {
            throw CLIError("No Loupe node matched selector")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let inspectionData = try encoder.encode(inspection)
        if let fields = options.fields {
            FileHandle.standardOutput.write(try filteredInspectionData(inspectionData, fields: fields))
        } else {
            FileHandle.standardOutput.write(inspectionData)
        }
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func subtree(_ arguments: [String]) throws {
        let options = try SubtreeOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)

        guard let subtree = LoupeSnapshotInspector.subtree(
            options.selector,
            in: snapshot,
            maxDepth: options.depth,
            options: LoupeQueryOptions(includeHidden: options.includeHidden)
        ) else {
            throw CLIError("No Loupe node matched selector")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        FileHandle.standardOutput.write(try encoder.encode(subtree))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func tree(_ arguments: [String]) async throws {
        let options = try TreeOptions(arguments)
        let snapshot: LoupeSnapshot
        let accessibilityTree: LoupeAccessibilityTree?

        if let snapshotURL = options.snapshotURL {
            let data = try Data(contentsOf: snapshotURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
            let context = LoupeSnapshotContext(snapshot: snapshot)
            accessibilityTree = options.tree == .accessibility
                ? LoupeAccessibilityTree.build(from: context, includeHidden: options.includeHidden, visibilityMode: .occlusion)
                : nil
        } else {
            let host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid,
                bundleID: options.bundleID
            )
            if let udid = options.udid {
                try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
            }
            snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
            accessibilityTree = options.tree == .accessibility
                ? try await fetchAccessibilityTree(host: host, fallbackSnapshot: snapshot, timeout: options.timeout)
                : nil
        }

        let output: String
        switch options.tree {
        case .view:
            output = renderViewTree(
                snapshot,
                selector: options.selector,
                depth: options.depth,
                includeHidden: options.includeHidden,
                presentation: options.presentation
            )
        case .accessibility:
            output = renderAccessibilityTree(
                accessibilityTree ?? LoupeAccessibilityTree.build(
                    from: LoupeSnapshotContext(snapshot: snapshot),
                    includeHidden: options.includeHidden
                ),
                selector: options.selector,
                depth: options.depth,
                includeHidden: options.includeHidden,
                presentation: options.presentation
            )
        }
        print(output)
    }

    static func audit(_ arguments: [String]) throws {
        let options = try AuditOptions(arguments)
        let data = try Data(contentsOf: options.snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(LoupeSnapshot.self, from: data)
        let audit = filteredAudit(
            LoupeLayoutAuditor.audit(
                snapshot,
                options: LoupeLayoutAuditOptions(
                    tolerance: options.tolerance,
                    minOverlapArea: options.minOverlapArea,
                    minTouchTarget: options.minTouchTarget,
                    minContrastRatio: options.minContrastRatio
                )
            ),
            options: options
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(audit))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func filteredAudit(_ audit: LoupeLayoutAudit, options: AuditOptions) -> LoupeLayoutAudit {
        let issues = audit.issues.filter { issue in
            (options.kinds.isEmpty || options.kinds.contains(issue.kind))
                && !options.excludedKinds.contains(issue.kind)
        }
        return LoupeLayoutAudit(snapshotID: audit.snapshotID, issues: issues)
    }

    static func diff(_ arguments: [String]) throws {
        let options = try DiffOptions(arguments)
        let before = try decodeSnapshot(from: options.beforeURL)
        let after = try decodeSnapshot(from: options.afterURL)
        let summary = snapshotDiff(before: before, after: after)

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(summary))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print(renderSnapshotDiff(summary, limit: options.limit, changedOnly: options.changedOnly))
    }

    static func traceSummary(_ arguments: [String]) throws {
        let options = try TraceSummaryOptions(arguments)
        let summary = try makeTraceSummary(directory: options.directory)

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            FileHandle.standardOutput.write(try encoder.encode(summary))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print(renderTraceSummary(summary, limit: options.limit))
    }

    static func compareDesign(_ arguments: [String]) throws {
        let options = try CompareDesignOptions(arguments)
        let snapshot = try decodeSnapshot(from: options.snapshotURL)
        let decoder = JSONDecoder()
        let design = try decoder.decode(LoupeDesignDocument.self, from: Data(contentsOf: options.designURL))
        let comparison = LoupeDesignComparator.compare(
            snapshot: snapshot,
            design: design,
            options: LoupeDesignComparisonOptions(
                frameTolerance: options.frameTolerance,
                colorTolerance: options.colorTolerance,
                cornerRadiusTolerance: options.cornerRadiusTolerance,
                fontSizeTolerance: options.fontSizeTolerance,
                maxMatchDistance: options.maxMatchDistance,
                includeUnexpectedAppNodes: options.includeUnexpectedAppNodes
            )
        )

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(comparison))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print(
            renderDesignComparison(
                comparison,
                limit: options.limit,
                suggestMutations: options.suggestMutations,
                snapshotURL: options.snapshotURL,
                suggestionHost: options.suggestionHost
            )
        )
    }

    static func applyDesignSuggestions(_ arguments: [String]) async throws {
        let options = try ApplyDesignSuggestionsOptions(arguments)
        let decoder = JSONDecoder()
        let comparison = try decoder.decode(
            LoupeDesignComparison.self,
            from: Data(contentsOf: options.compareURL)
        )
        let referenceSnapshot = try options.snapshotURL.map { try decodeSnapshot(from: $0) }
        let selectedSuggestions = options.selectedSuggestions(
            from: comparison.suggestions,
            referenceSnapshot: referenceSnapshot
        )
        guard !selectedSuggestions.isEmpty else {
            throw CLIError("apply-design-suggestions found no suggestions matching the requested filters")
        }

        try FileManager.default.createDirectory(
            at: options.outputDirectory,
            withIntermediateDirectories: true
        )

        let selectedURL = options.outputDirectory.appendingPathComponent("selected-suggestions.json")
        let beforeURL = options.outputDirectory.appendingPathComponent("before-snapshot.json")
        let afterURL = options.outputDirectory.appendingPathComponent("after-snapshot.json")
        let diffURL = options.outputDirectory.appendingPathComponent("diff.json")
        let responsesURL = options.outputDirectory.appendingPathComponent("responses.json")
        let summaryURL = options.outputDirectory.appendingPathComponent("summary.json")
        try writeJSON(selectedSuggestions, to: selectedURL)

        if options.dryRun {
            let applications = selectedSuggestions.enumerated().map { offset, suggestion in
                ApplyDesignSuggestionApplication(
                    index: offset + 1,
                    issueKind: suggestion.issueKind,
                    designID: suggestion.designID,
                    designName: suggestion.designName,
                    originalRef: suggestion.ref,
                    appliedRef: nil,
                    appliedSelectorKind: nil,
                    appliedSelectorValue: nil,
                    property: suggestion.property,
                    valueType: suggestion.valueType,
                    valueLabel: suggestion.valueLabel,
                    changed: nil,
                    warning: nil,
                    response: nil,
                    error: nil
                )
            }
            let result = ApplyDesignSuggestionsResult(
                host: nil,
                dryRun: true,
                compareDesign: options.compareURL.path,
                referenceSnapshot: options.snapshotURL?.path,
                outputDirectory: options.outputDirectory.path,
                selectedSuggestions: selectedSuggestions.count,
                mutationRequests: 0,
                changedMutations: 0,
                failedMutations: 0,
                beforeSnapshot: nil,
                afterSnapshot: nil,
                diff: nil,
                responses: nil,
                applications: applications
            )
            try writeJSON(result, to: summaryURL)
            print("apply-design-suggestions dry-run selected=\(selectedSuggestions.count)")
            print("summary: \(summaryURL.path)")
            print("selected: \(selectedURL.path)")
            return
        }

        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }

        var liveSnapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        let before = liveSnapshot
        try writeSnapshot(before, to: beforeURL)

        var applications: [ApplyDesignSuggestionApplication] = []
        var responses: [LoupeMutationResponse] = []
        for (offset, suggestion) in selectedSuggestions.enumerated() {
            var attemptedSelector: LoupeMutationSelector?
            let baseRequest = LoupeMutationRequest(
                selector: mutationSelector(for: suggestion),
                property: suggestion.property,
                value: suggestion.value,
                layout: true,
                animation: nil
            )

            do {
                let request: LoupeMutationRequest
                if let referenceSnapshot {
                    request = try requestByResolvingMutationSnapshotRef(
                        baseRequest,
                        referenceSnapshot: referenceSnapshot,
                        liveSnapshot: liveSnapshot
                    )
                } else {
                    request = baseRequest
                }
                attemptedSelector = request.selector

                let response = try await postMutation(request, host: host, timeout: options.timeout)
                responses.append(response)
                let responseURL = options.outputDirectory
                    .appendingPathComponent("response-\(String(format: "%02d", offset + 1))-\(safeArtifactName(suggestion.property))-\(safeArtifactName(request.selector.value)).json")
                try writeJSON(response, to: responseURL)
                applications.append(
                    ApplyDesignSuggestionApplication(
                        index: offset + 1,
                        issueKind: suggestion.issueKind,
                        designID: suggestion.designID,
                        designName: suggestion.designName,
                        originalRef: suggestion.ref,
                        appliedRef: request.selector.kind == .ref ? request.selector.value : nil,
                        appliedSelectorKind: request.selector.kind.rawValue,
                        appliedSelectorValue: request.selector.value,
                        property: suggestion.property,
                        valueType: suggestion.valueType,
                        valueLabel: suggestion.valueLabel,
                        changed: mutationResponseChanged(response),
                        warning: response.warning,
                        response: responseURL.path,
                        error: nil
                    )
                )
                liveSnapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
            } catch {
                applications.append(
                    ApplyDesignSuggestionApplication(
                        index: offset + 1,
                        issueKind: suggestion.issueKind,
                        designID: suggestion.designID,
                        designName: suggestion.designName,
                        originalRef: suggestion.ref,
                        appliedRef: attemptedSelector?.kind == .ref ? attemptedSelector?.value : nil,
                        appliedSelectorKind: attemptedSelector?.kind.rawValue,
                        appliedSelectorValue: attemptedSelector?.value,
                        property: suggestion.property,
                        valueType: suggestion.valueType,
                        valueLabel: suggestion.valueLabel,
                        changed: nil,
                        warning: nil,
                        response: nil,
                        error: String(describing: error)
                    )
                )
            }
        }

        let after = try await fetchSnapshot(host: host, timeout: options.timeout)
        try writeSnapshot(after, to: afterURL)
        let diff = snapshotDiff(before: before, after: after)
        try writeJSON(diff, to: diffURL)
        try writeJSON(responses, to: responsesURL)

        let changedCount = responses.filter { mutationResponseChanged($0) }.count
        let failedCount = applications.filter { $0.error != nil }.count
        let result = ApplyDesignSuggestionsResult(
            host: host.absoluteString,
            dryRun: false,
            compareDesign: options.compareURL.path,
            referenceSnapshot: options.snapshotURL?.path,
            outputDirectory: options.outputDirectory.path,
            selectedSuggestions: selectedSuggestions.count,
            mutationRequests: responses.count,
            changedMutations: changedCount,
            failedMutations: failedCount,
            beforeSnapshot: beforeURL.path,
            afterSnapshot: afterURL.path,
            diff: diffURL.path,
            responses: responsesURL.path,
            applications: applications
        )
        try writeJSON(result, to: summaryURL)

        print("apply-design-suggestions selected=\(selectedSuggestions.count) mutations=\(responses.count) changed=\(changedCount) failed=\(failedCount)")
        print("summary: \(summaryURL.path)")
        print("before: \(beforeURL.path)")
        print("after: \(afterURL.path)")
        print("responses: \(responsesURL.path)")
    }

    static func mutationSelector(for suggestion: LoupeDesignMutationSuggestion) -> LoupeMutationSelector {
        if let testID = suggestion.testID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !testID.isEmpty {
            return LoupeMutationSelector(kind: .testID, value: testID)
        }
        return LoupeMutationSelector(kind: .ref, value: suggestion.ref)
    }

    static func mutationResponseChanged(_ response: LoupeMutationResponse) -> Bool {
        if response.changed == true || response.changed == nil {
            return true
        }
        guard let requested = response.requested, let effective = response.effective else {
            return false
        }
        return mutationValuesApproximatelyEqual(requested, effective)
    }

    static func mutationValuesApproximatelyEqual(_ requested: LoupeMutationValue, _ effective: LoupeMutationValue) -> Bool {
        switch (requested, effective) {
        case let (.bool(lhs), .bool(rhs)):
            return lhs == rhs
        case let (.int(lhs), .int(rhs)):
            return lhs == rhs
        case let (.int(lhs), .double(rhs)):
            return abs(Double(lhs) - rhs) < 0.5
        case let (.double(lhs), .int(rhs)):
            return abs(lhs - Double(rhs)) < 0.5
        case let (.double(lhs), .double(rhs)):
            return abs(lhs - rhs) < 0.5
        case let (.string(lhs), .string(rhs)):
            return lhs == rhs
        case let (.color(lhs), .color(rhs)):
            return abs(lhs.red - rhs.red) < 0.01
                && abs(lhs.green - rhs.green) < 0.01
                && abs(lhs.blue - rhs.blue) < 0.01
                && abs(lhs.alpha - rhs.alpha) < 0.01
        case let (.point(lhs), .point(rhs)):
            return abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
        case let (.size(lhs), .size(rhs)):
            return abs(lhs.width - rhs.width) < 0.5 && abs(lhs.height - rhs.height) < 0.5
        case let (.rect(lhs), .rect(rhs)):
            return abs(lhs.x - rhs.x) < 0.5
                && abs(lhs.y - rhs.y) < 0.5
                && abs(lhs.width - rhs.width) < 0.5
                && abs(lhs.height - rhs.height) < 0.5
        default:
            return false
        }
    }

    static func skills(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError("Usage: loupe skills install [--target all|codex|claude] [--source <skill-dir>]")
        }

        switch subcommand {
        case "install":
            try installSkills(Array(arguments.dropFirst()))
        default:
            throw CLIError("Unknown skills command: \(subcommand)")
        }
    }

    static func installSkills(_ arguments: [String]) throws {
        let options = try InstallSkillsOptions(arguments)
        let source = try resolvedSkillSource(options.sourceURL)
        let targets = options.target.targets
        var installed = 0

        for target in targets {
            guard FileManager.default.fileExists(atPath: target.root.path) else {
                print("skipped \(target.name): \(target.root.path) does not exist")
                continue
            }

            let skillsDirectory = target.root.appendingPathComponent("skills", isDirectory: true)
            let destination = skillsDirectory.appendingPathComponent("loupe", isDirectory: true)
            try FileManager.default.createDirectory(at: skillsDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            installed += 1
            print("installed \(target.name): \(destination.path)")
        }

        if installed == 0 {
            throw CLIError("No supported skill folders found. Create ~/.codex or ~/.claude first, or pass --target for an installed client.")
        }
    }

    static func cleanup(_ arguments: [String]) async throws {
        let options = try CleanupOptions(arguments)
        var report = CleanupReport()

        if options.pruneRuntimes {
            report.runtimeRecordsRemoved = try await cleanupRuntimeRecords(options: options)
        }
        if options.pruneTraces {
            report.traceBundlesRemoved = try cleanupDirectory(
                traceRootDirectory(),
                olderThan: options.tracesOlderThan,
                dryRun: options.dryRun
            )
        }
        print("\(options.dryRun ? "would remove" : "removed") runtimeRecords=\(report.runtimeRecordsRemoved) traceBundles=\(report.traceBundlesRemoved)")
    }

    private static func cleanupRuntimeRecords(options: CleanupOptions) async throws -> Int {
        let records = try loadRuntimeHostRecords()
        var removed = 0

        for record in records {
            var shouldRemove = true
            if let host = URL(string: record.host),
               let state = try? await fetchRuntimeState(host: host, timeout: options.timeout),
               state.identity.simulatorUDID == record.udid,
               state.identity.bundleIdentifier == record.bundleID {
                shouldRemove = false
            }

            guard shouldRemove else {
                continue
            }

            removed += 1
            if !options.dryRun {
                try? removeRuntimeHostRecord(record)
            }
        }

        return removed
    }

    private static func cleanupDirectory(_ directory: URL, olderThan age: TimeInterval, dryRun: Bool) throws -> Int {
        guard age >= 0 else {
            throw CLIError("cleanup age must be non-negative")
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        let cutoff = Date().addingTimeInterval(-age)
        var removed = 0
        for url in urls {
            guard itemModificationDate(url) <= cutoff else {
                continue
            }
            removed += 1
            if !dryRun {
                try FileManager.default.removeItem(at: url)
            }
        }
        return removed
    }

    private static func itemModificationDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? Date.distantPast
    }

    private static func traceRootDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("loupe-traces", isDirectory: true)
    }

    static func start(_ arguments: [String]) async throws {
        var launchArguments: [String] = []
        var index = 0
        var hasLaunchMode = false

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--inject", "--linked", "--no-inject", "--dylib":
                hasLaunchMode = true
                launchArguments.append(argument)
            default:
                launchArguments.append(argument)
            }
            index += 1
        }

        if !hasLaunchMode {
            launchArguments.append("--inject")
        }
        try await launch(launchArguments)
    }

    static func launch(_ arguments: [String]) async throws {
        let options = try LaunchOptions(arguments)
        var environment = options.environment
        if let port = options.port {
            environment["LOUPE_PORT"] = String(port)
        }
        if let bindHost = options.bindHost {
            environment["LOUPE_BIND_HOST"] = bindHost
        }

        let resolvedSimulatorDevice: String?
        do {
            resolvedSimulatorDevice = try resolveSimulatorUDID(options.device)
        } catch {
            if options.shouldInject {
                throw error
            }
            guard options.device != "booted" else {
                throw CLIError(
                    "No booted simulator matched `booted`. For a physical device, pass --device <device-id> with --linked."
                )
            }
            resolvedSimulatorDevice = nil
        }

        if options.shouldInject, let dylibPath = try resolvedInjectorPath(explicitPath: options.dylibPath) {
            environment["DYLD_INSERT_LIBRARIES"] = dylibPath
            guard let udid = resolvedSimulatorDevice else {
                throw CLIError("Loupe injection requires a simulator device. Use --linked for LoupeInjector-linked physical-device apps.")
            }
            let port = try resolvedLoupePort(for: udid, environment: environment)
            let host = URL(string: "http://127.0.0.1:\(port)")!
            try validateLaunchPort(host: host, expectedUDID: udid, expectedBundleID: options.bundleID)
            environment["LOUPE_PORT"] = String(port)
            try terminateAppIfRunning(
                device: udid,
                bundleID: options.bundleID,
                timeout: simctlTerminateTimeout(launchTimeout: options.timeout)
            )

            try runSimctlLaunch(
                device: udid,
                bundleID: options.bundleID,
                environment: environment,
                timeout: options.timeout
            )

            try await waitForRuntime(host: host, expectedUDID: udid, timeout: options.timeout)
            try storeRuntimeHost(udid: udid, bundleID: options.bundleID, host: host)
            try storeCurrentRuntimeHost(
                LoupeRuntimeHostRecord(udid: udid, bundleID: options.bundleID, host: host.absoluteString, updatedAt: Date())
            )
            print("loupe host: \(host.absoluteString)")
            return
        }

        if let resolvedSimulatorDevice {
            try runSimctlLaunch(
                device: resolvedSimulatorDevice,
                bundleID: options.bundleID,
                environment: environment,
                timeout: options.timeout
            )
            if let host = options.host {
                try await storeLinkedRuntimeAfterLaunch(
                    host: host,
                    expectedDeviceID: resolvedSimulatorDevice,
                    fallbackDeviceID: resolvedSimulatorDevice,
                    fallbackBundleID: options.bundleID,
                    timeout: options.timeout
                )
            }
            return
        }

        environment["LOUPE_DEVICE_ID"] = environment["LOUPE_DEVICE_ID"] ?? options.device
        try runDevicectlLaunch(
            device: options.device,
            bundleID: options.bundleID,
            environment: environment,
            timeout: options.timeout
        )
        if let host = options.host {
            try await storeLinkedRuntimeAfterLaunch(
                host: host,
                expectedDeviceID: environment["LOUPE_DEVICE_ID"],
                fallbackDeviceID: options.device,
                fallbackBundleID: options.bundleID,
                timeout: options.timeout
            )
        } else {
            print("launched linked app on \(options.device)")
        }
    }

    private static func runSimctlLaunch(
        device: String,
        bundleID: String,
        environment: [String: String],
        timeout: TimeInterval
    ) throws {
        let request = SimctlLaunchRequest(
            device: device,
            bundleID: bundleID,
            environment: environment
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = SimctlCommandBuilder.launchArguments(for: request)
        process.environment = SimctlCommandBuilder.launchEnvironment(for: request)

        try run(process, label: "simctl launch", timeout: timeout)
    }

    private static func runDevicectlLaunch(
        device: String,
        bundleID: String,
        environment: [String: String],
        timeout: TimeInterval
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        var arguments = [
            "devicectl",
            "device",
            "process",
            "launch",
            "--device",
            device,
            "--terminate-existing",
        ]
        if !environment.isEmpty {
            let data = try JSONSerialization.data(
                withJSONObject: environment,
                options: [.sortedKeys]
            )
            guard let json = String(data: data, encoding: .utf8) else {
                throw CLIError("Could not encode devicectl environment")
            }
            arguments.append(contentsOf: ["--environment-variables", json])
        }
        arguments.append(bundleID)
        process.arguments = arguments

        try runDevicectlProcess(process, timeout: timeout)
    }

    private static func runDevicectlProcess(_ process: Process, timeout: TimeInterval) throws {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        try process.run()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw CLIError("devicectl launch timed out after \(format(timeout))s")
        }

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let error = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let details = [error, output]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            var message = "devicectl launch exited with status \(process.terminationStatus)"
            if !details.isEmpty {
                message += ": \(details)"
            }
            if details.contains("CoreDeviceService was unable to locate")
                || details.contains("The specified device was not found")
                || details.contains("pairingState: unsupported")
            {
                message += "\nHint: this device is not available through CoreDevice/devicectl. For older iOS devices, install and launch a LoupeInjector-linked debug app from Xcode, then select it with `loupe app use --host <runtime-host>`."
            }
            if details.contains("Locked")
                || details.contains("could not be, unlocked")
                || details.contains("Unable to launch")
            {
                message += "\nHint: unlock the physical device and keep it awake, then retry `loupe app launch --linked`."
            }
            throw CLIError(message)
        }
    }

    private static func storeLinkedRuntimeAfterLaunch(
        host: URL,
        expectedDeviceID: String?,
        fallbackDeviceID: String,
        fallbackBundleID: String,
        timeout: TimeInterval
    ) async throws {
        try await waitForRuntimeHost(
            host: host,
            expectedDeviceID: expectedDeviceID,
            timeout: timeout
        )
        let state = try await fetchRuntimeState(host: host, timeout: min(1, timeout))
        let record = runtimeHostRecord(
            state: state,
            host: host,
            fallbackDeviceID: fallbackDeviceID,
            fallbackBundleID: fallbackBundleID
        )
        try storeRuntimeHost(record)
        try storeCurrentRuntimeHost(record)
        print("loupe host: \(host.absoluteString)")
    }

    private static func injectorPath(_ arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw CLIError("Usage: loupe injector-path")
        }

        guard let path = try resolvedInjectorPath(explicitPath: nil) else {
            throw CLIError("LoupeInjector not found. Set LOUPE_INJECTOR_PATH or install Loupe through Homebrew.")
        }

        print(path)
    }

    private static func doctor(_ arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw CLIError("Usage: loupe doctor")
        }

        print("loupe: ok")

        if let path = try resolvedInjectorPath(explicitPath: nil) {
            print("injector: \(path)")
        } else {
            print("injector: not found")
            print("hint: set LOUPE_INJECTOR_PATH or install via Homebrew")
        }

        let simctl = Process()
        simctl.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        simctl.arguments = ["simctl", "help"]
        simctl.standardOutput = Pipe()
        simctl.standardError = Pipe()
        try simctl.run()
        simctl.waitUntilExit()
        print("simctl: \(simctl.terminationStatus == 0 ? "ok" : "unavailable")")
        print("action backend native: ok")
    }

    private static func resolvedInjectorPath(explicitPath: String?) throws -> String? {
        if let explicitPath {
            guard FileManager.default.isExecutableFile(atPath: explicitPath) else {
                throw CLIError("Injector is not executable: \(explicitPath)")
            }
            return explicitPath
        }

        return LoupeInjectorPathResolver().resolve()
    }

    static let developmentVersion = "0.1.5-dev"

    static func versionString(
        executablePath: String? = Bundle.main.executableURL?.path,
        resolvedExecutablePath: String? = Bundle.main.executableURL?.resolvingSymlinksInPath().path
    ) -> String {
        for path in [executablePath, resolvedExecutablePath].compactMap(\.self) {
            if let version = homebrewVersion(fromExecutablePath: path) {
                return version
            }
        }
        return developmentVersion
    }

    private static func homebrewVersion(fromExecutablePath executablePath: String) -> String? {
        let components = executablePath.split(separator: "/").map(String.init)
        for index in components.indices.dropLast(2) where components[index] == "Cellar" {
            guard components[index + 1] == "loupe" else {
                continue
            }
            return components[index + 2]
        }
        return nil
    }

    static func summaryHelp(version: String) -> String {
        """
        OVERVIEW: A CLI that gives agents runtime UI context through small primitives and skill-driven workflows.

        VERSION: \(version)

        USAGE: loupe <command-group> <subcommand>

        OPTIONS:
          -h, --help              Show help information.
          --version               Show the current Loupe version.

        COMMAND GROUPS:
          app                     Launch, select, and inspect app runtimes.
          ui                      Capture, inspect, audit, and mutate UI state.
          act                     Dispatch input and wait for UI state.
          debug                   Read and change diagnostic app state.
          skills                  Install Loupe workflow skills.

        DIAGNOSTICS:
          doctor                  Check local installation health.
          injector-path           Print the resolved injector path.
          version                 Show the current Loupe version.

          See 'loupe help <command-group> <subcommand>' for detailed help.
        """
    }

    static func summaryHelpLineCount(version: String) -> Int {
        summaryHelp(version: version)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .count
    }

    private static func printSummaryHelp() {
        print(summaryHelp(version: versionString()))
    }

    private static func printVersion() {
        print("loupe \(versionString())")
    }

    private static func printHelp() {
        printSummaryHelp()
    }

    private static func printCommandHelp(_ path: [String]) {
        guard !path.isEmpty else {
            printHelp()
            return
        }

        let usageKeys = (1...path.count)
            .reversed()
            .map { path.prefix($0).joined(separator: " ") }

        if let usage = usageKeys.lazy.compactMap({ commandUsage($0) }).first {
            print(usage)
        } else {
            printHelp()
        }
    }

    private static func printPaintStack(_ stack: LoupePaintStack) {
        print("point: \(format(stack.point.x)),\(format(stack.point.y))")
        if let sourceRef = stack.sourceRef {
            print("sourceRef: \(sourceRef)")
        }
        print("top")
        for entry in stack.entries {
            var parts: [String] = [
                entry.ref,
                entry.className ?? entry.typeName,
            ]
            if let testID = entry.testID {
                parts.append("#\(testID)")
            }
            if let text = entry.text {
                parts.append("text=\"\(text)\"")
            }
            parts.append("frame=\(format(entry.frame))")
            if let color = entry.style?.backgroundColor, color.alpha > 0 {
                parts.append("background=\(format(color))")
            }
            print(parts.joined(separator: " "))
        }
        print("bottom")
    }

    private static func format(_ rect: LoupeRect) -> String {
        "\(format(rect.x)),\(format(rect.y)),\(format(rect.width)),\(format(rect.height))"
    }

    private static func format(_ color: LoupeColor) -> String {
        "\(format(color.red)),\(format(color.green)),\(format(color.blue)),\(format(color.alpha))"
    }

    static func mutations(_ arguments: [String]) async throws {
        let options = try MutationListOptions(arguments)
        guard let selector = options.selector else {
            try await runtimeFetch(
                arguments,
                path: "/mutations",
                usage: "loupe ui mutations [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
            return
        }

        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }
        let snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        let matches = LoupeSnapshotQuery.find(
            selector,
            in: snapshot,
            options: LoupeQueryOptions(
                includeHidden: options.includeHidden,
                includeDisabled: true,
                maxResults: 20,
                visibilityMode: .raw
            )
        )
        guard let result = matches.first, let node = snapshot.nodes[result.ref] else {
            throw CLIError("No view node matched selector")
        }
        let output = renderNodeMutationCapabilities(node)
        if let outputURL = options.outputURL {
            try Data((output + "\n").utf8).write(to: outputURL)
        } else {
            print(output)
        }
    }

    static func constraints(_ arguments: [String]) async throws {
        let options = try ConstraintListOptions(arguments)
        let snapshot: LoupeSnapshot
        if let snapshotURL = options.snapshotURL {
            snapshot = try decodeSnapshot(from: snapshotURL)
        } else {
            let host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid,
                bundleID: options.bundleID
            )
            if let udid = options.udid {
                try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
            }
            snapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
        }

        let matches = LoupeSnapshotQuery.find(
            options.selector,
            in: snapshot,
            options: LoupeQueryOptions(
                includeHidden: options.includeHidden,
                includeDisabled: true,
                maxResults: 20,
                visibilityMode: .raw
            )
        )
        guard let result = matches.first, let node = snapshot.nodes[result.ref] else {
            throw CLIError("No view node matched selector")
        }

        let constraints = nodeConstraints(node)
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try write(data: encoder.encode(constraints), outputURL: options.outputURL)
        } else {
            let output = renderConstraints(node: node, constraints: constraints)
            if let outputURL = options.outputURL {
                try Data((output + "\n").utf8).write(to: outputURL)
            } else {
                print(output)
            }
        }
    }

    static func set(_ arguments: [String]) async throws {
        if arguments.contains("--list") {
            try await runtimeFetch(
                arguments.filter { $0 != "--list" },
                path: "/mutations",
                usage: "loupe ui set --list [--host <url>] [--udid <sim>] [--output <path>]"
            )
            return
        }

        let options = try MutationSetOptions(arguments)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }

        let mutationRequest: LoupeMutationRequest
        if let snapshotURL = options.snapshotURL {
            let referenceSnapshot = try decodeSnapshot(from: snapshotURL)
            let liveSnapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
            mutationRequest = try requestByResolvingMutationSnapshotRef(
                options.request,
                referenceSnapshot: referenceSnapshot,
                liveSnapshot: liveSnapshot
            )
        } else {
            mutationRequest = options.request
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let body = try encoder.encode(mutationRequest)
        var request = URLRequest(url: host.appendingPathComponent("mutate"))
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await httpData(for: request, timeout: options.timeout, label: "mutation")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("mutation expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw CLIError("mutation failed with HTTP \(httpResponse.statusCode): \(body)")
        }
        if options.outputURL != nil,
           let mutation = try? JSONDecoder().decode(LoupeMutationResponse.self, from: data) {
            FileHandle.standardError.write(Data((renderMutationSummary(mutation, outputURL: options.outputURL) + "\n").utf8))
        }
        try write(data: data, outputURL: options.outputURL)
    }

    static func requestByResolvingMutationSnapshotRef(
        _ request: LoupeMutationRequest,
        referenceSnapshot: LoupeSnapshot,
        liveSnapshot: LoupeSnapshot
    ) throws -> LoupeMutationRequest {
        guard request.selector.kind == .ref else {
            return request
        }

        let referenceRef = request.selector.value
        guard let referenceNode = referenceSnapshot.nodes[referenceRef] else {
            throw CLIError("Snapshot does not contain ref \(referenceRef)")
        }

        if let liveNode = liveSnapshot.nodes[referenceRef],
           mutationSnapshotRefCandidateScore(reference: referenceNode, candidate: liveNode) != nil {
            return request
        }

        let scoredCandidates = liveSnapshot.nodes.values.compactMap { candidate -> (node: LoupeNode, score: Double)? in
            guard let score = mutationSnapshotRefCandidateScore(reference: referenceNode, candidate: candidate) else {
                return nil
            }
            return (candidate, score)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.node.ref < rhs.node.ref
        }

        guard let best = scoredCandidates.first else {
            throw CLIError("Could not resolve snapshot ref \(referenceRef) in the live runtime; re-query the current screen or use --test-id")
        }
        if let second = scoredCandidates.dropFirst().first, abs(best.score - second.score) < 0.001 {
            throw CLIError("Snapshot ref \(referenceRef) is ambiguous in the live runtime; re-query the current screen or use --test-id")
        }

        var resolvedRequest = request
        resolvedRequest.selector = LoupeMutationSelector(kind: .ref, value: best.node.ref)
        return resolvedRequest
    }

    private static func mutationSnapshotRefCandidateScore(reference: LoupeNode, candidate: LoupeNode) -> Double? {
        let referenceClass = reference.platform?.className ?? reference.typeName
        let candidateClass = candidate.platform?.className ?? candidate.typeName
        let referenceText = LoupeObservationCompactor.displayText(for: reference)
        let candidateText = LoupeObservationCompactor.displayText(for: candidate)

        var score = 0.0
        if let testID = reference.testID {
            guard candidate.testID == testID else {
                return nil
            }
            score += 1_000
        } else {
            guard reference.typeName == candidate.typeName || referenceClass == candidateClass else {
                return nil
            }
        }

        if reference.typeName == candidate.typeName {
            score += 120
        }
        if referenceClass == candidateClass {
            score += 120
        }

        if let referenceRole = reference.role {
            guard candidate.role == referenceRole else {
                return nil
            }
            score += 80
        }

        if let referenceText {
            guard candidateText == referenceText else {
                return nil
            }
            score += 160
        }

        if let referenceFrame = reference.frame, let candidateFrame = candidate.frame {
            let delta = abs(referenceFrame.x - candidateFrame.x)
                + abs(referenceFrame.y - candidateFrame.y)
                + abs(referenceFrame.width - candidateFrame.width)
                + abs(referenceFrame.height - candidateFrame.height)
            guard reference.testID != nil || delta <= 80 else {
                return nil
            }
            score += max(0, 160 - delta)
        }

        if reference.isInteractive == candidate.isInteractive {
            score += 20
        }
        if reference.isEnabled == candidate.isEnabled {
            score += 10
        }
        return score
    }

    static func setMany(_ arguments: [String]) async throws {
        let startedAt = Date()
        let options = try BatchMutationOptions(arguments)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }

        try FileManager.default.createDirectory(at: options.traceDirectory, withIntermediateDirectories: true)
        let prevURL = options.traceDirectory.appendingPathComponent("prev-snapshot.json")
        let nextURL = options.traceDirectory.appendingPathComponent("next-snapshot.json")
        let diffURL = options.traceDirectory.appendingPathComponent("diff.json")
        let targetsURL = options.traceDirectory.appendingPathComponent("targets.json")
        let responsesURL = options.traceDirectory.appendingPathComponent("responses.json")

        let before = try await fetchSnapshot(host: host, timeout: options.timeout)
        try writeSnapshot(before, to: prevURL)
        let plan = BatchMutationPlanner.makePlan(snapshot: before, options: options)
        guard !plan.isEmpty else {
            throw CLIError("set-many found no matching nodes for \(options.selectorDescription)")
        }

        var mutationResponses: [LoupeMutationResponse] = []
        for target in plan {
            for ref in target.mutationRefs {
                let request = LoupeMutationRequest(
                    selector: LoupeMutationSelector(kind: .ref, value: ref),
                    property: options.property!,
                    value: target.value,
                    layout: true,
                    animation: options.animation
                )
                mutationResponses.append(try await postMutation(request, host: host, timeout: options.timeout))
            }
        }

        let after = try await fetchSnapshot(host: host, timeout: options.timeout)
        try writeSnapshot(after, to: nextURL)
        let diff = snapshotDiff(before: before, after: after)
        let encoder = makeLoupeJSONEncoder()
        try encoder.encode(diff).write(to: diffURL)

        let targets = plan.map { target in
            BatchMutationTargetResult(
                targetRef: target.targetRef,
                mutationRefs: target.mutationRefs,
                frame: target.frame,
                verified: batchMutationVerified(target, after: after, property: options.property!, responses: mutationResponses)
            )
        }
        try encoder.encode(targets).write(to: targetsURL)
        try encoder.encode(mutationResponses).write(to: responsesURL)
        let verifiedCells = targets.filter(\.verified).count
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let result = BatchMutationResult(
            host: host.absoluteString,
            elapsedMs: elapsedMs,
            selector: options.selectorDescription,
            property: options.property!,
            valueSequence: options.valueLabel,
            visibleOnly: options.visibleOnly,
            yRange: options.yRange.map { "\($0.lowerBound),\($0.upperBound)" },
            matchedTargets: plan.count,
            mutationRequests: mutationResponses.count,
            changedMutations: mutationResponses.filter { $0.changed ?? true }.count,
            verifiedTargets: verifiedCells,
            accuracy: plan.isEmpty ? 0 : Double(verifiedCells) / Double(plan.count),
            prevSnapshot: prevURL.path,
            nextSnapshot: nextURL.path,
            diff: diffURL.path,
            targets: targetsURL.path,
            responses: responsesURL.path,
            traceDirectory: options.traceDirectory.path
        )
        let resultData = try encoder.encode(result)
        try resultData.write(to: options.traceDirectory.appendingPathComponent("summary.json"))
        if options.outputURL != nil {
            FileHandle.standardError.write(Data((renderBatchMutationSummary(result) + "\n").utf8))
        }
        try write(data: resultData, outputURL: options.outputURL)
    }

    static func mutateConstraint(_ arguments: [String], deactivate: Bool) async throws {
        let options = try ConstraintMutationOptions(arguments, deactivate: deactivate)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let body = try encoder.encode(options.request)
        var request = URLRequest(url: host.appendingPathComponent("constraint"))
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await httpData(for: request, timeout: options.timeout, label: "constraint mutation")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("constraint mutation expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw CLIError("constraint mutation failed with HTTP \(httpResponse.statusCode): \(body)")
        }
        try write(data: data, outputURL: options.outputURL)
    }

    static func reflect(_ arguments: [String]) throws {
        let options = try MutationReflectOptions(arguments)
        let data = try Data(contentsOf: options.mutationURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let response = try? decoder.decode(LoupeMutationResponse.self, from: data) {
            let reflection = mutationReflection(response, sourceRoot: options.sourceRoot)
            try write(data: try encoder.encode(reflection), outputURL: options.outputURL)
            return
        }

        if let responses = try? decoder.decode([LoupeMutationResponse].self, from: data) {
            let reflections = responses.map { mutationReflection($0, sourceRoot: options.sourceRoot) }
            try write(data: try encoder.encode(reflections), outputURL: options.outputURL)
            return
        }

        if let batch = try? decoder.decode(BatchMutationResult.self, from: data),
           let responsesPath = batch.responses {
            let responsesURL = URL(fileURLWithPath: responsesPath)
            let responsesData = try Data(contentsOf: responsesURL)
            let responses = try decoder.decode([LoupeMutationResponse].self, from: responsesData)
            let reflections = responses.map { mutationReflection($0, sourceRoot: options.sourceRoot) }
            try write(data: try encoder.encode(reflections), outputURL: options.outputURL)
            return
        }

        if (try? decoder.decode(BatchMutationResult.self, from: data)) != nil {
            throw CLIError("reflect cannot read this set-many summary because it does not include mutation responses; rerun set-many with a current loupe build")
        }

        throw CLIError("reflect expected a mutation response, mutation response array, or set-many summary")
    }

    static func runtimes(_ arguments: [String]) async throws {
        let options = try RuntimeListOptions(arguments)
        let records = try loadRuntimeHostRecords()
        let rows = await withTaskGroup(of: (Int, RuntimeListRow).self) { group in
            for (index, record) in records.enumerated() {
                group.addTask {
                    (index, await runtimeListRow(for: record, timeout: options.timeout))
                }
            }

            var indexedRows: [(Int, RuntimeListRow)] = []
            for await row in group {
                indexedRows.append(row)
            }
            return indexedRows
                .sorted { $0.0 < $1.0 }
                .map(\.1)
        }

        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(rows))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }

        print("udid\tlive\tbundle\t host\tpid\tsimulator\tstartedAt\tupdatedAt")
        for row in rows {
            print("\(row.udid)\t\(row.live ? "yes" : "no")\t\(row.bundleID)\t\(row.host)\t\(row.pid)\t\(row.simulator)\t\(row.startedAt)\t\(row.updatedAt)")
        }
    }

    private static func runtimeListRow(for record: LoupeRuntimeHostRecord, timeout: TimeInterval) async -> RuntimeListRow {
        var live = false
        var simulator = ""
        var pid = ""
        var startedAt = ""
        var bundleID = record.bundleID
        if let host = URL(string: record.host),
           let state = try? await fetchRuntimeState(host: host, timeout: timeout) {
            live = runtimeState(state, matches: record)
            if live {
                simulator = state.identity.simulatorName ?? ""
                pid = String(state.identity.processIdentifier)
                startedAt = isoString(state.identity.startedAt)
                bundleID = state.identity.bundleIdentifier ?? bundleID
            }
        }
        return RuntimeListRow(
            udid: record.udid,
            simulator: simulator,
            bundleID: bundleID,
            host: record.host,
            pid: pid,
            live: live,
            startedAt: startedAt,
            updatedAt: isoString(record.updatedAt)
        )
    }

    static func screenshot(_ arguments: [String]) throws {
        let options = try ScreenshotOptions(arguments)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", options.udid, "screenshot", options.outputPath]
        try run(process, label: "simctl screenshot", timeout: options.timeout)
    }

    static func exploreRoutes(_ arguments: [String]) async throws {
        let options = try ExploreRoutesOptions(arguments)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }

        let runtimeState = try await fetchRuntimeState(host: host, timeout: options.timeout)
        let actionUDID = options.udid ?? runtimeState.identity.simulatorUDID ?? "booted"
        var visitedKeys = Set<String>()
        var visits: [ExploreRouteVisit] = []
        var skippedCandidates = 0
        var latestSnapshot = try await fetchSnapshot(host: host, timeout: options.timeout)

        while visits.count < options.limit {
            let candidates = ExploreRoutePlanner.candidates(
                in: latestSnapshot,
                visitedKeys: visitedKeys,
                limit: max(options.limit - visits.count, 1) + 4
            )
            guard let candidate = candidates.first else {
                break
            }
            skippedCandidates += max(0, candidates.count - 1)
            visitedKeys.insert(candidate.key)
            let beforeSnapshot = latestSnapshot

            let routeTraceDirectory = options.traceDirectory?.appendingPathComponent(
                String(format: "%02d-%@", visits.count + 1, candidate.ref),
                isDirectory: true
            )
            var afterSnapshot: LoupeSnapshot?
            var tapElapsed = 0.0
            var afterSnapshotElapsed = 0.0
            var backElapsed = 0.0
            var backSucceeded = false
            var errorMessage: String?

            do {
                tapElapsed = try await measure {
                    try await performRouteTap(
                        candidate,
                        snapshot: beforeSnapshot,
                        host: host,
                        udid: actionUDID,
                        timeout: options.timeout,
                        traceDirectory: routeTraceDirectory
                    )
                }
                try await sleep(seconds: options.settleDelay)
                (afterSnapshot, afterSnapshotElapsed) = try await measuredValue {
                    try await fetchSnapshot(host: host, timeout: options.timeout)
                }
                if let afterSnapshot {
                    backElapsed = try await measure {
                        try performRouteBack(
                            snapshot: afterSnapshot,
                            udid: actionUDID,
                            timeout: options.timeout,
                            backTestID: options.backTestID,
                            fallbackPoint: options.backPoint
                        )
                    }
                    backSucceeded = true
                    try await sleep(seconds: options.settleDelay)
                    latestSnapshot = try await fetchSnapshot(host: host, timeout: options.timeout)
                }
            } catch {
                errorMessage = String(describing: error)
            }

            visits.append(
                ExploreRouteVisit(
                    index: visits.count + 1,
                    candidate: candidate,
                    beforeSnapshotID: beforeSnapshot.id,
                    afterSnapshotID: afterSnapshot?.id,
                    beforeTitle: probableTitle(in: beforeSnapshot),
                    afterTitle: afterSnapshot.flatMap(probableTitle),
                    tapElapsed: tapElapsed,
                    afterSnapshotElapsed: afterSnapshotElapsed,
                    backElapsed: backElapsed,
                    backSucceeded: backSucceeded,
                    traceDirectory: routeTraceDirectory?.path,
                    error: errorMessage
                )
            )

            if errorMessage != nil || !backSucceeded {
                break
            }
        }

        let report = ExploreRoutesReport(
            bundleID: runtimeState.identity.bundleIdentifier ?? options.bundleID,
            host: host.absoluteString,
            udid: actionUDID,
            screen: latestSnapshot.screen,
            visited: visits,
            skippedCandidates: skippedCandidates,
            generatedAt: Date()
        )

        let data = try makeLoupeJSONEncoder().encode(report)
        if options.json || options.outputURL != nil {
            try write(data: data, outputURL: options.outputURL)
        } else {
            print(renderExploreRoutesReport(report))
        }
    }

    private static func performRouteTap(
        _ candidate: ExploreRouteCandidate,
        snapshot: LoupeSnapshot,
        host: URL,
        udid: String,
        timeout: TimeInterval,
        traceDirectory: URL?
    ) async throws {
        if let traceDirectory {
            try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
            try await action(command: "tap", arguments: [
                "--host", host.absoluteString,
                "--udid", udid,
                "--ref", candidate.ref,
                "--trace-dir", traceDirectory.path,
                "--timeout", String(timeout),
            ])
            return
        }

        let options = try ActionOptions(command: "tap", arguments: [
            "--udid", udid,
            "--x", String(candidate.center.x),
            "--y", String(candidate.center.y),
            "--width", String(snapshot.screen.size.width),
            "--height", String(snapshot.screen.size.height),
            "--timeout", String(timeout),
        ])
        let target = ActionTarget(
            point: candidate.center,
            screen: snapshot.screen.size,
            screenScale: snapshot.screen.scale,
            source: .view(ref: candidate.ref)
        )
        try dispatchAction(command: "tap", options: options, target: target)
    }

    private static func performRouteBack(
        snapshot: LoupeSnapshot,
        udid: String,
        timeout: TimeInterval,
        backTestID: String?,
        fallbackPoint: LoupePoint
    ) throws {
        let point = backTestID.flatMap { backPoint(in: snapshot, testID: $0) } ?? fallbackPoint
        let options = try ActionOptions(command: "tap", arguments: [
            "--udid", udid,
            "--x", String(point.x),
            "--y", String(point.y),
            "--width", String(snapshot.screen.size.width),
            "--height", String(snapshot.screen.size.height),
            "--timeout", String(timeout),
        ])
        let target = ActionTarget(
            point: point,
            screen: snapshot.screen.size,
            screenScale: snapshot.screen.scale,
            source: .coordinates
        )
        try dispatchAction(command: "tap", options: options, target: target)
    }

    private static func backPoint(in snapshot: LoupeSnapshot, testID: String) -> LoupePoint? {
        snapshot.nodes.values
            .filter { $0.isVisible && $0.isEnabled && $0.testID == testID }
            .sorted { lhs, rhs in
                guard let lhsFrame = lhs.frame else { return false }
                guard let rhsFrame = rhs.frame else { return true }
                if abs(lhsFrame.y - rhsFrame.y) > 1 {
                    return lhsFrame.y < rhsFrame.y
                }
                return lhsFrame.x < rhsFrame.x
            }
            .compactMap { center(of: $0.frame) }
            .first
    }

    private static func probableTitle(in snapshot: LoupeSnapshot) -> String? {
        let screen = snapshot.screen.size
        let textNodes = snapshot.nodes.values.compactMap { node -> (String, LoupeRect)? in
            guard node.isVisible, let frame = node.frame, let text = displayText(node), !text.isEmpty else {
                return nil
            }
            return (text, frame)
        }

        let topTextNodes = textNodes.filter { _, frame in
            frame.y >= 40
                && frame.y <= 150
                && frame.x >= 0
                && frame.maxX <= screen.width
                && frame.width <= screen.width * 0.85
        }
        let sortedTopTextNodes = topTextNodes.sorted { lhs, rhs in
            if abs(lhs.1.y - rhs.1.y) > 1 {
                return lhs.1.y < rhs.1.y
            }
            return abs((lhs.1.x + lhs.1.width / 2) - screen.width / 2)
                < abs((rhs.1.x + rhs.1.width / 2) - screen.width / 2)
        }
        if let title = sortedTopTextNodes.first?.0 {
            return title
        }

        return textNodes
            .sorted { lhs, rhs in
                if abs(lhs.1.y - rhs.1.y) > 1 {
                    return lhs.1.y < rhs.1.y
                }
                return lhs.1.x < rhs.1.x
            }
            .first?.0
    }

    private static func measuredValue<T>(_ operation: () async throws -> T) async throws -> (T, Double) {
        let start = Date()
        let value = try await operation()
        return (value, Date().timeIntervalSince(start))
    }

    private static func measure(_ operation: () async throws -> Void) async throws -> Double {
        let start = Date()
        try await operation()
        return Date().timeIntervalSince(start)
    }

    private static func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func renderExploreRoutesReport(_ report: ExploreRoutesReport) -> String {
        var lines = [
            "debug trace explore host=\(report.host) udid=\(report.udid) screen=\(format(report.screen.size.width))x\(format(report.screen.size.height))",
        ]
        if let bundleID = report.bundleID {
            lines[0] += " bundle=\(bundleID)"
        }
        for visit in report.visited {
            var parts = [
                "\(visit.index).",
                visit.candidate.ref,
                visit.candidate.reason,
                "frame=\(format(visit.candidate.frame))",
                "tap=\(format(visit.tapElapsed))s",
                "snapshot=\(format(visit.afterSnapshotElapsed))s",
                "back=\(format(visit.backElapsed))s",
            ]
            if let text = visit.candidate.text {
                parts.append("text=\"\(text)\"")
            }
            if let title = visit.afterTitle {
                parts.append("after=\"\(title)\"")
            }
            if let error = visit.error {
                parts.append("error=\"\(error)\"")
            } else if !visit.backSucceeded {
                parts.append("back=failed")
            }
            lines.append(parts.joined(separator: " "))
        }
        if report.visited.isEmpty {
            lines.append("No visible route-like candidates found.")
        }
        return lines.joined(separator: "\n")
    }

    static func action(command: String, arguments: [String]) async throws {
        var options = try ActionOptions(command: command, arguments: arguments)
        try validateActionBackend(options.backend)
        var target: ActionTarget?
        do {
            if command == "tap",
               let point = options.point,
               options.screen.width > 0,
               options.screen.height > 0,
               options.traceDirectory == nil,
               !options.hostWasExplicit,
               options.expectVisibleSelector == nil {
                let coordinateTarget = ActionTarget(point: point, screen: options.screen, screenScale: 1, source: .coordinates)
                target = coordinateTarget
                try dispatchAction(command: command, options: options, target: coordinateTarget)
                return
            }

            options.host = try await resolvedRuntimeHost(
                requestedHost: options.host,
                hostWasExplicit: options.hostWasExplicit,
                udid: options.udid
            )
            let runtimeState = try await fetchRuntimeState(host: options.host, timeout: options.timeout)
            options.backend = resolvedActionBackend(
                requested: options.backend,
                command: command,
                hostWasExplicit: options.hostWasExplicit,
                runtimeIdentity: runtimeState.identity
            )
            let usesRuntimeActivation = options.backend == "runtime"
            if usesRuntimeActivation && command != "tap" {
                throw CLIError("runtime action backend currently supports tap only")
            }
            if !usesRuntimeActivation {
                try validateRuntimeIdentity(state: runtimeState, expectedUDID: options.udid, host: options.host)
            }
            if let traceDirectory = options.traceDirectory {
                try prepareTraceDirectory(traceDirectory)
                try await writePreActionTrace(command: command, options: options, traceDirectory: traceDirectory)
            }
            let resolvedTarget = try await resolveActionTarget(options)
            target = resolvedTarget
            let scrollBaseline = try await scrollVerificationBaseline(
                command: command,
                options: options,
                target: resolvedTarget
            )
            if let traceDirectory = options.traceDirectory {
                try writeActionRecord(
                    command: command,
                    options: options,
                    target: resolvedTarget,
                    phase: "target",
                    to: traceDirectory.appendingPathComponent("action-target.json")
                )
            }
            if usesRuntimeActivation {
                try await dispatchRuntimeActivation(options: options, target: resolvedTarget)
            } else {
                try dispatchAction(command: command, options: options, target: resolvedTarget)
            }
            try await verifyRuntimeAlive(host: options.host, timeout: options.timeout)
            if let scrollBaseline {
                try await verifyScrollChanged(scrollBaseline, host: options.host, timeout: options.timeout)
            }
            if let expected = options.expectVisibleSelector {
                try await expectVisible(expected, host: options.host, timeout: options.timeout)
            }
            if let traceDirectory = options.traceDirectory {
                try await Task.sleep(nanoseconds: 250_000_000)
                try await writePostActionTrace(command: command, options: options, target: resolvedTarget, traceDirectory: traceDirectory)
            }
        } catch {
            let traceDirectory = options.traceDirectory ?? automaticTraceDirectory(command: command)
            try? prepareTraceDirectory(traceDirectory)
            try? await writeFailureTrace(
                command: command,
                options: options,
                target: target,
                error: error,
                traceDirectory: traceDirectory
            )
            if options.traceDirectory == nil {
                FileHandle.standardError.write(Data("trace: \(traceDirectory.path)\n".utf8))
            }
            throw error
        }
    }

    private static func scrollVerificationBaseline(
        command: String,
        options: ActionOptions,
        target: ActionTarget
    ) async throws -> GestureScrollBaseline? {
        guard command == "swipe", options.verifyScroll, let endPoint = options.endPoint else {
            return nil
        }
        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        return GestureScrollVerifier.baseline(in: snapshot, start: target.point, end: endPoint)
    }

    private static func verifyScrollChanged(
        _ baseline: GestureScrollBaseline,
        host: URL,
        timeout: TimeInterval
    ) async throws {
        try await Task.sleep(nanoseconds: 250_000_000)
        let after = try await fetchSnapshot(host: host, timeout: timeout)
        guard GestureScrollVerifier.didChange(baseline, after: after) else {
            throw CLIError(GestureScrollVerifier.diagnostic(baseline))
        }
    }

    static func waitFor(_ arguments: [String], mode: WaitMode) async throws {
        let options = try WaitForOptions(arguments, mode: mode)
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }
        let deadline = Date().addingTimeInterval(options.timeout)

        while true {
            let snapshot = try await fetchSnapshot(host: host, timeout: min(3, options.timeout))
            let accessibilityTree = try await fetchAccessibilityTree(
                host: host,
                fallbackSnapshot: snapshot,
                timeout: min(3, options.timeout)
            )
            let accessibilityResult = LoupeAccessibilityTreeQuery.first(
                options.selector,
                in: accessibilityTree,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            )
            let viewResult = LoupeSnapshotQuery.first(
                options.selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            )

            switch mode {
            case .visible:
                if let result = accessibilityResult {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(result)
                    if let outputURL = options.outputURL {
                        FileHandle.standardError.write(Data("wait-for-visible matched accessibility ref=\(result.ref) output=\(outputURL.path)\n".utf8))
                        try write(data: data, outputURL: outputURL)
                    } else {
                        FileHandle.standardOutput.write(data)
                        FileHandle.standardOutput.write(Data("\n".utf8))
                    }
                    return
                }
                if let result = viewResult {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(result)
                    if let outputURL = options.outputURL {
                        FileHandle.standardError.write(Data("wait-for-visible matched view ref=\(result.ref) output=\(outputURL.path)\n".utf8))
                        try write(data: data, outputURL: outputURL)
                    } else {
                        FileHandle.standardOutput.write(data)
                        FileHandle.standardOutput.write(Data("\n".utf8))
                    }
                    return
                }
            case .gone:
                if accessibilityResult == nil, viewResult == nil {
                    print(#"{"status":"gone"}"#)
                    return
                }
            case .value:
                guard let keyPath = options.keyPath, let expectedValue = options.expectedValue else {
                    throw CLIError("act wait value requires --key <path> and --equals <value>")
                }
                if let node = firstMatchingNode(options.selector, in: snapshot),
                   let value = jsonValue(in: node, keyPath: keyPath),
                   valueMatches(value, expected: expectedValue) {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(node)
                    if let outputURL = options.outputURL {
                        FileHandle.standardError.write(Data((renderWaitForValueSummary(node: node, keyPath: keyPath, value: value, outputURL: outputURL) + "\n").utf8))
                        try write(data: data, outputURL: outputURL)
                    } else {
                        FileHandle.standardOutput.write(data)
                        FileHandle.standardOutput.write(Data("\n".utf8))
                    }
                    return
                }
            }

            guard Date() < deadline else {
                switch mode {
                case .visible:
                    throw CLIError("Timed out waiting for visible Loupe node")
                case .gone:
                    throw CLIError("Timed out waiting for Loupe node to disappear")
                case .value:
                    throw CLIError("Timed out waiting for Loupe node value")
                }
            }

            try await Task.sleep(nanoseconds: UInt64(options.interval * 1_000_000_000))
        }
    }

    private static func expectVisible(_ selector: LoupeSelector, host: URL, timeout: TimeInterval) async throws {
        let options = WaitForOptions(
            host: host,
            hostWasExplicit: true,
            selector: selector,
            timeout: timeout,
            interval: 0.25,
            keyPath: nil,
            expectedValue: nil
        )
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            let snapshot = try await fetchSnapshot(host: options.host, timeout: min(3, options.timeout))
            let accessibilityTree = try await fetchAccessibilityTree(
                host: options.host,
                fallbackSnapshot: snapshot,
                timeout: min(3, options.timeout)
            )
            if LoupeAccessibilityTreeQuery.first(
                options.selector,
                in: accessibilityTree,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            ) != nil {
                return
            }
            if LoupeSnapshotQuery.first(
                options.selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
            ) != nil {
                return
            }
            guard Date() < deadline else {
                throw CLIError("Timed out waiting for expected visible Loupe node: \(selectorDescription(selector))")
            }
            try await Task.sleep(nanoseconds: UInt64(options.interval * 1_000_000_000))
        }
    }

    private static func resolveActionTarget(_ options: ActionOptions) async throws -> ActionTarget {
        if let point = options.point {
            let screen = try await resolveActionScreen(options)
            return ActionTarget(point: point, screen: screen.size, screenScale: screen.scale, source: .coordinates)
        }

        guard let selector = options.selector else {
            if options.command == "type" {
                return ActionTarget(
                    point: LoupePoint(x: 0, y: 0),
                    screen: options.screen,
                    screenScale: 1,
                    source: .keyboardFocus
                )
            }
            if options.command == "press" {
                let screen = try await resolveActionScreen(options)
                return ActionTarget(
                    point: LoupePoint(x: 0, y: 0),
                    screen: screen.size,
                    screenScale: screen.scale,
                    source: .remotePress(button: options.press ?? "unknown")
                )
            }
            throw CLIError("\(options.command) requires a selector or coordinates")
        }

        let snapshot: LoupeSnapshot
        if let snapshotURL = options.snapshotURL {
            snapshot = try decodeSnapshot(from: snapshotURL)
        } else {
            snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        }
        let accessibilityTree: LoupeAccessibilityTree
        if options.snapshotURL != nil {
            accessibilityTree = LoupeAccessibilityTree.build(from: snapshot)
        } else {
            accessibilityTree = try await fetchAccessibilityTree(
                host: options.host,
                fallbackSnapshot: snapshot,
                timeout: options.timeout
            )
        }
        let accessibilityMatches = preferPlatformBackedActionMatches(
            uniqueActionMatches(
                LoupeAccessibilityTreeQuery.find(
                    selector,
                    in: accessibilityTree,
                    options: LoupeQueryOptions(includeHidden: false, includeDisabled: false, maxResults: 8)
                )
            ),
            snapshot: snapshot
        )
        if accessibilityMatches.count > 1 {
            throw CLIError("Selector matched multiple accessibility nodes: \(matchSummary(accessibilityMatches))")
        }
        if let result = accessibilityMatches.first,
           let point = result.activationPoint ?? center(of: result.frame) {
            return ActionTarget(
                point: point,
                screen: snapshot.screen.size,
                screenScale: snapshot.screen.scale,
                source: .accessibility(ref: result.ref, sourceRef: result.sourceRef),
                match: .accessibility(result)
            )
        }

        let viewMatches = preferPlatformBackedActionMatches(
            uniqueActionMatches(
                LoupeSnapshotQuery.find(
                    selector,
                    in: snapshot,
                    options: LoupeQueryOptions(includeHidden: false, includeDisabled: false, maxResults: 8)
                )
            ),
            snapshot: snapshot
        )
        if viewMatches.count > 1 {
            throw CLIError("Selector matched multiple view nodes: \(matchSummary(viewMatches))")
        }
        guard let result = viewMatches.first else {
            throw CLIError("No Loupe accessibility or view node matched selector")
        }
        guard let point = center(of: result.frame) else {
            throw CLIError("Matched node has no frame: \(result.ref)")
        }

        return ActionTarget(
            point: point,
            screen: snapshot.screen.size,
            screenScale: snapshot.screen.scale,
            source: .view(ref: result.ref),
            match: .view(result)
        )
    }

    private static func resolveActionScreen(_ options: ActionOptions) async throws -> (size: LoupeSize, scale: Double) {
        if let screen = ActionScreenResolver.explicit(options.screen) {
            return (screen.size, screen.scale)
        }

        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        let screen = ActionScreenResolver.resolve(explicit: options.screen, fallback: snapshot.screen)
        return (screen.size, screen.scale)
    }

    private static func center(of frame: LoupeRect?) -> LoupePoint? {
        guard let frame else {
            return nil
        }
        return LoupePoint(x: frame.x + frame.width / 2, y: frame.y + frame.height / 2)
    }

    private static func uniqueActionMatches(
        _ matches: [LoupeAccessibilityQueryResult]
    ) -> [LoupeAccessibilityQueryResult] {
        var seen = Set<String>()
        return matches.filter { match in
            seen.insert(actionEquivalenceKey(match)).inserted
        }
    }

    private static func uniqueActionMatches(_ matches: [LoupeQueryResult]) -> [LoupeQueryResult] {
        var seen = Set<String>()
        return matches.filter { match in
            seen.insert(actionEquivalenceKey(match)).inserted
        }
    }

    static func preferPlatformBackedActionMatches(
        _ matches: [LoupeAccessibilityQueryResult],
        snapshot: LoupeSnapshot
    ) -> [LoupeAccessibilityQueryResult] {
        preferPlatformBackedActionMatches(
            matches,
            snapshot: snapshot,
            sourceRef: \.sourceRef,
            semanticKey: actionSemanticKey
        )
    }

    static func preferPlatformBackedActionMatches(
        _ matches: [LoupeQueryResult],
        snapshot: LoupeSnapshot
    ) -> [LoupeQueryResult] {
        LoupeSnapshotQuery.preferPlatformBackedMatches(matches, in: snapshot)
    }

    private static func preferPlatformBackedActionMatches<Match>(
        _ matches: [Match],
        snapshot: LoupeSnapshot,
        sourceRef: KeyPath<Match, String>,
        semanticKey: (Match) -> String
    ) -> [Match] {
        let grouped = Dictionary(grouping: matches, by: semanticKey)
        let keysWithPlatformBackedAlternative = Set(grouped.compactMap { key, group -> String? in
            let platformBacked = group.filter {
                !LoupeSnapshotQuery.isSyntheticRegisteredProbeSource($0[keyPath: sourceRef], in: snapshot)
            }
            let synthetic = group.count - platformBacked.count
            if !platformBacked.isEmpty, synthetic > 0 {
                return key
            }
            return nil
        })

        return matches.filter { match in
            let key = semanticKey(match)
            guard keysWithPlatformBackedAlternative.contains(key) else {
                return true
            }
            return !LoupeSnapshotQuery.isSyntheticRegisteredProbeSource(match[keyPath: sourceRef], in: snapshot)
        }
    }

    private static func actionEquivalenceKey(_ match: LoupeAccessibilityQueryResult) -> String {
        [
            match.role ?? "",
            match.testID ?? "",
            match.text ?? "",
            geometryKey(frame: match.frame, activationPoint: match.activationPoint),
        ].joined(separator: "|")
    }

    private static func actionEquivalenceKey(_ match: LoupeQueryResult) -> String {
        [
            match.role ?? "",
            match.testID ?? "",
            match.text ?? "",
            geometryKey(frame: match.frame, activationPoint: nil),
        ].joined(separator: "|")
    }

    private static func actionSemanticKey(_ match: LoupeAccessibilityQueryResult) -> String {
        [
            match.role ?? "",
            match.testID ?? "",
            match.text ?? "",
        ].joined(separator: "|")
    }

    private static func geometryKey(frame: LoupeRect?, activationPoint: LoupePoint?) -> String {
        let frameKey: String
        if let frame {
            frameKey = [frame.x, frame.y, frame.width, frame.height].map(roundedKey).joined(separator: ",")
        } else {
            frameKey = "nil"
        }
        let pointKey: String
        if let activationPoint {
            pointKey = [activationPoint.x, activationPoint.y].map(roundedKey).joined(separator: ",")
        } else {
            pointKey = "nil"
        }
        return "\(frameKey)|\(pointKey)"
    }

    private static func roundedKey(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func matchSummary(_ matches: [LoupeAccessibilityQueryResult]) -> String {
        matches
            .map { "\($0.ref)\($0.testID.map { "#\($0)" } ?? "")\($0.text.map { " \"\($0)\"" } ?? "")" }
            .joined(separator: ", ")
    }

    private static func matchSummary(_ matches: [LoupeQueryResult]) -> String {
        matches
            .map { "\($0.ref)\($0.testID.map { "#\($0)" } ?? "")\($0.text.map { " \"\($0)\"" } ?? "")" }
            .joined(separator: ", ")
    }

    private static func fetchSnapshot(host: URL, timeout: TimeInterval = 5) async throws -> LoupeSnapshot {
        let url = host.appendingPathComponent("snapshot")
        let (data, response) = try await httpData(from: url, timeout: timeout, label: "snapshot fetch")
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("snapshot fetch failed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeSnapshot.self, from: data)
    }

    private static func postMutation(
        _ mutation: LoupeMutationRequest,
        host: URL,
        timeout: TimeInterval
    ) async throws -> LoupeMutationResponse {
        let body = try makeLoupeJSONEncoder().encode(mutation)
        var request = URLRequest(url: host.appendingPathComponent("mutate"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await httpData(for: request, timeout: timeout, label: "mutation")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("mutation expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw CLIError("mutation failed with HTTP \(httpResponse.statusCode): \(body)")
        }
        return try JSONDecoder().decode(LoupeMutationResponse.self, from: data)
    }

    private static func postActivation(
        _ activation: LoupeActivationRequest,
        host: URL,
        timeout: TimeInterval
    ) async throws -> LoupeActivationResponse {
        let body = try makeLoupeJSONEncoder().encode(activation)
        var request = URLRequest(url: host.appendingPathComponent("activate"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await httpData(for: request, timeout: timeout, label: "activation")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("activation expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(decoding: data, as: UTF8.self)
            throw CLIError("activation failed with HTTP \(httpResponse.statusCode): \(body)")
        }
        return try JSONDecoder().decode(LoupeActivationResponse.self, from: data)
    }

    private static func writeSnapshot(_ snapshot: LoupeSnapshot, to url: URL) throws {
        try makeLoupeJSONEncoder().encode(snapshot).write(to: url)
    }

    private static func filteredInspectionData(_ data: Data, fields: Set<String>) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        object = object.filter { fields.contains($0.key) }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    private static func makeLoupeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func colorsMatch(_ lhs: LoupeColor, _ rhs: LoupeColor, tolerance: Double = 0.01) -> Bool {
        abs(lhs.red - rhs.red) <= tolerance
            && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
            && abs(lhs.alpha - rhs.alpha) <= tolerance
    }

    private static func batchMutationVerified(
        _ target: BatchMutationPlan,
        after: LoupeSnapshot,
        property: String,
        responses: [LoupeMutationResponse]
    ) -> Bool {
        let normalizedProperty = normalizedCLIProperty(property)
        let snapshotVerified = target.mutationRefs.contains { ref in
            guard let node = after.nodes[ref],
                  let actual = snapshotMutationValue(property: normalizedProperty, node: node) else {
                return false
            }
            return mutationValuesMatch(actual, target.value)
        }
        if snapshotVerified {
            return true
        }

        return target.mutationRefs.contains { ref in
            responses.contains { response in
                response.target.ref == ref && (response.changed ?? true)
            }
        }
    }

    private static func snapshotMutationValue(property: String, node: LoupeNode) -> LoupeMutationValue? {
        switch property {
        case "backgroundcolor", "stylebackgroundcolor":
            return node.style?.backgroundColor.map(LoupeMutationValue.color)
        case "alpha", "stylealpha", "uikitalpha":
            return node.style?.alpha.map(LoupeMutationValue.double)
        case "hidden", "ishidden", "uikitishidden":
            return .bool(!node.isVisible)
        case "frame":
            return node.frame.map(LoupeMutationValue.rect)
        default:
            return nil
        }
    }

    private static func mutationValuesMatch(_ lhs: LoupeMutationValue, _ rhs: LoupeMutationValue, tolerance: Double = 0.01) -> Bool {
        switch (lhs, rhs) {
        case let (.bool(lhs), .bool(rhs)):
            return lhs == rhs
        case let (.int(lhs), .int(rhs)):
            return lhs == rhs
        case let (.double(lhs), .double(rhs)):
            return abs(lhs - rhs) <= tolerance
        case let (.int(lhs), .double(rhs)):
            return abs(Double(lhs) - rhs) <= tolerance
        case let (.double(lhs), .int(rhs)):
            return abs(lhs - Double(rhs)) <= tolerance
        case let (.string(lhs), .string(rhs)):
            return lhs == rhs
        case let (.color(lhs), .color(rhs)):
            return colorsMatch(lhs, rhs, tolerance: tolerance)
        case let (.rect(lhs), .rect(rhs)):
            return abs(lhs.x - rhs.x) <= tolerance
                && abs(lhs.y - rhs.y) <= tolerance
                && abs(lhs.width - rhs.width) <= tolerance
                && abs(lhs.height - rhs.height) <= tolerance
        default:
            return false
        }
    }

    private static func normalizedCLIProperty(_ property: String) -> String {
        property
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func fetchAccessibilityTree(
        host: URL,
        fallbackSnapshot: LoupeSnapshot,
        timeout: TimeInterval = 5
    ) async throws -> LoupeAccessibilityTree {
        let url = host.appendingPathComponent("accessibility")
        do {
            let (data, response) = try await httpData(from: url, timeout: timeout, label: "accessibility fetch")
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                return LoupeAccessibilityTree.build(from: fallbackSnapshot)
            }
            return try JSONDecoder().decode(LoupeAccessibilityTree.self, from: data)
        } catch {
            return LoupeAccessibilityTree.build(from: fallbackSnapshot)
        }
    }

    static func fetchRuntimeState(host: URL, timeout: TimeInterval = 5) async throws -> LoupeRuntimeState {
        let url = host.appendingPathComponent("runtime")
        let (data, response) = try await httpData(from: url, timeout: timeout, label: "runtime fetch")
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime fetch failed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeRuntimeState.self, from: data)
    }

    static func resolvedActionBackend(
        requested: String,
        command: String,
        hostWasExplicit: Bool,
        runtimeIdentity: LoupeRuntimeIdentity
    ) -> String {
        guard requested == "auto", command == "tap", hostWasExplicit else {
            return requested
        }
        if let simulatorUDID = runtimeIdentity.simulatorUDID, !simulatorUDID.isEmpty {
            return "auto"
        }
        return "runtime"
    }

    static func validateRuntimeIdentity(host: URL, expectedUDID: String, timeout: TimeInterval = 5) async throws {
        let state = try await fetchRuntimeState(host: host, timeout: timeout)
        try validateRuntimeIdentity(state: state, expectedUDID: expectedUDID, host: host)
    }

    static func validateRuntimeIdentity(state: LoupeRuntimeState, expectedUDID: String, host: URL? = nil) throws {
        let expected = try resolvedBackendUDID(expectedUDID)
        let actual = state.identity.deviceIdentifier ?? state.identity.simulatorUDID
        guard let actual, !actual.isEmpty else {
            throw CLIError("Loupe runtime did not report a simulator or device identifier; cannot validate --udid \(expected)")
        }
        guard actual == expected else {
            let bundle = state.identity.bundleIdentifier ?? "unknown-bundle"
            let location = host?.absoluteString ?? "selected host"
            throw CLIError(
                "Loupe runtime at \(location) is \(bundle) on device \(actual), not requested --udid \(expected)"
            )
        }
    }

    private static func verifyRuntimeAlive(host: URL, timeout: TimeInterval) async throws {
        _ = try await fetchRuntimeState(host: host, timeout: timeout)
    }

    private static func waitForRuntime(host: URL, expectedUDID: String, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        repeat {
            do {
                try await validateRuntimeIdentity(host: host, expectedUDID: expectedUDID, timeout: min(1, timeout))
                return
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        } while Date() < deadline

        throw CLIError("Timed out waiting for Loupe runtime at \(host.absoluteString): \(lastError.map(String.init(describing:)) ?? "no response")")
    }

    private static func waitForRuntimeHost(host: URL, expectedDeviceID: String?, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?

        repeat {
            do {
                let state = try await fetchRuntimeState(host: host, timeout: min(1, timeout))
                if let expectedDeviceID,
                   let actual = state.identity.deviceIdentifier ?? state.identity.simulatorUDID,
                   actual != expectedDeviceID {
                    throw CLIError("Loupe runtime at \(host.absoluteString) is device \(actual), not requested device \(expectedDeviceID)")
                }
                return
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        } while Date() < deadline

        throw CLIError("Timed out waiting for Loupe runtime at \(host.absoluteString): \(lastError.map(String.init(describing:)) ?? "no response")")
    }

    private static func resolvedLoupePort(for _: String, environment: [String: String]) throws -> UInt16 {
        if let rawPort = environment["LOUPE_PORT"] {
            guard let port = UInt16(rawPort), port > 0 else {
                throw CLIError("LOUPE_PORT must be a valid TCP port")
            }
            return port
        }

        return try randomAvailableLoupePort()
    }

    private static func randomAvailableLoupePort() throws -> UInt16 {
        for _ in 0..<100 {
            let port = UInt16.random(in: 10_000...60_999)
            if isLocalhostPortAvailable(port) {
                return port
            }
        }
        throw CLIError("Could not find an available local port for Loupe runtime injection.")
    }

    private static func isLocalhostPortAvailable(_ port: UInt16) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private static func validateLaunchPort(host: URL, expectedUDID: String, expectedBundleID: String) throws {
        var request = URLRequest(url: host.appendingPathComponent("runtime"))
        request.timeoutInterval = 0.75
        let semaphore = DispatchSemaphore(value: 0)
        let probe = LaunchPortProbe()
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                probe.result = .failure(error)
                return
            }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                probe.result = .failure(CLIError("port is occupied by a non-Loupe HTTP service"))
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            probe.result = Result { try decoder.decode(LoupeRuntimeState.self, from: data) }
        }.resume()

        guard semaphore.wait(timeout: .now() + 1) == .success, let result = probe.result else {
            return
        }

        switch result {
        case let .success(state):
            guard state.identity.simulatorUDID == expectedUDID else {
                let actual = state.identity.simulatorUDID ?? "unknown"
                throw CLIError("Loupe port collision at \(host.absoluteString): running simulator \(actual), requested \(expectedUDID)")
            }
            guard state.identity.bundleIdentifier == expectedBundleID else {
                let actual = state.identity.bundleIdentifier ?? "unknown"
                throw CLIError("Loupe port collision at \(host.absoluteString): running bundle \(actual), requested \(expectedBundleID)")
            }
        case let .failure(error as CLIError):
            throw error
        case .failure:
            return
        }
    }

    static func simctlTerminateTimeout(
        launchTimeout: TimeInterval,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        guard
            let raw = environment["LOUPE_SIMCTL_TERMINATE_TIMEOUT"],
            let value = TimeInterval(raw),
            value > 0
        else {
            return launchTimeout
        }
        return value
    }

    private static func terminateAppIfRunning(device: String, bundleID: String, timeout: TimeInterval) throws {
        let attempts = 2
        for attempt in 1...attempts {
            if try runTerminateApp(device: device, bundleID: bundleID, timeout: timeout) {
                return
            }
            if attempt < attempts {
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        FileHandle.standardError.write(
            Data("warning: simctl terminate timed out after \(format(timeout))s for \(bundleID) on \(device); continuing to launch\n".utf8)
        )
    }

    private static func runTerminateApp(device: String, bundleID: String, timeout: TimeInterval) throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "terminate", device, bundleID]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        try process.run()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return false
        }
        return true
    }

    private static func prepareTraceDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func writePreActionTrace(
        command: String,
        options: ActionOptions,
        traceDirectory: URL
    ) async throws {
        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        try writeJSON(snapshot, to: traceDirectory.appendingPathComponent("before-snapshot.json"))
        try writeJSON(
            try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot, timeout: options.timeout),
            to: traceDirectory.appendingPathComponent("before-accessibility.json")
        )
        try? await writeRuntimeTracePayload(
            host: options.host,
            path: "logs",
            to: traceDirectory.appendingPathComponent("before-logs.json")
        )
        try writeActionRecord(
            command: command,
            options: options,
            target: nil,
            phase: "before",
            to: traceDirectory.appendingPathComponent("action-before.json")
        )

        if options.backend != "runtime" {
            let udid = try resolvedBackendUDID(options.udid)
            try captureSimulatorScreenshot(
                udid: udid,
                outputURL: traceDirectory.appendingPathComponent("before.png")
            )
        }
    }

    private static func writePostActionTrace(
        command: String,
        options: ActionOptions,
        target: ActionTarget,
        traceDirectory: URL
    ) async throws {
        let snapshot = try await fetchSnapshot(host: options.host, timeout: options.timeout)
        try writeJSON(snapshot, to: traceDirectory.appendingPathComponent("after-snapshot.json"))
        try writeJSON(
            try await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot, timeout: options.timeout),
            to: traceDirectory.appendingPathComponent("after-accessibility.json")
        )
        try? await writeRuntimeTracePayload(
            host: options.host,
            path: "logs",
            to: traceDirectory.appendingPathComponent("after-logs.json")
        )
        try writeActionRecord(
            command: command,
            options: options,
            target: target,
            phase: "after",
            to: traceDirectory.appendingPathComponent("action-after.json")
        )

        if options.backend != "runtime" {
            let udid = try resolvedBackendUDID(options.udid)
            let screenshotURL = traceDirectory.appendingPathComponent("after.png")
            try captureSimulatorScreenshot(udid: udid, outputURL: screenshotURL)
            try? cropTargetImage(
                target: target,
                screenshotURL: screenshotURL,
                outputURL: traceDirectory.appendingPathComponent("target-crop.png")
            )
        }
    }

    private static func writeFailureTrace(
        command: String,
        options: ActionOptions,
        target: ActionTarget?,
        error: Error,
        traceDirectory: URL
    ) async throws {
        try writeJSON(
            LoupeCLIActionErrorTrace(message: String(describing: error), recordedAt: Date()),
            to: traceDirectory.appendingPathComponent("error.json")
        )
        try writeActionRecord(
            command: command,
            options: options,
            target: target,
            phase: "failure",
            to: traceDirectory.appendingPathComponent("action-failure.json")
        )
        if let snapshot = try? await fetchSnapshot(host: options.host, timeout: min(3, options.timeout)) {
            try? writeJSON(snapshot, to: traceDirectory.appendingPathComponent("failure-snapshot.json"))
            if let tree = try? await fetchAccessibilityTree(host: options.host, fallbackSnapshot: snapshot, timeout: min(3, options.timeout)) {
                try? writeJSON(tree, to: traceDirectory.appendingPathComponent("failure-accessibility.json"))
            }
        }
        try? await writeRuntimeTracePayload(
            host: options.host,
            path: "logs",
            to: traceDirectory.appendingPathComponent("failure-logs.json")
        )
        if let udid = try? resolvedBackendUDID(options.udid) {
            let screenshotURL = traceDirectory.appendingPathComponent("failure.png")
            try? captureSimulatorScreenshot(udid: udid, outputURL: screenshotURL)
            if let target {
                try? cropTargetImage(
                    target: target,
                    screenshotURL: screenshotURL,
                    outputURL: traceDirectory.appendingPathComponent("target-crop.png")
                )
            }
        }
    }

    private static func automaticTraceDirectory(command: String) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return traceRootDirectory()
            .appendingPathComponent("\(stamp)-\(command)", isDirectory: true)
    }

    private static func writeActionRecord(
        command: String,
        options: ActionOptions,
        target: ActionTarget?,
        phase: String,
        to url: URL
    ) throws {
        let record = LoupeCLIActionTrace(
            command: command,
            phase: phase,
            host: options.host.absoluteString,
            backend: options.backend,
            udid: options.udid,
            selector: options.selector.map(selectorDescription),
            point: options.point,
            endPoint: options.endPoint,
            duration: options.duration,
            text: ActionTraceText.recordable(command: command, text: options.text),
            press: options.press,
            resolvedPoint: target?.point,
            resolvedScreen: target?.screen,
            coordinateUnit: target == nil ? nil : "points",
            resolvedScreenScale: target?.screenScale,
            resolvedSource: target?.source.description,
            resolvedTarget: target?.match?.trace,
            recordedAt: Date()
        )
        try writeJSON(record, to: url)
    }

    private static func captureSimulatorScreenshot(udid: String, outputURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "screenshot", "--type=png", outputURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try run(process, label: "simctl screenshot", timeout: 10)
    }

    private static func cropTargetImage(
        target: ActionTarget,
        screenshotURL: URL,
        outputURL: URL
    ) throws {
        guard let frame = target.match?.trace.frame, !frame.isEmpty else {
            return
        }
        let pixelSize = try pngPixelSize(screenshotURL)
        let scaleX = pixelSize.width / max(target.screen.width, 1)
        let scaleY = pixelSize.height / max(target.screen.height, 1)
        let padding: Double = 8
        let x = max(0, Int(((frame.x - padding) * scaleX).rounded(.down)))
        let y = max(0, Int(((frame.y - padding) * scaleY).rounded(.down)))
        let maxWidth = max(1, Int(pixelSize.width) - x)
        let maxHeight = max(1, Int(pixelSize.height) - y)
        let width = min(maxWidth, max(1, Int(((frame.width + padding * 2) * scaleX).rounded(.up))))
        let height = min(maxHeight, max(1, Int(((frame.height + padding * 2) * scaleY).rounded(.up))))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = [
            screenshotURL.path,
            "--cropToHeightWidth", String(height), String(width),
            "--cropOffset", String(y), String(x),
            "--out", outputURL.path,
        ]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try run(process, label: "sips crop", timeout: 5)
    }

    private static func pngPixelSize(_ url: URL) throws -> LoupeSize {
        let data = try Data(contentsOf: url)
        guard data.count >= 24 else {
            throw CLIError("Could not read PNG size")
        }
        let width = UInt32(data[16]) << 24
            | UInt32(data[17]) << 16
            | UInt32(data[18]) << 8
            | UInt32(data[19])
        let height = UInt32(data[20]) << 24
            | UInt32(data[21]) << 16
            | UInt32(data[22]) << 8
            | UInt32(data[23])
        return LoupeSize(width: Double(width), height: Double(height))
    }

    private static func writeRuntimeTracePayload(host: URL, path: String, to url: URL) async throws {
        let endpoint = host.appendingPathComponent(path)
        let (data, response) = try await httpData(from: endpoint, timeout: 5, label: "runtime trace fetch")
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime trace fetch failed for /\(path)")
        }
        try data.write(to: url)
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
    }

    private static func renderCaptureReportMarkdown(_ report: CaptureReport) -> String {
        var artifactLines = [
            "- screenshot: \(report.artifacts.screenshot ?? "unavailable for this runtime")",
            "- snapshot: \(report.artifacts.snapshot)",
            "- screen-map: \(report.artifacts.screenMap)",
            "- accessibility: \(report.artifacts.accessibility)",
            "- compact: \(report.artifacts.compact)",
            "- audit: \(report.artifacts.audit)",
        ]
        if let runtime = report.artifacts.runtime {
            artifactLines.append("- runtime: \(runtime)")
        }
        if let logs = report.artifacts.logs {
            artifactLines.append("- logs: \(logs)")
        }

        var lines: [String] = [
            "# Loupe Capture Report",
            "",
            "- host: \(report.host)",
            "- bundleID: \(report.bundleID ?? "unknown")",
            "- udid: \(report.udid ?? "unknown")",
            "- snapshotID: \(report.snapshotID)",
            "- screen: \(format(report.screen.size.width))x\(format(report.screen.size.height)) @\(format(report.screen.scale))x",
            "",
            "## Artifacts",
            "",
        ]
        lines += artifactLines
        lines += [
            "",
            "## Counts",
            "",
            "- nodes: \(report.counts.nodes)",
            "- screenMapElements: \(report.counts.screenMapElements)",
            "- visibleTexts: \(report.counts.visibleTexts)",
            "- interactiveElements: \(report.counts.interactiveElements)",
            "- accessibilityNodes: \(report.counts.accessibilityNodes)",
            "- auditIssues: \(report.counts.auditIssues)",
            "- scrollViews: \(report.counts.scrollViews)",
            "- scrollableScrollViews: \(report.counts.scrollableScrollViews)",
        ]

        if !report.scrollViews.isEmpty {
            lines += [
                "",
                "## Scrollability",
                "",
            ]
            for scrollView in report.scrollViews.prefix(8) {
                let frame = scrollView.frame.map { " frame=\(rectSummary($0))" } ?? ""
                let axes = scrollView.scrollableAxes.isEmpty ? "none" : scrollView.scrollableAxes.joined(separator: ",")
                lines.append("- \(scrollView.ref)\(scrollView.testID.map { " #\($0)" } ?? "")\(frame) contentSize=\(format(scrollView.contentSize.width))x\(format(scrollView.contentSize.height)) offset=\(format(scrollView.contentOffset.x)),\(format(scrollView.contentOffset.y)) axes=\(axes)")
            }
        }

        if !report.topAuditIssues.isEmpty {
            lines += [
                "",
                "## Audit Issues By Kind",
                "",
            ]
            for key in report.auditIssuesByKind.keys.sorted() {
                lines.append("- \(key): \(report.auditIssuesByKind[key] ?? 0)")
            }

            lines += [
                "",
                "## Top Audit Issues",
                "",
            ]
            for issue in report.topAuditIssues {
                let text = issue.text.map { " text=\"\($0)\"" } ?? ""
                let type = issue.className ?? issue.typeName ?? "unknown"
                let frame = issue.frame.map { " frame=\(rectSummary($0))" } ?? ""
                lines.append("- \(issue.kind.rawValue) \(issue.ref) \(type)\(issue.testID.map { " #\($0)" } ?? "")\(text)\(frame): \(issue.message)")
            }
        }

        lines += [
            "",
            "## Agent Loop",
            "",
            report.artifacts.screenshot == nil
                ? "Use screen-map/audit/accessibility artifacts for structure, semantics, and actionable fixes. This runtime did not provide a simulator screenshot."
                : "Use the screenshot for visual fidelity and the screen-map/audit/accessibility artifacts for structure, semantics, and actionable fixes.",
        ]
        return lines.joined(separator: "\n") + "\n"
    }

    private static func selectorDescription(_ selector: LoupeSelector) -> String {
        switch selector {
        case let .testID(value):
            return "testID:\(value)"
        case let .text(value, exact):
            return exact ? "text:\(value)" : "textContains:\(value)"
        case let .role(value):
            return "role:\(value)"
        case let .roleAndText(role, text, exact):
            return exact ? "roleAndText:\(role):\(text)" : "roleAndTextContains:\(role):\(text)"
        case let .ref(value):
            return "ref:\(value)"
        }
    }

    private static func dispatchAction(command: String, options: ActionDispatchOptions, target: ActionTarget) throws {
        guard command != "pinch" else {
            throw CLIError("pinch is not supported by the native HID backend yet")
        }

        try validateActionBackend(options.backend)
        let udid = try resolvedBackendUDID(options.udid)
        let mappedPoint = mapToDisplayPoint(target.point)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status: Int32
        switch command {
        case "tap":
            status = LoupeHIDTap(udid, mappedPoint.x, mappedPoint.y, target.screen.width, target.screen.height, &errorMessage)
        case "swipe", "drag":
            let end = try options.requireEndPoint(command: command)
            let mappedEnd = mapToDisplayPoint(end)
            status = LoupeHIDDrag(
                udid,
                mappedPoint.x,
                mappedPoint.y,
                mappedEnd.x,
                mappedEnd.y,
                target.screen.width,
                target.screen.height,
                options.duration ?? 0.6,
                &errorMessage
            )
        case "type":
            status = LoupeHIDType(udid, options.text ?? "", &errorMessage)
        case "press":
            status = LoupeHIDPress(udid, options.press ?? "", &errorMessage)
        case "pinch":
            throw CLIError("pinch is not supported by the native HID backend yet")
        default:
            throw CLIError("Unsupported action command: \(command)")
        }

        if let errorMessage {
            defer { LoupeHIDFreeCString(errorMessage) }
            if status != 0 {
                throw CLIError("native HID \(command) failed: \(String(cString: errorMessage))")
            }
        } else if status != 0 {
            throw CLIError("native HID \(command) failed")
        }
    }

    private static func dispatchRuntimeActivation(options: ActionOptions, target _: ActionTarget) async throws {
        guard let selector = options.selector else {
            throw CLIError("runtime tap requires --test-id or --ref")
        }
        let request = LoupeActivationRequest(selector: try activationSelector(from: selector))
        _ = try await postActivation(request, host: options.host, timeout: options.timeout)
    }

    private static func activationSelector(from selector: LoupeSelector) throws -> LoupeMutationSelector {
        switch selector {
        case let .testID(value):
            return LoupeMutationSelector(kind: .testID, value: value)
        case let .ref(value):
            return LoupeMutationSelector(kind: .ref, value: value)
        case let .role(value):
            return LoupeMutationSelector(kind: .role, value: value)
        case let .text(value, exact):
            return LoupeMutationSelector(kind: .text, value: value, exact: exact)
        case let .roleAndText(role, text, exact):
            return LoupeMutationSelector(kind: .roleAndText, value: text, role: role, exact: exact)
        }
    }

    private static func mapToDisplayPoint(_ point: LoupePoint) -> LoupePoint {
        point
    }

    private static func simulatorDisplaySize(udid: String, scale: Double) throws -> LoupeSize {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loupe-display-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "screenshot", "--type=png", url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try run(process, label: "simctl screenshot")

        let data = try Data(contentsOf: url)
        guard data.count >= 24 else {
            throw CLIError("Could not read simulator screenshot size")
        }

        let width = UInt32(data[16]) << 24
            | UInt32(data[17]) << 16
            | UInt32(data[18]) << 8
            | UInt32(data[19])
        let height = UInt32(data[20]) << 24
            | UInt32(data[21]) << 16
            | UInt32(data[22]) << 8
            | UInt32(data[23])

        return LoupeSize(width: Double(width) / scale, height: Double(height) / scale)
    }

    private static func validateActionBackend(_ requested: String) throws {
        guard requested == "auto" || requested == "native" || requested == "runtime" else {
            throw CLIError("Unsupported action backend: \(requested). Loupe currently supports native or runtime.")
        }
    }

    static func resolvedBackendUDID(_ requested: String) throws -> String {
        guard requested == "booted" else {
            return requested
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "--json"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try run(process, label: "simctl list booted devices", timeout: simctlListTimeout())

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devicesByRuntime = object["devices"] as? [String: [[String: Any]]]
        else {
            throw CLIError("Could not parse booted simulator list")
        }

        let booted = Self.preferredBootedDevice(in: devicesByRuntime)

        guard let booted else {
            let count = devicesByRuntime.values.flatMap { $0 }.filter { ($0["state"] as? String) == "Booted" }.count
            throw CLIError("Expected exactly one booted simulator, or exactly one booted iPhone when multiple platforms are booted. Found \(count). Pass --udid <UDID>.")
        }

        guard let udid = booted["udid"] as? String else {
            throw CLIError("Booted simulator did not include a UDID")
        }

        return udid
    }

    static func preferredBootedDevice(in devicesByRuntime: [String: [[String: Any]]]) -> [String: Any]? {
        let booted = devicesByRuntime.values
            .flatMap { $0 }
            .filter { ($0["state"] as? String) == "Booted" }

        if booted.count == 1 {
            return booted[0]
        }

        let bootedPhones = devicesByRuntime
            .filter { runtime, _ in runtime.contains(".iOS-") || runtime.hasSuffix(".iOS") }
            .flatMap(\.value)
            .filter { ($0["state"] as? String) == "Booted" && (($0["name"] as? String)?.contains("iPhone") == true) }

        return bootedPhones.count == 1 ? bootedPhones[0] : nil
    }

    private static func resolveSimulatorUDID(_ requested: String) throws -> String {
        if requested == "booted" {
            return try resolvedBackendUDID(requested)
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "--json"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try run(process, label: "simctl list devices", timeout: simctlListTimeout())

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let devicesByRuntime = object["devices"] as? [String: [[String: Any]]]
        else {
            throw CLIError("Could not parse simulator device list")
        }

        let devices = devicesByRuntime.values.flatMap { $0 }
        if devices.contains(where: { ($0["udid"] as? String) == requested }) {
            return requested
        }

        let bootedMatches = devices.filter {
            ($0["name"] as? String) == requested && ($0["state"] as? String) == "Booted"
        }
        guard bootedMatches.count == 1 else {
            throw CLIError("Expected exactly one booted simulator named \(requested), found \(bootedMatches.count). Pass --device <UDID>.")
        }

        guard let udid = bootedMatches[0]["udid"] as? String else {
            throw CLIError("Simulator \(requested) did not include a UDID")
        }
        return udid
    }

    private static func simctlListTimeout() -> TimeInterval {
        guard let raw = ProcessInfo.processInfo.environment["LOUPE_SIMCTL_LIST_TIMEOUT"],
              let value = Double(raw),
              value > 0 else {
            return 60
        }
        return value
    }

    private static func executablePath(named name: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func httpData(
        from url: URL,
        timeout: TimeInterval,
        label: String
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await httpData(for: request, timeout: timeout, label: label)
    }

    static func httpData(
        for request: URLRequest,
        timeout: TimeInterval,
        label: String
    ) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = timeout
        let timedRequest = request
        let requestURL = request.url?.absoluteString ?? "unknown-url"
        do {
            return try await withExplicitTimeout(seconds: timeout) {
                try await URLSession.shared.data(for: timedRequest)
            }
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError("\(label) timed out or failed for \(requestURL): \(error.localizedDescription)")
        }
    }

    private static func withExplicitTimeout<Value: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds(seconds))
                throw CLIError("request timed out after \(format(seconds))s")
            }

            defer {
                group.cancelAll()
            }

            guard let value = try await group.next() else {
                throw CLIError("request timed out after \(format(seconds))s")
            }
            return value
        }
    }

    private static func timeoutNanoseconds(_ seconds: TimeInterval) -> UInt64 {
        let capped = min(max(seconds, 0), Double(UInt64.max) / 1_000_000_000)
        return UInt64((capped * 1_000_000_000).rounded(.up))
    }

    private static func run(_ process: Process, label: String, timeout: TimeInterval = 10) throws {
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }
        try process.run()
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw CLIError("\(label) timed out after \(format(timeout))s")
        }
        guard process.terminationStatus == 0 else {
            throw CLIError("\(label) exited with status \(process.terminationStatus)")
        }
    }

    static func write(data: Data, outputURL: URL?) throws {
        if let outputURL {
            try data.write(to: outputURL)
            FileHandle.standardError.write(Data("wrote \(outputURL.path)\n".utf8))
        } else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func decodeSnapshot(from url: URL) throws -> LoupeSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeSnapshot.self, from: Data(contentsOf: url))
    }

    static func snapshotDiff(before: LoupeSnapshot, after: LoupeSnapshot) -> LoupeSnapshotDiff {
        let beforeIndex = indexedNodes(before)
        let afterIndex = indexedNodes(after)
        let beforeKeys = Set(beforeIndex.keys)
        let afterKeys = Set(afterIndex.keys)

        let appeared = afterKeys.subtracting(beforeKeys)
            .compactMap { key in afterIndex[key].map { diffNodeSummary(key: key, node: $0, screen: after.screen.size) } }
            .sorted { $0.key < $1.key }
        let disappeared = beforeKeys.subtracting(afterKeys)
            .compactMap { key in beforeIndex[key].map { diffNodeSummary(key: key, node: $0, screen: before.screen.size) } }
            .sorted { $0.key < $1.key }

        let changed = beforeKeys.intersection(afterKeys)
            .compactMap { key -> LoupeNodeChange? in
                guard let beforeNode = beforeIndex[key], let afterNode = afterIndex[key] else {
                    return nil
                }
                let changes = changedFields(before: beforeNode, after: afterNode, screen: after.screen.size)
                guard !changes.isEmpty else {
                    return nil
                }
                return LoupeNodeChange(key: key, summary: nodeSummary(afterNode, screen: after.screen.size), changes: changes)
            }
            .sorted { $0.key < $1.key }

        return LoupeSnapshotDiff(
            beforeSnapshotID: before.id,
            afterSnapshotID: after.id,
            appeared: appeared,
            disappeared: disappeared,
            changed: changed
        )
    }

    private static func indexedNodes(_ snapshot: LoupeSnapshot) -> [String: LoupeNode] {
        var counts: [String: Int] = [:]
        var result: [String: LoupeNode] = [:]

        for node in snapshot.nodes.values where !suppressesDiffNode(node, in: snapshot) {
            let baseKey = nodeIdentityKey(node, screen: snapshot.screen.size)
            let count = counts[baseKey, default: 0]
            counts[baseKey] = count + 1
            let key = count == 0 ? baseKey : "\(baseKey)#\(node.ref)"
            result[key] = node
        }
        return result
    }

    private static func suppressesDiffNode(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        if isSystemOwnedPassiveDecoration(node) {
            return true
        }
        guard isRolelessAppleSystemChromeAggregate(node, in: snapshot),
              isSemanticOnlyDisplayText(node),
              let text = LoupeObservationCompactor.displayText(for: node) else {
            return false
        }
        return hasSpecificVisibleTextMatch(
            text,
            excluding: node.ref,
            in: snapshot,
            screen: snapshot.screen.size
        )
    }

    private static func isSystemOwnedPassiveDecoration(_ node: LoupeNode) -> Bool {
        guard node.runtime?.frameworkBundleIdentifier?.hasPrefix("com.apple.") == true else {
            return false
        }
        if node.testID != nil || node.role != nil || node.accessibility?.isElement == true {
            return false
        }
        if node.isInteractive || isPublicInteractiveUIKitElement(node) {
            return false
        }
        return LoupeObservationCompactor.displayText(for: node) == nil
    }

    private static func isPublicInteractiveUIKitElement(_ node: LoupeNode) -> Bool {
        node.platform?.button != nil
            || node.platform?.switchControl != nil
            || node.platform?.slider != nil
            || node.platform?.stepper != nil
            || node.platform?.segmentedControl != nil
            || node.platform?.textField != nil
            || node.platform?.textView != nil
            || hasSyntheticSource("UIBarButtonItem", node)
            || hasSyntheticSource("UITabBarItem", node)
    }

    private static func hasSyntheticSource(_ source: String, _ node: LoupeNode) -> Bool {
        guard case .bool(true) = node.custom["synthetic"],
              case let .string(nodeSource) = node.custom["source"],
              nodeSource == source else {
            return false
        }
        return true
    }

    private static func nodeIdentityKey(_ node: LoupeNode, screen: LoupeSize) -> String {
        if let testID = node.testID, !testID.isEmpty {
            return "testID:\(testID)"
        }
        if let identifier = node.accessibility?.identifier, !identifier.isEmpty {
            return "axID:\(identifier)"
        }
        let type = node.platform?.className ?? node.typeName
        let role = node.role ?? ""
        if let frame = node.frame {
            if suppressesDiffAggregateText(node, screen: screen) {
                return "visual:\(type):\(role):\(rectSummary(frame))"
            }
            let text = diffSummaryText(node, screen: screen) ?? ""
            return "visual:\(type):\(role):\(text):\(rectSummary(frame))"
        }
        return "ref:\(node.ref)"
    }

    private static func diffNodeSummary(key: String, node: LoupeNode, screen: LoupeSize) -> LoupeNodeDiffSummary {
        LoupeNodeDiffSummary(
            key: key,
            ref: node.ref,
            typeName: node.platform?.className ?? node.typeName,
            role: node.role,
            testID: node.testID,
            text: diffSummaryText(node, screen: screen),
            frame: node.frame,
            isVisible: node.isVisible
        )
    }

    private static func nodeSummary(_ node: LoupeNode, screen: LoupeSize) -> String {
        [
            node.platform?.className ?? node.typeName,
            node.testID.map { "#\($0)" },
            diffSummaryText(node, screen: screen).map { "\"\(summaryPreview($0))\"" },
            node.frame.map(rectSummary),
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func changedFields(before: LoupeNode, after: LoupeNode, screen: LoupeSize) -> [LoupeNodeFieldChange] {
        var changes: [LoupeNodeFieldChange] = []
        appendChange("text", diffSummaryText(before, screen: screen), diffSummaryText(after, screen: screen), to: &changes)
        appendChange("value", before.value, after.value, to: &changes)
        appendChange("isVisible", before.isVisible, after.isVisible, to: &changes)
        appendChange("isEnabled", before.isEnabled, after.isEnabled, to: &changes)
        appendChange("isInteractive", before.isInteractive, after.isInteractive, to: &changes)
        appendChange("frame", before.frame.map(rectSummary), after.frame.map(rectSummary), to: &changes)
        appendChange("uikit.isFocused", before.platform?.isFocused, after.platform?.isFocused, to: &changes)
        appendChange("uikit.canBecomeFocused", before.platform?.canBecomeFocused, after.platform?.canBecomeFocused, to: &changes)
        appendChange("style.alpha", before.style?.alpha, after.style?.alpha, to: &changes)
        appendChange("style.backgroundColor", before.style?.backgroundColor.map(colorSummary), after.style?.backgroundColor.map(colorSummary), to: &changes)
        appendChange("style.tintColor", before.style?.tintColor.map(colorSummary), after.style?.tintColor.map(colorSummary), to: &changes)
        appendChange("style.textColor", before.style?.textColor.map(colorSummary), after.style?.textColor.map(colorSummary), to: &changes)
        appendChange("style.borderColor", before.style?.borderColor.map(colorSummary), after.style?.borderColor.map(colorSummary), to: &changes)
        appendChange("style.borderWidth", before.style?.borderWidth, after.style?.borderWidth, to: &changes)
        appendChange("style.cornerRadius", before.style?.cornerRadius, after.style?.cornerRadius, to: &changes)
        appendChange("style.fontName", before.style?.fontName, after.style?.fontName, to: &changes)
        appendChange("style.fontSize", before.style?.fontSize, after.style?.fontSize, to: &changes)
        appendChange("style.shadowColor", before.style?.shadowColor.map(colorSummary), after.style?.shadowColor.map(colorSummary), to: &changes)
        appendChange("style.shadowOpacity", before.style?.shadowOpacity, after.style?.shadowOpacity, to: &changes)
        appendChange("style.shadowRadius", before.style?.shadowRadius, after.style?.shadowRadius, to: &changes)
        appendChange("style.shadowOffset", before.style?.shadowOffset.map(sizeSummary), after.style?.shadowOffset.map(sizeSummary), to: &changes)
        appendChange("uikit.scrollView.contentOffset", before.platform?.scrollView.map { pointSummary($0.contentOffset) }, after.platform?.scrollView.map { pointSummary($0.contentOffset) }, to: &changes)
        appendChange("uikit.scrollView.contentSize", before.platform?.scrollView.map { sizeSummary($0.contentSize) }, after.platform?.scrollView.map { sizeSummary($0.contentSize) }, to: &changes)
        appendChange("uikit.scrollView.contentInset", before.platform?.scrollView.map { insetsSummary($0.contentInset) }, after.platform?.scrollView.map { insetsSummary($0.contentInset) }, to: &changes)
        appendChange("uikit.scrollView.adjustedContentInset", before.platform?.scrollView.map { insetsSummary($0.adjustedContentInset) }, after.platform?.scrollView.map { insetsSummary($0.adjustedContentInset) }, to: &changes)
        appendChange("uikit.scrollView.scrollIndicatorInsets", before.platform?.scrollView.map { insetsSummary($0.scrollIndicatorInsets) }, after.platform?.scrollView.map { insetsSummary($0.scrollIndicatorInsets) }, to: &changes)
        appendChange("uikit.scrollView.isScrollEnabled", before.platform?.scrollView?.isScrollEnabled, after.platform?.scrollView?.isScrollEnabled, to: &changes)
        appendChange("uikit.scrollView.isPagingEnabled", before.platform?.scrollView?.isPagingEnabled, after.platform?.scrollView?.isPagingEnabled, to: &changes)
        appendChange("uikit.scrollView.bounces", before.platform?.scrollView?.bounces, after.platform?.scrollView?.bounces, to: &changes)
        appendChange("uikit.scrollView.showsVerticalScrollIndicator", before.platform?.scrollView?.showsVerticalScrollIndicator, after.platform?.scrollView?.showsVerticalScrollIndicator, to: &changes)
        appendChange("uikit.scrollView.showsHorizontalScrollIndicator", before.platform?.scrollView?.showsHorizontalScrollIndicator, after.platform?.scrollView?.showsHorizontalScrollIndicator, to: &changes)
        appendChange("uikit.switch.isOn", before.platform?.switchControl?.isOn, after.platform?.switchControl?.isOn, to: &changes)
        appendChange("uikit.segmentedControl.selectedSegmentIndex", before.platform?.segmentedControl?.selectedSegmentIndex, after.platform?.segmentedControl?.selectedSegmentIndex, to: &changes)
        appendChange("uikit.slider.value", before.platform?.slider?.value, after.platform?.slider?.value, to: &changes)
        appendChange("uikit.stepper.value", before.platform?.stepper?.value, after.platform?.stepper?.value, to: &changes)
        appendChange("uikit.pageControl.currentPage", before.platform?.pageControl?.currentPage, after.platform?.pageControl?.currentPage, to: &changes)
        appendChange("uikit.progressView.value", before.platform?.progressView?.value, after.platform?.progressView?.value, to: &changes)
        return changes
    }

    private static func diffSummaryText(_ node: LoupeNode, screen: LoupeSize) -> String? {
        guard !suppressesDiffAggregateText(node, screen: screen) else {
            return nil
        }
        return displayText(node)
    }

    private static func suppressesDiffAggregateText(_ node: LoupeNode, screen: LoupeSize) -> Bool {
        if node.platform?.scrollView != nil {
            return true
        }

        switch node.role?.lowercased() {
        case "collectionview", "tableview", "scrollview", "window", "navigationbar":
            return true
        default:
            break
        }

        guard node.testID == nil, node.role == nil, !node.children.isEmpty, let frame = node.frame else {
            return false
        }

        let screenArea = max(0, screen.width) * max(0, screen.height)
        guard screenArea > 0 else {
            return false
        }
        return max(0, frame.width) * max(0, frame.height) / screenArea >= 0.5
    }

    private static func isRolelessAppleSystemChromeAggregate(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        guard node.runtime?.frameworkBundleIdentifier?.hasPrefix("com.apple.") == true,
              node.testID == nil,
              node.role == nil,
              node.accessibility?.isElement != true else {
            return false
        }
        return isSystemChromeDescendant(node, in: snapshot)
    }

    private static func isSystemChromeDescendant(_ node: LoupeNode, in snapshot: LoupeSnapshot) -> Bool {
        if isSystemChromeRole(node.role) {
            return true
        }
        var currentRef = node.parentRef
        while let ref = currentRef, let current = snapshot.nodes[ref] {
            if isSystemChromeRole(current.role) {
                return true
            }
            currentRef = current.parentRef
        }
        return false
    }

    private static func isSystemChromeRole(_ role: String?) -> Bool {
        role == "navigationBar" || role == "tabBar" || role == "toolbar"
    }

    private static func isSemanticOnlyDisplayText(_ node: LoupeNode) -> Bool {
        nonEmpty(node.semanticText) != nil
            && nonEmpty(node.text) == nil
            && nonEmpty(node.renderedText) == nil
            && nonEmpty(node.label) == nil
            && nonEmpty(node.value) == nil
            && nonEmpty(node.placeholder) == nil
    }

    private static func hasSpecificVisibleTextMatch(
        _ text: String,
        excluding ref: String,
        in snapshot: LoupeSnapshot,
        screen: LoupeSize
    ) -> Bool {
        let screenRect = LoupeRect(x: 0, y: 0, width: screen.width, height: screen.height)
        return snapshot.nodes.values.contains { candidate in
            guard candidate.ref != ref,
                  candidate.isVisible,
                  let frame = candidate.frame,
                  frame.intersects(screenRect),
                  LoupeObservationCompactor.displayText(for: candidate) == text else {
                return false
            }
            return isSpecificTextNode(candidate)
        }
    }

    private static func isSpecificTextNode(_ node: LoupeNode) -> Bool {
        node.testID != nil
            || node.role != nil
            || node.accessibility?.isElement == true
            || !isSemanticOnlyDisplayText(node)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func appendChange<T: Equatable>(
        _ field: String,
        _ before: T?,
        _ after: T?,
        to changes: inout [LoupeNodeFieldChange]
    ) {
        guard before != after else {
            return
        }
        changes.append(
            LoupeNodeFieldChange(
                field: field,
                before: before.map { String(describing: $0) },
                after: after.map { String(describing: $0) }
            )
        )
    }

    private static func colorSummary(_ color: LoupeColor) -> String {
        "rgba(\(format(color.red)),\(format(color.green)),\(format(color.blue)),\(format(color.alpha)))"
    }

    private static func pointSummary(_ point: LoupePoint) -> String {
        "\(format(point.x)),\(format(point.y))"
    }

    private static func sizeSummary(_ size: LoupeSize) -> String {
        "\(format(size.width)),\(format(size.height))"
    }

    private static func insetsSummary(_ insets: LoupeInsets) -> String {
        "\(format(insets.top)),\(format(insets.left)),\(format(insets.bottom)),\(format(insets.right))"
    }

    private static func renderSnapshotDiff(
        _ diff: LoupeSnapshotDiff,
        limit: Int,
        changedOnly: Bool = false,
        visibleOnly: Bool = false
    ) -> String {
        let appeared = visibleOnly ? diff.appeared.filter(\.isVisibleForSummary) : diff.appeared
        let disappeared = visibleOnly ? diff.disappeared.filter(\.isVisibleForSummary) : diff.disappeared
        var lines: [String] = [
            "diff \(diff.beforeSnapshotID) -> \(diff.afterSnapshotID)",
            "appeared=\(appeared.count) disappeared=\(disappeared.count) changed=\(diff.changed.count)",
        ]
        if visibleOnly {
            let skippedAppeared = diff.appeared.count - appeared.count
            let skippedDisappeared = diff.disappeared.count - disappeared.count
            if skippedAppeared > 0 || skippedDisappeared > 0 {
                lines.append("hiddenSkipped appeared=\(skippedAppeared) disappeared=\(skippedDisappeared)")
            }
        }

        if !changedOnly {
            appendSection("appeared", appeared.prefix(limit).map(renderDiffNode), to: &lines)
            appendSection("disappeared", disappeared.prefix(limit).map(renderDiffNode), to: &lines)
        }
        appendSection("changed", diff.changed.prefix(limit).map(renderNodeChange), to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendSection<S: Sequence>(_ title: String, _ items: S, to lines: inout [String]) where S.Element == String {
        let rendered = Array(items)
        guard !rendered.isEmpty else {
            return
        }
        lines.append("")
        lines.append("\(title):")
        lines.append(contentsOf: rendered.map { "  \($0)" })
    }

    private static func renderDiffNode(_ node: LoupeNodeDiffSummary) -> String {
        [
            summaryPreview(node.key, maxLength: 180),
            node.typeName,
            node.role.map { "role=\($0)" },
            node.testID.map { "testID=\($0)" },
            node.text.map { "text=\"\(summaryPreview($0))\"" },
            node.frame.map { "frame=\(rectSummary($0))" },
            node.isVisible == false ? "visible=false" : nil,
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func renderNodeChange(_ change: LoupeNodeChange) -> String {
        let fields = change.changes
            .map { "\($0.field):\(summaryPreview($0.before ?? "nil"))->\(summaryPreview($0.after ?? "nil"))" }
            .joined(separator: ", ")
        return "\(summaryPreview(change.key, maxLength: 180)) \(change.summary) \(fields)"
    }

    private static func summaryPreview(_ text: String, maxLength: Int = 140) -> String {
        let oneLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard oneLine.count > maxLength else {
            return oneLine
        }
        let end = oneLine.index(oneLine.startIndex, offsetBy: maxLength)
        return "\(oneLine[..<end])..."
    }

    private static func makeTraceSummary(directory: URL) throws -> LoupeTraceSummary {
        let beforeAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-before.json"))
        let targetAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-target.json"))
        let afterAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-after.json"))
        let failureAction = try readJSONIfExists(LoupeCLIActionTrace.self, directory.appendingPathComponent("action-failure.json"))
        let error = try readJSONIfExists(LoupeCLIActionErrorTrace.self, directory.appendingPathComponent("error.json"))
        let batchMutation = try readJSONIfExists(BatchMutationResult.self, directory.appendingPathComponent("summary.json"))

        let beforeLogs = (try readJSONIfExists([LoupeRuntimeLog].self, directory.appendingPathComponent("before-logs.json"))) ?? []
        let afterLogs = (try readJSONIfExists([LoupeRuntimeLog].self, directory.appendingPathComponent("after-logs.json"))) ?? []
        let failureLogs = (try readJSONIfExists([LoupeRuntimeLog].self, directory.appendingPathComponent("failure-logs.json"))) ?? []
        let newLogs = afterLogs.filter { afterLog in
            !beforeLogs.contains(where: { $0.id == afterLog.id })
        }

        let beforeSnapshotURL = existingTraceFile(
            in: directory,
            names: ["before-snapshot.json", "prev-snapshot.json"]
        )
        let afterSnapshotURL = existingTraceFile(
            in: directory,
            names: ["after-snapshot.json", "next-snapshot.json"]
        )
        let diff: LoupeSnapshotDiff?
        if let beforeSnapshotURL, let afterSnapshotURL {
            diff = try snapshotDiff(before: decodeSnapshot(from: beforeSnapshotURL), after: decodeSnapshot(from: afterSnapshotURL))
        } else {
            diff = nil
        }

        let screenshotDiff = try? screenshotDiffIfPresent(in: directory)
        let cropURL = directory.appendingPathComponent("target-crop.png")
        return LoupeTraceSummary(
            directory: directory.path,
            command: afterAction?.command ?? failureAction?.command ?? targetAction?.command ?? beforeAction?.command ?? (batchMutation == nil ? nil : "set-many"),
            phase: error == nil ? (afterAction?.phase ?? targetAction?.phase ?? beforeAction?.phase ?? (batchMutation == nil ? nil : "after")) : "failure",
            selector: afterAction?.selector ?? failureAction?.selector ?? targetAction?.selector ?? beforeAction?.selector ?? batchMutation?.selector,
            target: afterAction?.resolvedTarget ?? failureAction?.resolvedTarget ?? targetAction?.resolvedTarget,
            error: error?.message,
            diff: diff,
            screenshotDiff: screenshotDiff,
            notes: traceNotes(diff: diff, screenshotDiff: screenshotDiff),
            batchMutation: batchMutation,
            newLogs: newLogs,
            failureLogs: failureLogs,
            targetCropPath: FileManager.default.fileExists(atPath: cropURL.path) ? cropURL.path : nil
        )
    }

    private static func screenshotDiffIfPresent(in directory: URL) throws -> LoupeScreenshotDiffSummary? {
        let beforeURL = directory.appendingPathComponent("before.png")
        let afterURL = directory.appendingPathComponent("after.png")
        guard
            FileManager.default.fileExists(atPath: beforeURL.path),
            FileManager.default.fileExists(atPath: afterURL.path)
        else {
            return nil
        }
        return try ScreenshotDiffer.diff(before: beforeURL, after: afterURL)
    }

    static func traceNotes(
        diff: LoupeSnapshotDiff?,
        screenshotDiff: LoupeScreenshotDiffSummary?
    ) -> [String] {
        guard let screenshotDiff, screenshotDiff.changedPixelRatio >= 0.20 else {
            return []
        }

        let snapshotChangeCount = diff.map(visibleSnapshotChangeCount) ?? 0
        guard snapshotChangeCount <= 5 else {
            return []
        }

        return [
            "large screenshot change with minimal app snapshot diff; likely system alert, simulator chrome, or external overlay outside the injected app tree",
        ]
    }

    private static func visibleSnapshotChangeCount(_ diff: LoupeSnapshotDiff) -> Int {
        diff.appeared.filter(\.isVisibleForSummary).count
            + diff.disappeared.filter(\.isVisibleForSummary).count
            + diff.changed.count
    }

    private static func existingTraceFile(in directory: URL, names: [String]) -> URL? {
        names
            .map { directory.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func readJSONIfExists<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    private static func renderTraceSummary(_ summary: LoupeTraceSummary, limit: Int) -> String {
        var lines = [
            "trace \(summary.directory)",
            "command=\(summary.command ?? "unknown") phase=\(summary.phase ?? "unknown") selector=\(summary.selector ?? "none")",
        ]
        if let target = summary.target {
            lines.append("target=\(target.tree):\(target.ref) testID=\(target.testID ?? "none") role=\(target.role ?? "none") frame=\(target.frame.map(rectSummary) ?? "nil")")
        }
        if let targetCropPath = summary.targetCropPath {
            lines.append("targetCrop=\(targetCropPath)")
        }
        if let error = summary.error {
            lines.append("error=\(error)")
        }
        if let screenshotDiff = summary.screenshotDiff {
            lines.append(
                "screenshotDiff changed=\(formatPercent(screenshotDiff.changedPixelRatio)) pixels=\(screenshotDiff.changedPixels)/\(screenshotDiff.comparedPixels) meanDelta=\(formatDecimal(screenshotDiff.meanColorDelta)) maxDelta=\(screenshotDiff.maxColorDelta)"
            )
            if !screenshotDiff.dimensionsMatch {
                lines.append("screenshotSize before=\(screenshotDiff.beforeSize.width)x\(screenshotDiff.beforeSize.height) after=\(screenshotDiff.afterSize.width)x\(screenshotDiff.afterSize.height)")
            }
            lines.append("screenshots before=\(screenshotDiff.beforePath) after=\(screenshotDiff.afterPath)")
        }
        for note in summary.notes {
            lines.append("note=\(note)")
        }
        if let batchMutation = summary.batchMutation {
            lines.append("set-many matched=\(batchMutation.matchedTargets) mutations=\(batchMutation.mutationRequests) verified=\(batchMutation.verifiedTargets) accuracy=\(format(batchMutation.accuracy))")
            lines.append("artifacts prev=\(batchMutation.prevSnapshot) next=\(batchMutation.nextSnapshot) targets=\(batchMutation.targets)")
        }
        if let diff = summary.diff {
            lines.append("")
            lines.append(renderSnapshotDiff(diff, limit: limit, visibleOnly: true))
        }
        let logs = summary.error == nil ? summary.newLogs : summary.failureLogs
        if !logs.isEmpty {
            lines.append("")
            lines.append("logs:")
            for log in logs.prefix(limit) {
                lines.append("  \(log.level) \(log.message)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }

    private static func formatDecimal(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func renderBatchMutationSummary(_ result: BatchMutationResult) -> String {
        [
            "set-many matched=\(result.matchedTargets)",
            "mutations=\(result.mutationRequests)",
            "verified=\(result.verifiedTargets)",
            "accuracy=\(format(result.accuracy))",
            "summary=\(result.traceDirectory)/summary.json",
            "trace=\(result.traceDirectory)",
        ].joined(separator: " ")
    }

    private static func renderMutationSummary(_ response: LoupeMutationResponse, outputURL: URL?) -> String {
        [
            "set ref=\(response.target.ref)",
            "property=\(response.property)",
            "changed=\(response.changed.map { $0 ? "true" : "false" } ?? "unknown")",
            response.selfSizingProbe.map { "selfSizing=\(selfSizingProbeSummary($0))" },
            response.warning.map { "warning=\"\($0)\"" },
            outputURL.map { "output=\($0.path)" },
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func selfSizingProbeSummary(_ probe: LoupeSelfSizingProbeResult) -> String {
        if probe.attempted {
            return probe.applied ? "applied" : "failed"
        }
        if probe.applied {
            return "already-enabled"
        }
        return "skipped:\(probe.reason ?? "not-applicable")"
    }

    private static func renderWaitForValueSummary(
        node: LoupeNode,
        keyPath: String,
        value: Any,
        outputURL: URL
    ) -> String {
        [
            "act wait value matched ref=\(node.ref)",
            node.testID.map { "testID=\($0)" },
            displayText(node).flatMap(waitSummaryText).map { "text=\"\($0)\"" },
            "key=\(keyPath)",
            "value=\(jsonValueSummary(value))",
            "output=\(outputURL.path)",
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func waitSummaryText(_ text: String) -> String? {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !singleLine.isEmpty else {
            return nil
        }
        let limit = 120
        guard singleLine.count > limit else {
            return singleLine
        }
        return "\(singleLine.prefix(limit - 1))..."
    }

    private static func jsonValueSummary(_ value: Any) -> String {
        if let string = value as? String {
            return "\"\(string)\""
        }
        if let number = value as? NSNumber {
            return String(describing: number)
        }
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        return String(describing: value)
    }

    private static func renderDesignComparison(
        _ comparison: LoupeDesignComparison,
        limit: Int,
        suggestMutations: Bool = false,
        snapshotURL: URL? = nil,
        suggestionHost: URL? = nil
    ) -> String {
        var lines = [
            "design \(comparison.designFrameName) vs snapshot \(comparison.snapshotID)",
            "matched=\(comparison.matchedCount) issues=\(comparison.issueCount)",
        ]

        if !comparison.matches.isEmpty {
            lines.append("")
            lines.append("matches:")
            for match in comparison.matches.prefix(limit) {
                lines.append("  \(match.strategy) \(match.designID ?? match.designName) -> \(match.ref) testID=\(match.testID ?? "none")")
            }
        }

        if !comparison.issues.isEmpty {
            lines.append("")
            lines.append("issues:")
            for issue in comparison.issues.prefix(limit) {
                let subject = issue.designID ?? issue.testID ?? issue.designName ?? issue.ref ?? "unknown"
                let property = issue.property.map { " \($0)" } ?? ""
                let expected = issue.expected.map { " expected=\($0)" } ?? ""
                let actual = issue.actual.map { " actual=\($0)" } ?? ""
                lines.append("  \(issue.kind.rawValue) \(subject)\(property)\(expected)\(actual): \(issue.message)")
            }
        }

        if suggestMutations, !comparison.suggestions.isEmpty {
            lines.append("")
            lines.append("suggested mutations:")
            for suggestion in comparison.suggestions.prefix(limit) {
                lines.append("  \(renderDesignMutationSuggestion(suggestion, snapshotURL: snapshotURL, host: suggestionHost))")
                lines.append("    \(suggestion.reason)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func renderDesignMutationSuggestion(
        _ suggestion: LoupeDesignMutationSuggestion,
        snapshotURL: URL?,
        host: URL?
    ) -> String {
        var parts = ["loupe", "ui", "set"]
        if let host {
            parts.append("--host")
            parts.append(host.absoluteString)
        }
        if let snapshotURL {
            parts.append("--snapshot")
            parts.append(snapshotURL.path)
        }
        parts.append("--ref")
        parts.append(suggestion.ref)
        parts.append(suggestion.property)
        parts.append(contentsOf: mutationValueArguments(for: suggestion))
        parts.append("--no-animate")
        return parts.map(shellArgument).joined(separator: " ")
    }

    private static func mutationValueArguments(for suggestion: LoupeDesignMutationSuggestion) -> [String] {
        switch suggestion.value {
        case .color:
            return ["--color", suggestion.valueLabel]
        case .rect:
            return ["--rect", suggestion.valueLabel]
        case .point:
            return ["--point", suggestion.valueLabel]
        case .size:
            return ["--size", suggestion.valueLabel]
        case .bool:
            return ["--bool", suggestion.valueLabel]
        case .int, .double:
            return ["--number", suggestion.valueLabel]
        case .string:
            return ["--string", suggestion.valueLabel]
        }
    }

    private static func shellArgument(_ value: String) -> String {
        guard !value.isEmpty else {
            return "''"
        }
        let safeScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:-=,@")
        if value.unicodeScalars.allSatisfy({ safeScalars.contains($0) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func safeArtifactName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        let scalars = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return name.isEmpty ? "value" : String(name.prefix(80))
    }

    private static func resolvedSkillSource(_ explicitSource: URL?) throws -> URL {
        var candidates: [URL] = []
        if let explicitSource {
            candidates.append(explicitSource)
        }
        if let env = ProcessInfo.processInfo.environment["LOUPE_SKILL_SOURCE"], !env.isEmpty {
            candidates.append(URL(fileURLWithPath: env, isDirectory: true))
        }

        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectory.appendingPathComponent("skills/loupe", isDirectory: true))

        if let executableURL = Bundle.main.executableURL {
            candidates.append(
                executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("../share/loupe/skills/loupe", isDirectory: true)
                    .standardizedFileURL
            )
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/share/loupe/skills/loupe", isDirectory: true))
        candidates.append(URL(fileURLWithPath: "/usr/local/share/loupe/skills/loupe", isDirectory: true))

        for candidate in candidates {
            let skillFile = candidate.appendingPathComponent("SKILL.md")
            if FileManager.default.fileExists(atPath: skillFile.path) {
                return candidate
            }
        }

        throw CLIError("Could not find Loupe skill source. Run from the repo root or pass --source <path-to-skill-dir>.")
    }

    static func renderViewTree(
        _ snapshot: LoupeSnapshot,
        selector: LoupeSelector?,
        depth: Int?,
        includeHidden: Bool,
        presentation: TreePresentation = .outline
    ) -> String {
        if presentation != .outline {
            return renderFlatViewTree(snapshot, selector: selector, includeHidden: includeHidden, presentation: presentation)
        }

        let roots: [String]
        if let selector {
            roots = LoupeSnapshotQuery.find(
                selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 20)
            ).map(\.ref)
        } else {
            roots = snapshot.rootRefs
        }

        var lines: [String] = []
        for ref in roots {
            appendViewTree(ref: ref, snapshot: snapshot, depth: 0, maxDepth: depth, includeHidden: includeHidden, lines: &lines)
        }
        guard !lines.isEmpty else {
            return "(empty)"
        }
        var output = lines.joined(separator: "\n")
        if let depth, depth <= 5, visiblePrefixContainsOnlyContainers(roots: roots, snapshot: snapshot, maxDepth: depth, includeHidden: includeHidden) {
            output += "\n\nhint: Only container nodes found at depth \(depth). Try --depth 8 or `loupe ui tree --interesting`."
        }
        return output
    }

    private static func appendViewTree(
        ref: String,
        snapshot: LoupeSnapshot,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        lines: inout [String]
    ) {
        guard let node = snapshot.nodes[ref] else {
            return
        }
        let shouldRender = includeHidden || node.isVisible
        if shouldRender {
            lines.append("\(String(repeating: "  ", count: depth))\(viewTreeLine(node))")
            guard maxDepth.map({ depth < $0 }) ?? true else {
                return
            }
        }
        let childDepth = shouldRender ? depth + 1 : depth
        for child in node.children {
            appendViewTree(ref: child, snapshot: snapshot, depth: childDepth, maxDepth: maxDepth, includeHidden: includeHidden, lines: &lines)
        }
    }

    private static func renderAccessibilityTree(
        _ tree: LoupeAccessibilityTree,
        selector: LoupeSelector?,
        depth: Int?,
        includeHidden: Bool,
        presentation: TreePresentation = .outline
    ) -> String {
        if presentation != .outline {
            return renderFlatAccessibilityTree(tree, selector: selector, includeHidden: includeHidden, presentation: presentation)
        }

        let roots: [String]
        if let selector {
            roots = LoupeAccessibilityTreeQuery.find(
                selector,
                in: tree,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 20)
            ).map(\.ref)
        } else {
            roots = tree.rootRefs
        }

        var lines: [String] = []
        for ref in roots {
            appendAccessibilityTree(ref: ref, tree: tree, depth: 0, maxDepth: depth, includeHidden: includeHidden, lines: &lines)
        }
        guard !lines.isEmpty else {
            return "(empty)"
        }
        var output = lines.joined(separator: "\n")
        if let depth, depth <= 5, accessibilityPrefixContainsOnlyContainers(roots: roots, tree: tree, maxDepth: depth, includeHidden: includeHidden) {
            output += "\n\nhint: Only container nodes found at depth \(depth). Try --depth 8 or `loupe ui tree --interesting`."
        }
        return output
    }

    private static func appendAccessibilityTree(
        ref: String,
        tree: LoupeAccessibilityTree,
        depth: Int,
        maxDepth: Int?,
        includeHidden: Bool,
        lines: inout [String]
    ) {
        guard let node = tree.nodes[ref] else {
            return
        }
        if !includeHidden, !node.isVisible {
            return
        }
        lines.append("\(String(repeating: "  ", count: depth))\(accessibilityTreeLine(node))")
        guard maxDepth.map({ depth < $0 }) ?? true else {
            return
        }
        for child in node.children {
            appendAccessibilityTree(ref: child, tree: tree, depth: depth + 1, maxDepth: maxDepth, includeHidden: includeHidden, lines: &lines)
        }
    }

    private static func renderFlatViewTree(
        _ snapshot: LoupeSnapshot,
        selector: LoupeSelector?,
        includeHidden: Bool,
        presentation: TreePresentation
    ) -> String {
        let nodes = selectedViewNodes(snapshot, selector: selector, includeHidden: includeHidden)
            .filter { node in
                switch presentation {
                case .outline:
                    return true
                case .interesting:
                    return isInteresting(node)
                case .visibleLeaves:
                    return isVisibleLeaf(node, in: snapshot, includeHidden: includeHidden)
                case .text:
                    return displayText(node) != nil
                case .mutable:
                    return !MutationPropertySupport.supportedProperties(for: node).isEmpty
                }
            }
        let lines = nodes.map(viewTreeLine)
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }

    private static func selectedViewNodes(
        _ snapshot: LoupeSnapshot,
        selector: LoupeSelector?,
        includeHidden: Bool
    ) -> [LoupeNode] {
        if let selector {
            return LoupeSnapshotQuery.find(
                selector,
                in: snapshot,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 200)
            ).compactMap { snapshot.nodes[$0.ref] }
        }
        return snapshot.nodes.values
            .filter { includeHidden || $0.isVisible }
            .sorted(by: nodeScreenOrder)
    }

    private static func renderFlatAccessibilityTree(
        _ tree: LoupeAccessibilityTree,
        selector: LoupeSelector?,
        includeHidden: Bool,
        presentation: TreePresentation
    ) -> String {
        let nodes = selectedAccessibilityNodes(tree, selector: selector, includeHidden: includeHidden)
            .filter { node in
                switch presentation {
                case .outline, .mutable:
                    return true
                case .interesting:
                    return accessibilityDisplayText(node) != nil || node.testID != nil || node.isInteractive
                case .visibleLeaves:
                    return node.children.isEmpty
                case .text:
                    return accessibilityDisplayText(node) != nil
                }
            }
        let lines = nodes.map(accessibilityTreeLine)
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }

    private static func selectedAccessibilityNodes(
        _ tree: LoupeAccessibilityTree,
        selector: LoupeSelector?,
        includeHidden: Bool
    ) -> [LoupeAccessibilityNode] {
        if let selector {
            return LoupeAccessibilityTreeQuery.find(
                selector,
                in: tree,
                options: LoupeQueryOptions(includeHidden: includeHidden, includeDisabled: true, maxResults: 200)
            ).compactMap { tree.nodes[$0.ref] }
        }
        return tree.nodes.values
            .filter { includeHidden || $0.isVisible }
            .sorted(by: accessibilityNodeScreenOrder)
    }

    private static func nodeScreenOrder(_ lhs: LoupeNode, _ rhs: LoupeNode) -> Bool {
        if let lhsFrame = lhs.frame, let rhsFrame = rhs.frame {
            if abs(lhsFrame.y - rhsFrame.y) > 0.5 {
                return lhsFrame.y < rhsFrame.y
            }
            if abs(lhsFrame.x - rhsFrame.x) > 0.5 {
                return lhsFrame.x < rhsFrame.x
            }
        }
        return lhs.ref < rhs.ref
    }

    private static func accessibilityNodeScreenOrder(_ lhs: LoupeAccessibilityNode, _ rhs: LoupeAccessibilityNode) -> Bool {
        if let lhsFrame = lhs.frame, let rhsFrame = rhs.frame {
            if abs(lhsFrame.y - rhsFrame.y) > 0.5 {
                return lhsFrame.y < rhsFrame.y
            }
            if abs(lhsFrame.x - rhsFrame.x) > 0.5 {
                return lhsFrame.x < rhsFrame.x
            }
        }
        return lhs.ref < rhs.ref
    }

    private static func isInteresting(_ node: LoupeNode) -> Bool {
        displayText(node) != nil || node.testID != nil || node.isInteractive || node.role != nil
    }

    private static func isVisibleLeaf(_ node: LoupeNode, in snapshot: LoupeSnapshot, includeHidden: Bool) -> Bool {
        guard includeHidden || node.isVisible else {
            return false
        }
        return !node.children.contains { ref in
            guard let child = snapshot.nodes[ref] else {
                return false
            }
            return includeHidden || child.isVisible
        }
    }

    private static func visiblePrefixContainsOnlyContainers(
        roots: [String],
        snapshot: LoupeSnapshot,
        maxDepth: Int,
        includeHidden: Bool
    ) -> Bool {
        var visited: [LoupeNode] = []
        for root in roots {
            collectViewPrefix(ref: root, snapshot: snapshot, depth: 0, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &visited)
        }
        return !visited.isEmpty && visited.allSatisfy(isContainerOnly)
    }

    private static func collectViewPrefix(
        ref: String,
        snapshot: LoupeSnapshot,
        depth: Int,
        maxDepth: Int,
        includeHidden: Bool,
        nodes: inout [LoupeNode]
    ) {
        guard let node = snapshot.nodes[ref] else {
            return
        }
        let shouldInclude = includeHidden || node.isVisible
        if shouldInclude {
            nodes.append(node)
            guard depth < maxDepth else {
                return
            }
        }
        let childDepth = shouldInclude ? depth + 1 : depth
        for child in node.children {
            collectViewPrefix(ref: child, snapshot: snapshot, depth: childDepth, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &nodes)
        }
    }

    private static func accessibilityPrefixContainsOnlyContainers(
        roots: [String],
        tree: LoupeAccessibilityTree,
        maxDepth: Int,
        includeHidden: Bool
    ) -> Bool {
        var visited: [LoupeAccessibilityNode] = []
        for root in roots {
            collectAccessibilityPrefix(ref: root, tree: tree, depth: 0, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &visited)
        }
        return !visited.isEmpty && visited.allSatisfy(isAccessibilityContainerOnly)
    }

    private static func collectAccessibilityPrefix(
        ref: String,
        tree: LoupeAccessibilityTree,
        depth: Int,
        maxDepth: Int,
        includeHidden: Bool,
        nodes: inout [LoupeAccessibilityNode]
    ) {
        guard let node = tree.nodes[ref], includeHidden || node.isVisible else {
            return
        }
        nodes.append(node)
        guard depth < maxDepth else {
            return
        }
        for child in node.children {
            collectAccessibilityPrefix(ref: child, tree: tree, depth: depth + 1, maxDepth: maxDepth, includeHidden: includeHidden, nodes: &nodes)
        }
    }

    private static func viewTreeLine(_ node: LoupeNode) -> String {
        [
            node.ref,
            node.platform?.className ?? node.typeName,
            node.role.map { "role=\($0)" },
            node.swiftui.map(swiftUISummary),
            node.testID.map { "testID=\($0)" },
            displayText(node).map { "text=\"\($0)\"" },
            node.frame.map { "frame=\(rectSummary($0))" },
            node.platform?.layout.map(layoutSummary),
            node.platform?.isFocused == true ? "focused" : nil,
            node.platform?.canBecomeFocused == true ? "focusable" : nil,
            node.isVisible ? nil : "hidden",
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func accessibilityTreeLine(_ node: LoupeAccessibilityNode) -> String {
        [
            node.ref,
            node.role ?? "accessibility",
            "source=\(node.sourceRef)",
            node.testID.map { "testID=\($0)" },
            LoupeAccessibilityTreeQuery.displayText(for: node).map { "text=\"\($0)\"" },
            node.frame.map { "frame=\(rectSummary($0))" },
            node.isFocused == true ? "focused" : nil,
            node.canBecomeFocused == true ? "focusable" : nil,
            node.isVisible ? nil : "hidden",
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func swiftUISummary(_ swiftui: LoupeSwiftUIProperties) -> String {
        var parts = ["swiftui=\(swiftui.origin)"]
        if let rootTypeName = swiftui.rootTypeName {
            parts.append("root=\(rootTypeName)")
        }
        if !swiftui.properties.isEmpty {
            let properties = swiftui.properties.prefix(4).map { property in
                if let value = property.value {
                    return "\(property.name)=\(metadataValueSummary(value))"
                }
                return "\(property.name):\(property.typeName)"
            }.joined(separator: ",")
            parts.append("props=\(properties)")
        }
        return parts.joined(separator: " ")
    }

    private static func metadataValueSummary(_ value: LoupeMetadataValue) -> String {
        switch value {
        case let .string(value):
            return "\"\(value)\""
        case let .bool(value):
            return "\(value)"
        case let .int(value):
            return "\(value)"
        case let .double(value):
            return format(value)
        }
    }

    private static func rectSummary(_ rect: LoupeRect) -> String {
        "\(format(rect.x)),\(format(rect.y)),\(format(rect.width)),\(format(rect.height))"
    }

    private static func layoutSummary(_ layout: LoupeUILayoutProperties) -> String {
        [
            "ambiguousLayout=\(layout.isAmbiguousLayout)",
            "hugging=\(priorityPair(layout.hugging))",
            "compression=\(priorityPair(layout.compressionResistance))",
        ].joined(separator: " ")
    }

    private static func priorityPair(_ priorities: LoupeUILayoutPriorities) -> String {
        "\(format(priorities.horizontal))/\(format(priorities.vertical))"
    }

    private static func displayText(_ node: LoupeNode) -> String? {
        [node.text, node.renderedText, node.semanticText, node.label, node.value, node.placeholder]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func accessibilityDisplayText(_ node: LoupeAccessibilityNode) -> String? {
        LoupeAccessibilityTreeQuery.displayText(for: node)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func isContainerOnly(_ node: LoupeNode) -> Bool {
        displayText(node) == nil
            && node.testID == nil
            && node.role == nil
            && !node.isInteractive
    }

    private static func isAccessibilityContainerOnly(_ node: LoupeAccessibilityNode) -> Bool {
        accessibilityDisplayText(node) == nil
            && node.testID == nil
            && node.role == nil
            && !node.isInteractive
    }

    private static func nodeConstraints(_ node: LoupeNode) -> [LoupeUILayoutConstraintProperties] {
        guard let layout = node.platform?.layout else {
            return []
        }
        var seen = Set<String>()
        var constraints: [LoupeUILayoutConstraintProperties] = []
        for constraint in layout.constraints + layout.affectingHorizontalConstraints + layout.affectingVerticalConstraints {
            let key = constraint.id.isEmpty ? constraintSummaryKey(constraint) : constraint.id
            guard !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            constraints.append(constraint)
        }
        return constraints.sorted {
            constraintDisplayName($0) < constraintDisplayName($1)
        }
    }

    private static func renderConstraints(
        node: LoupeNode,
        constraints: [LoupeUILayoutConstraintProperties]
    ) -> String {
        var lines = [
            "\(node.ref) \(node.platform?.className ?? node.typeName) constraints=\(constraints.count)"
        ]
        if constraints.isEmpty {
            lines.append("No captured Auto Layout constraints for this node.")
            return lines.joined(separator: "\n")
        }
        for constraint in constraints {
            lines.append(renderConstraintLine(constraint))
        }
        return lines.joined(separator: "\n")
    }

    private static func renderConstraintLine(_ constraint: LoupeUILayoutConstraintProperties) -> String {
        [
            constraint.id,
            constraint.isActive ? "active" : "inactive",
            "constant=\(format(constraint.constant))",
            "priority=\(format(constraint.priority))",
            "first=\(constraint.firstItem ?? "nil").\(constraint.firstAttribute)",
            "\(constraint.relation)",
            "second=\(constraint.secondItem ?? "nil").\(constraint.secondAttribute)",
            "multiplier=\(format(constraint.multiplier))",
            constraint.identifier.map { "identifier=\($0)" },
        ].compactMap(\.self).joined(separator: " ")
    }

    private static func constraintDisplayName(_ constraint: LoupeUILayoutConstraintProperties) -> String {
        [
            constraint.firstItem ?? "",
            constraint.firstAttribute,
            constraint.secondItem ?? "",
            constraint.secondAttribute,
            constraint.id,
        ].joined(separator: "|")
    }

    private static func constraintSummaryKey(_ constraint: LoupeUILayoutConstraintProperties) -> String {
        [
            constraint.identifier ?? "",
            constraint.firstItem ?? "",
            constraint.firstAttribute,
            constraint.relation,
            constraint.secondItem ?? "",
            constraint.secondAttribute,
            format(constraint.multiplier),
            format(constraint.constant),
            format(constraint.priority),
        ].joined(separator: "|")
    }

    static func renderNodeMutationCapabilities(_ node: LoupeNode) -> String {
        let supported = MutationPropertySupport.supportedProperties(for: node)
        let unsupported = MutationPropertySupport.unsupportedExamples(for: node)
        var lines = [
            "\(node.ref) \(node.platform?.className ?? node.typeName)",
            "supported: \(supported.isEmpty ? "none" : supported.joined(separator: ", "))",
        ]
        if !unsupported.isEmpty {
            lines.append("unsupported: \(unsupported.joined(separator: ", "))")
        }
        if !MutationPropertySupport.supportsTextMutation(node), displayText(node) != nil {
            lines.append("hint: visible text is semantic/accessibility text; mutate accessibility.label or inspect the source view instead of text.")
        }
        return lines.joined(separator: "\n")
    }

    private static func firstMatchingNode(_ selector: LoupeSelector, in snapshot: LoupeSnapshot) -> LoupeNode? {
        LoupeSnapshotQuery.find(
            selector,
            in: snapshot,
            options: LoupeQueryOptions(includeHidden: false, includeDisabled: true, maxResults: 1)
        ).first.flatMap { snapshot.nodes[$0.ref] }
    }

    private static func jsonValue(in node: LoupeNode, keyPath: String) -> Any? {
        let normalizedPath = keyPath
            .replacingOccurrences(of: "uikit.switch.", with: "uikit.switchControl.")
        guard let data = try? JSONEncoder().encode(node),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var current: Any? = object
        for key in normalizedPath.split(separator: ".").map(String.init) {
            if let dictionary = current as? [String: Any] {
                current = dictionary[key]
            } else {
                return nil
            }
        }
        return current
    }

    static func valueMatches(_ value: Any, expected: String) -> Bool {
        if let bool = value as? Bool {
            return bool == (expected as NSString).boolValue
        }
        if let number = value as? NSNumber {
            if expected == "true" || expected == "false" {
                return number.boolValue == (expected as NSString).boolValue
            }
            if let expectedNumber = Double(expected),
               numericValuesMatch(number.doubleValue, expected: expectedNumber) {
                return true
            }
            return format(number.doubleValue) == expected || String(number.intValue) == expected
        }
        if let string = value as? String {
            return string == expected
        }
        return String(describing: value) == expected
    }

    private static func numericValuesMatch(_ actual: Double, expected: Double) -> Bool {
        guard actual.isFinite, expected.isFinite else {
            return actual == expected
        }
        let tolerance = max(1e-6, abs(expected) * 1e-6)
        return abs(actual - expected) <= tolerance
    }

    static func mutationReflection(
        _ response: LoupeMutationResponse,
        sourceRoot: URL
    ) -> LoupeMutationReflection {
        let testID = response.after.testID ?? response.target.testID ?? mutationSelectorTestID(response.selector)
        let hierarchy = response.hierarchy ?? mutationHierarchyContext(response)
        let candidates = sourceCandidates(
            for: response,
            hierarchy: hierarchy,
            testID: testID,
            under: sourceRoot
        )
        return LoupeMutationReflection(
            selector: response.selector,
            property: response.property,
            value: response.value,
            targetType: response.after.platform?.className ?? response.after.typeName,
            testID: testID,
            before: mutationNodeSummary(response.before),
            after: mutationNodeSummary(response.after),
            targetMatchesHierarchy: targetMatchesHierarchy(response: response, hierarchy: hierarchy),
            hierarchy: hierarchy,
            sourceCandidates: candidates
        )
    }

    private static func mutationSelectorTestID(_ selector: LoupeMutationSelector) -> String? {
        selector.kind == .testID ? selector.value : nil
    }

    private struct RankedMutationSourceCandidate {
        var score: Int
        var candidate: LoupeMutationSourceCandidate
    }

    private static func sourceCandidates(
        for response: LoupeMutationResponse,
        hierarchy: LoupeMutationHierarchyContext,
        testID: String?,
        under sourceRoot: URL
    ) -> [LoupeMutationSourceCandidate] {
        if let testID {
            let customTypes = mutationCustomTypeTerms(from: hierarchy)
            let viewTypes = mutationTargetViewTypeTerms(from: hierarchy)
            let testIDCandidates = sourceCandidates(
                matching: testID,
                customTypes: customTypes,
                viewTypes: viewTypes,
                under: sourceRoot
            )
            if !testIDCandidates.isEmpty {
                return testIDCandidates
            }
        }

        return hierarchySourceCandidates(response: response, hierarchy: hierarchy, under: sourceRoot)
    }

    private static func sourceCandidates(
        matching testID: String,
        customTypes: [String],
        viewTypes: [String],
        under sourceRoot: URL
    ) -> [LoupeMutationSourceCandidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var candidates: [RankedMutationSourceCandidate] = []
        for case let url as URL in enumerator {
            guard isSearchableSource(url),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            let fileScore = mutationSourceFileScore(url: url, text: text, customTypes: customTypes, viewTypes: viewTypes)
            for (offset, line) in text.components(separatedBy: .newlines).enumerated()
                where line.contains(testID) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                candidates.append(
                    RankedMutationSourceCandidate(
                        score: fileScore + mutationTestIDSourceLineScore(
                            trimmed,
                            testID: testID,
                            customTypes: customTypes,
                            viewTypes: viewTypes
                        ),
                        candidate: LoupeMutationSourceCandidate(
                            path: url.path,
                            line: offset + 1,
                            text: trimmed
                        )
                    )
                )
            }
        }

        return candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.candidate.path != $1.candidate.path { return $0.candidate.path < $1.candidate.path }
            return $0.candidate.line < $1.candidate.line
        }.prefix(12).map(\.candidate)
    }

    private static func hierarchySourceCandidates(
        response: LoupeMutationResponse,
        hierarchy: LoupeMutationHierarchyContext,
        under sourceRoot: URL
    ) -> [LoupeMutationSourceCandidate] {
        let customTypes = mutationCustomTypeTerms(from: hierarchy)
        let viewTypes = mutationTargetViewTypeTerms(from: hierarchy)
        let propertyTerms = mutationPropertySourceTerms(response.property)
        let literalTerms = mutationLiteralSourceTerms(from: hierarchy)
        guard !customTypes.isEmpty || !propertyTerms.isEmpty else {
            return []
        }
        if customTypes.isEmpty,
           literalTerms.isEmpty,
           isWeakStandaloneMutationProperty(response.property) {
            return []
        }
        guard let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var ranked: [String: RankedMutationSourceCandidate] = [:]
        for case let url as URL in enumerator {
            guard isSearchableSource(url),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            let fileScore = mutationSourceFileScore(url: url, text: text, customTypes: customTypes, viewTypes: viewTypes)
            guard fileScore > 0 || customTypes.isEmpty else {
                continue
            }

            for (offset, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    continue
                }
                var score = fileScore
                let hasProperty = containsAnySourceTerm(trimmed, terms: propertyTerms)
                let hasCustomType = containsAnySourceTerm(trimmed, terms: customTypes)
                let hasViewType = containsAnySourceTerm(trimmed, terms: viewTypes)
                let hasLiteral = containsAny(trimmed, terms: literalTerms)
                if trimmed.hasPrefix("//"), !hasProperty {
                    continue
                }
                guard hasProperty || hasCustomType || hasViewType || hasLiteral else {
                    continue
                }
                if hasProperty { score += 60 }
                if hasCustomType { score += 25 }
                if hasViewType { score += 15 }
                if hasLiteral { score += mutationLiteralSourceLineScore(trimmed, hierarchy: hierarchy) }
                guard score >= 35 else {
                    continue
                }

                let candidate = LoupeMutationSourceCandidate(
                    path: url.path,
                    line: offset + 1,
                    text: trimmed
                )
                let key = "\(candidate.path):\(candidate.line)"
                if let existing = ranked[key], existing.score >= score {
                    continue
                }
                ranked[key] = RankedMutationSourceCandidate(score: score, candidate: candidate)
            }
        }

        return ranked.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.candidate.path != $1.candidate.path { return $0.candidate.path < $1.candidate.path }
            return $0.candidate.line < $1.candidate.line
        }.prefix(12).map(\.candidate)
    }

    private static func mutationSourceFileScore(
        url: URL,
        text: String,
        customTypes: [String],
        viewTypes: [String]
    ) -> Int {
        let fileName = url.deletingPathExtension().lastPathComponent
        var score = 0
        for type in customTypes {
            if fileName.caseInsensitiveCompare(type) == .orderedSame {
                score += 80
            } else if sourceTermMatches(fileName, term: type) {
                score += 40
            }
            if text.localizedCaseInsensitiveContains("class \(type)")
                || text.localizedCaseInsensitiveContains("struct \(type)")
                || text.localizedCaseInsensitiveContains("final class \(type)") {
                score += 70
            } else if containsAnySourceTerm(text, terms: [type]) {
                score += 15
            }
        }
        for type in viewTypes where !customTypes.contains(type) {
            if containsAnySourceTerm(text, terms: [type]) {
                score += 3
            }
        }
        return score
    }

    private static func mutationLiteralSourceLineScore(
        _ line: String,
        hierarchy: LoupeMutationHierarchyContext
    ) -> Int {
        var score = 20
        if line.localizedCaseInsensitiveContains("Text(")
            || line.localizedCaseInsensitiveContains("Label(")
            || line.localizedCaseInsensitiveContains("Button(")
            || line.localizedCaseInsensitiveContains("TextField(")
            || line.localizedCaseInsensitiveContains("SecureField(")
            || line.localizedCaseInsensitiveContains(".navigationTitle")
            || line.localizedCaseInsensitiveContains(".tabItem")
            || line.localizedCaseInsensitiveContains("accessibilityLabel") {
            score += 25
        }
        if hierarchy.parent?.typeName.localizedCaseInsensitiveContains("NavigationBar") == true
            && line.localizedCaseInsensitiveContains(".navigationTitle") {
            score += 35
        }
        return score
    }

    private static func mutationTestIDSourceLineScore(
        _ line: String,
        testID: String,
        customTypes: [String],
        viewTypes: [String]
    ) -> Int {
        var score = 20
        if line.contains("\"\(testID)\"") || line.contains("'\(testID)'") {
            score += 35
        }
        if line.localizedCaseInsensitiveContains("accessibilityIdentifier")
            || line.localizedCaseInsensitiveContains("NSUserInterfaceItemIdentifier")
            || line.localizedCaseInsensitiveContains(".identifier") {
            score += 65
        }
        if line.localizedCaseInsensitiveContains("class \(testID)")
            || line.localizedCaseInsensitiveContains("struct \(testID)")
            || line.localizedCaseInsensitiveContains("final class \(testID)") {
            score += 60
        }
        if line.localizedCaseInsensitiveContains("\(testID)(") {
            score += 45
        }
        if containsAnySourceTerm(line, terms: customTypes) {
            score += 20
        }
        if containsAnySourceTerm(line, terms: viewTypes) {
            score += 10
        }
        if line.localizedCaseInsensitiveContains("#selector")
            || line.localizedCaseInsensitiveContains("NotificationCenter.default.publisher") {
            score -= 25
        }
        return score
    }

    private static func mutationCustomTypeTerms(from hierarchy: LoupeMutationHierarchyContext) -> [String] {
        mutationHierarchyTypeTerms(from: hierarchy).filter(isSpecificMutationSourceType)
    }

    private static func mutationHierarchyTypeTerms(from hierarchy: LoupeMutationHierarchyContext) -> [String] {
        var terms: [String?] = [
            hierarchy.parent?.typeName,
            hierarchy.target.typeName,
        ]
        terms.append(contentsOf: (hierarchy.ancestors ?? []).map(\.typeName))
        terms.append(contentsOf: hierarchy.siblings.map(\.typeName))
        terms.append(contentsOf: hierarchy.children.map(\.typeName))
        return uniqueSourceTerms(terms)
    }

    private static func mutationTargetViewTypeTerms(from hierarchy: LoupeMutationHierarchyContext) -> [String] {
        uniqueSourceTerms([hierarchy.target.typeName])
    }

    private static func mutationPropertySourceTerms(_ property: String) -> [String] {
        let base = property.split(separator: ".").last.map(String.init) ?? property
        let terms: [String]
        switch property {
        case "textColor":
            terms = ["textColor", "foregroundColor"]
        case "backgroundColor":
            terms = ["backgroundColor"]
        case "tintColor":
            terms = ["tintColor"]
        case "cornerRadius":
            terms = ["cornerRadius", "layer.cornerRadius"]
        case "borderWidth":
            terms = ["borderWidth", "layer.borderWidth"]
        case "borderColor":
            terms = ["borderColor", "layer.borderColor"]
        case "fontSize":
            terms = ["font", "pointSize", "systemFont"]
        default:
            if property.hasPrefix("layout.") {
                terms = [base, "constraint", "NSLayoutConstraint", "contentHuggingPriority", "compressionResistancePriority"]
            } else {
                terms = [property, base]
            }
        }
        return uniqueSourceTerms(terms)
    }

    private static func isWeakStandaloneMutationProperty(_ property: String) -> Bool {
        let normalized = property.lowercased()
        return weakStandaloneMutationProperties.contains(normalized)
            || normalized.hasPrefix("layout.")
    }

    private static func mutationLiteralSourceTerms(from hierarchy: LoupeMutationHierarchyContext) -> [String] {
        var terms: [String?] = [
            hierarchy.target.testID,
            hierarchy.target.text,
            hierarchy.parent?.testID,
            hierarchy.parent?.text,
        ]
        terms.append(contentsOf: (hierarchy.ancestors ?? []).flatMap { [$0.testID, $0.text] })
        return uniqueLiteralTerms(terms)
    }

    private static let genericUIKitTypeNames: Set<String> = [
        "NSObject",
        "UIResponder",
        "UIApplication",
        "UIWindow",
        "UIView",
        "UIControl",
        "UILabel",
        "UIImageView",
        "UIButton",
        "UITextField",
        "UITextView",
        "UISwitch",
        "UISlider",
        "UIScrollView",
        "UICollectionView",
        "UICollectionViewCell",
        "UITableView",
        "UITableViewCell",
        "UIStackView",
        "UIVisualEffectView",
        "NSView",
        "NSControl",
        "NSTextField",
        "NSButton",
        "NSScrollView",
        "NSCollectionView",
        "NSTableView",
    ]

    private static let genericSwiftUIRuntimeTypeNames: Set<String> = [
        "AnyView",
        "CellHostingView",
        "CollectionViewCellModifier",
        "CollectionViewListDataSource",
        "CoreInteractionRepresentableAdaptor",
        "EmptyModifier",
        "HostingView",
        "ListRepresentable",
        "ModifiedContent",
        "PlatformViewControllerRepresentableAdaptor",
        "PresentationHostingController",
        "RootModifier",
        "ScrollPocketElementInteractionRepresentable",
        "SelectionManagerBox",
        "TupleView",
        "UIKitAdaptableTabView",
        "UIKitPlatformViewHost",
        "ViewModifier_Content",
        "_ConditionalContent",
        "_FrameLayout",
        "_TraitWritingModifier",
        "_ViewList_View",
    ]

    private static let weakStandaloneMutationProperties: Set<String> = [
        "alpha",
        "bounces",
        "bounds",
        "center",
        "contentinset",
        "contentoffset",
        "contentsize",
        "enabled",
        "frame",
        "hidden",
        "layer.opacity",
        "layer.zposition",
    ]

    private static func isSpecificMutationSourceType(_ term: String) -> Bool {
        !genericUIKitTypeNames.contains(term)
            && !genericSwiftUIRuntimeTypeNames.contains(term)
            && !term.hasPrefix("_")
    }

    private static func uniqueSourceTerms(_ terms: [String?]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in terms {
            for term in normalizedSourceTerms(raw) {
                let key = term.lowercased()
                if seen.insert(key).inserted {
                    result.append(term)
                }
            }
        }
        return result
    }

    private static func uniqueLiteralTerms(_ terms: [String?]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for raw in terms {
            guard let term = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  term.count >= 3,
                  term.count <= 80 else {
                continue
            }
            let key = term.lowercased()
            if seen.insert(key).inserted {
                result.append(term)
            }
        }
        return result
    }

    private static func normalizedSourceTerms(_ raw: String?) -> [String] {
        guard let raw else {
            return []
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        if let directTerm = normalizedSimpleSourceTerm(trimmed) {
            return [directTerm]
        }

        var terms: [String] = []
        var seen: Set<String> = []
        let tokens = trimmed.split { !isSourceIdentifierCharacter($0) }
        for token in tokens {
            guard let term = normalizedSimpleSourceTerm(String(token)) else {
                continue
            }
            let key = term.lowercased()
            if seen.insert(key).inserted {
                terms.append(term)
            }
        }
        return terms
    }

    private static func normalizedSimpleSourceTerm(_ raw: String) -> String? {
        let leaf = raw.split(separator: ".").last.map(String.init) ?? raw
        guard leaf.count >= 2, leaf.allSatisfy({ isSourceIdentifierCharacter($0) }) else {
            return nil
        }
        return leaf
    }

    private static func containsAny(_ value: String, terms: [String]) -> Bool {
        terms.contains { value.localizedCaseInsensitiveContains($0) }
    }

    private static func containsAnySourceTerm(_ value: String, terms: [String]) -> Bool {
        terms.contains { sourceTermMatches(value, term: $0) }
    }

    private static func sourceTermMatches(_ value: String, term: String) -> Bool {
        if term.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" }) {
            return value.localizedCaseInsensitiveContains(term)
        }

        let lowerValue = value.lowercased()
        let lowerTerm = term.lowercased()
        var searchStart = lowerValue.startIndex
        while let range = lowerValue.range(of: lowerTerm, range: searchStart..<lowerValue.endIndex) {
            let beforeOK = range.lowerBound == lowerValue.startIndex
                || !isSourceIdentifierCharacter(lowerValue[lowerValue.index(before: range.lowerBound)])
            let afterOK = range.upperBound == lowerValue.endIndex
                || !isSourceIdentifierCharacter(lowerValue[range.upperBound])
            if beforeOK && afterOK {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isSourceIdentifierCharacter(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    private static func isSearchableSource(_ url: URL) -> Bool {
        ["swift", "m", "mm", "h", "xib", "storyboard"].contains(url.pathExtension)
    }

    private static func mutationHierarchyContext(_ response: LoupeMutationResponse) -> LoupeMutationHierarchyContext {
        LoupeMutationHierarchyContext(
            target: mutationNodeSummary(response.after),
            parent: response.after.parentRef.map {
                LoupeMutationNodeSummary(ref: $0, typeName: "unknown")
            },
            siblings: [],
            children: response.after.children.map {
                LoupeMutationNodeSummary(ref: $0, typeName: "unknown")
            }
        )
    }

    private static func targetMatchesHierarchy(
        response: LoupeMutationResponse,
        hierarchy: LoupeMutationHierarchyContext
    ) -> Bool {
        guard hierarchy.target.ref == response.after.ref else {
            return false
        }

        switch response.selector.kind {
        case .testID:
            return hierarchy.target.testID == response.selector.value
        case .ref:
            return hierarchy.target.ref == response.selector.value
        case .role:
            return hierarchy.target.role == response.selector.value
        case .text:
            guard let text = hierarchy.target.text else {
                return false
            }
            if response.selector.exact {
                return text == response.selector.value
            }
            return text.localizedCaseInsensitiveContains(response.selector.value)
        case .roleAndText:
            guard hierarchy.target.role == response.selector.role,
                  let text = hierarchy.target.text else {
                return false
            }
            if response.selector.exact {
                return text == response.selector.value
            }
            return text.localizedCaseInsensitiveContains(response.selector.value)
        }
    }

    private static func mutationNodeSummary(_ node: LoupeNode) -> LoupeMutationNodeSummary {
        LoupeMutationNodeSummary(
            ref: node.ref,
            typeName: node.platform?.className ?? node.typeName,
            role: node.role,
            testID: node.testID,
            text: displayText(node),
            frame: node.frame
        )
    }

    static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func format(_ value: Double) -> String {
        if value.isFinite, value.rounded() == value, let intValue = Int(exactly: value) {
            return String(intValue)
        }
        return String(value)
    }

}
