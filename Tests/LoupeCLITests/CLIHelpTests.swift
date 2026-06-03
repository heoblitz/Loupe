@testable import LoupeCLI
import Foundation
import Testing

@Suite struct CLIHelpTests {
    @Test func versionFallsBackToDevelopmentVersionOutsideHomebrew() {
        #expect(LoupeCLI.versionString(executablePath: "/tmp/loupe/.build/debug/loupe") == "0.1.4-dev")
    }

    @Test func versionCanBeDetectedFromHomebrewCellarPath() {
        #expect(
            LoupeCLI.versionString(
                executablePath: "/opt/homebrew/Cellar/loupe/1.2.3/bin/loupe"
            ) == "1.2.3"
        )
    }

    @Test func versionCanBeDetectedFromResolvedHomebrewSymlinkPath() {
        #expect(
            LoupeCLI.versionString(
                executablePath: "/opt/homebrew/bin/loupe",
                resolvedExecutablePath: "/opt/homebrew/Cellar/loupe/1.2.3/bin/loupe"
            ) == "1.2.3"
        )
    }

    @Test func summaryHelpUsesConciseTuistStyleOverview() {
        let output = LoupeCLI.summaryHelp(version: "1.2.3")

        #expect(output.contains("OVERVIEW:"))
        #expect(output.contains("VERSION: 1.2.3"))
        #expect(output.contains("USAGE: loupe <domain> <subcommand>"))
        #expect(output.contains("DOMAINS:"))
        #expect(output.contains("target                  Select a runtime target."))
        #expect(output.contains("debug                   Read logs, network events, and reference evidence."))
        #expect(output.contains("state                   Inspect defaults, flags, and keychain metadata."))
        #expect(output.contains("Existing flat commands remain as compatibility aliases."))
        #expect(output.contains("See 'loupe help <domain> <subcommand>' for detailed help."))
        #expect(LoupeCLI.summaryHelpLineCount(version: "1.2.3") <= 50)
        #expect(!output.contains("accessibility <snapshot.json>"))
        #expect(!output.contains("wait-for-value"))
    }

    @Test func groupedCommandUsageFirstLinesStayStable() throws {
        let expectedUsage: [String: String] = [
            "target": "Usage: loupe target <subcommand>",
            "target list": "Usage: loupe target list [--json] [--timeout <seconds>]",
            "runtime": "Usage: loupe runtime <subcommand>",
            "runtime start": "Usage: loupe runtime start --bundle-id <id> [--device <sim>|--udid <sim>] [--port <port>] [--env KEY=VALUE] [--timeout <seconds>]",
            "runtime logs": "Usage: loupe runtime logs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "observe": "Usage: loupe observe <subcommand>",
            "observe capture": "Usage: loupe observe capture [--host <url>] [--udid <sim>] [--bundle-id <id>] --output <dir> [--screen-map-limit <n>] [--timeout <seconds>]",
            "observe tree": "Usage: loupe observe tree [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--view|--accessibility] [--depth <n>]",
            "inspect": "Usage: loupe inspect <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--include-hidden] [--node-only|--fields node,parent,children,siblings]",
            "inspect node": "Usage: loupe inspect node <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--include-hidden] [--fields node,parent,children,siblings]",
            "act": "Usage: loupe act <subcommand>",
            "act tap": "Usage: loupe act tap (--test-id <id> | --ref <ref> | --x <n> --y <n>) --udid <sim> [--host <url>] [--snapshot <snapshot.json>] [--trace-dir <path>] [--expect-visible <testID>]",
            "act press": "Usage: loupe act press up|down|left|right|select|menu|playPause --udid <sim> [--host <url>] [--trace-dir <path>] [--expect-visible <testID>]",
            "act wait": "Usage: loupe act wait visible|gone|value <selector> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--timeout <seconds>]",
            "ui": "Usage: loupe ui <subcommand>",
            "ui set": "Usage: loupe ui set (--test-id <id> | --ref <ref> | --role <role> | --text <text>) <property> <value> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "ui hit-test": "Usage: loupe ui hit-test --point x,y [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug": "Usage: loupe debug <subcommand>",
            "debug network": "Usage: loupe debug network [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug refs": "Usage: loupe debug refs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug object-graph": "Usage: loupe debug object-graph [target|--target <name>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug heap": "Usage: loupe debug heap [target|--target <name>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "state": "Usage: loupe state <subcommand>",
            "state keychain": "Usage: loupe state keychain list [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "env": "Usage: loupe env <subcommand>",
            "env appearance": "Usage: loupe env appearance [light|dark|system] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "perf": "Usage: loupe perf <subcommand>",
            "perf scroll": "Usage: loupe perf scroll --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--trace-dir <path>] [--output <path>]",
            "trace": "Usage: loupe trace <subcommand>",
            "trace summary": "Usage: loupe trace summary <trace-dir> [--json] [--limit <n>]",
        ]

        for (command, expected) in expectedUsage {
            #expect(try firstNonEmptyLine(from: LoupeCLI.commandUsage(command)) == expected)
        }
    }

    @Test func publicCommandUsageFirstLinesStayStable() throws {
        let expectedUsage: [String: String] = [
            "start": "Usage: loupe start --bundle-id <id> [--device <sim>|--udid <sim>] [--port <port>] [--env KEY=VALUE] [--timeout <seconds>]",
            "capture-report": "Usage: loupe capture-report [--host <url>] [--udid <sim>] [--bundle-id <id>] --output <dir> [--screen-map-limit <n>] [--timeout <seconds>]",
            "logs": "Usage: loupe logs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "tree": "Usage: loupe tree [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--view|--accessibility] [--depth <n>]",
            "tap": "Usage: loupe tap (--test-id <id> | --ref <ref> | --x <n> --y <n>) --udid <sim> [--host <url>] [--snapshot <snapshot.json>] [--trace-dir <path>] [--expect-visible <testID>]",
            "swipe": "Usage: loupe swipe --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--no-verify-scroll] [--trace-dir <path>]",
            "drag": "Usage: loupe drag --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--trace-dir <path>]",
            "type": "Usage: loupe type <text> --udid <sim> [--host <url>] [--trace-dir <path>]",
            "press": "Usage: loupe press up|down|left|right|select|menu|playPause --udid <sim> [--host <url>] [--trace-dir <path>] [--expect-visible <testID>]",
            "trace-summary": "Usage: loupe trace-summary <trace-dir> [--json] [--limit <n>]",
            "diff": "Usage: loupe diff <before-snapshot.json> <after-snapshot.json> [--json] [--changed-only] [--limit <n>]",
            "screenshot": "Usage: loupe screenshot --udid <sim> --output <path> [--timeout <seconds>]",
            "cleanup": "Usage: loupe cleanup [--dry-run] [--no-runtimes] [--no-traces] [--traces-older-than <duration>|--all-traces] [--timeout <seconds>]",
            "set": "Usage: loupe set (--test-id <id> | --ref <ref> | --role <role> | --text <text>) <property> <value> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "set-many": "Usage: loupe set-many (--refs <refs> | --type-name <name> | --role <role>) <property> (--value <value> | --number <n> | --bool <bool> | --color <color> | --colors <colors>)",
            "mutations": "Usage: loupe mutations [--host <url>] [--udid <sim>] [--bundle-id <id>]",
            "constraints": "Usage: loupe constraints [snapshot.json] (--ref <ref> | --test-id <id> | --text <text>) [--json]",
            "set-constraint": "Usage: loupe set-constraint --id <constraint-id> constant <value> [priority <value>] [active true|false]",
        ]

        for (command, expected) in expectedUsage {
            #expect(try firstNonEmptyLine(from: LoupeCLI.commandUsage(command)) == expected)
        }
    }

    @Test func simulatorLaunchHelpIsNotIOSOnly() throws {
        let start = try #require(LoupeCLI.commandUsage("start"))
        let launch = try #require(LoupeCLI.commandUsage("launch"))

        #expect(start.contains("Apple simulator app"))
        #expect(launch.contains("Apple simulator app"))
        #expect(!start.contains("iOS Simulator app"))
        #expect(!launch.contains("iOS Simulator app"))
    }

    @Test func perfScrollHelpIncludesRuntimeOffsetMode() throws {
        let help = try #require(LoupeCLI.commandUsage("perf scroll"))

        #expect(help.contains("--from x,y --to x,y --udid <sim>"))
        #expect(help.contains("--delta dx,dy|--to-offset x,y"))
        #expect(help.contains("[--bundle-id <id>]"))
    }

    @Test func publicCommandHelpIsAvailableForActionAndMutationCommands() {
        let publicCommands = [
            "target",
            "runtime",
            "observe",
            "inspect",
            "act",
            "ui",
            "debug",
            "state",
            "env",
            "perf",
            "trace",
            "start",
            "capture-report",
            "logs",
            "tree",
            "tap",
            "swipe",
            "drag",
            "type",
            "press",
            "trace-summary",
            "diff",
            "screenshot",
            "cleanup",
            "set",
            "set-many",
            "mutations",
            "constraints",
            "set-constraint",
            "deactivate-constraint",
        ]

        for command in publicCommands {
            #expect(LoupeCLI.commandUsage(command) != nil)
        }
    }

    private func firstNonEmptyLine(from text: String?) throws -> String {
        let text = try #require(text)
        return try #require(
            text.split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
        )
    }
}
