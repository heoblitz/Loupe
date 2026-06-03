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

    @Test func summaryHelpUsesFourStableCommandGroups() {
        let output = LoupeCLI.summaryHelp(version: "1.2.3")

        #expect(output.contains("OVERVIEW:"))
        #expect(output.contains("VERSION: 1.2.3"))
        #expect(output.contains("USAGE: loupe <command-group> <subcommand>"))
        #expect(output.contains("COMMAND GROUPS:"))
        #expect(output.contains("app                     Launch, select, and inspect app runtimes."))
        #expect(output.contains("ui                      Capture, inspect, audit, and mutate UI state."))
        #expect(output.contains("act                     Dispatch input and wait for UI state."))
        #expect(output.contains("debug                   Read and change diagnostic app state."))
        #expect(output.contains("See 'loupe help <command-group> <subcommand>' for detailed help."))
        #expect(LoupeCLI.summaryHelpLineCount(version: "1.2.3") <= 50)
        #expect(!output.contains("Existing flat commands"))
        #expect(!output.contains("observe"))
        #expect(!output.contains("target"))
        #expect(!output.contains("state                   "))
    }

    @Test func groupedCommandUsageFirstLinesStayStable() throws {
        let expectedUsage: [String: String] = [
            "app": "Usage: loupe app <subcommand>",
            "app launch": "Usage: loupe app launch --bundle-id <id> [--device <sim>|--udid <sim>] [--port <port>] [--env KEY=VALUE] [--timeout <seconds>]",
            "app list": "Usage: loupe app list [--json] [--timeout <seconds>]",
            "app use": "Usage: loupe app use <bundle-id> | --bundle-id <id> | --host <url> [--udid <sim>]",
            "app current": "Usage: loupe app current [--json] [--timeout <seconds>]",
            "app info": "Usage: loupe app info [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "ui": "Usage: loupe ui <subcommand>",
            "ui report": "Usage: loupe ui report [--host <url>] [--udid <sim>] [--bundle-id <id>] --output <dir> [--screen-map-limit <n>] [--timeout <seconds>]",
            "ui snapshot": "Usage: loupe ui snapshot [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>] [--timeout <seconds>]",
            "ui tree": "Usage: loupe ui tree [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--view|--accessibility] [--depth <n>]",
            "ui node": "Usage: loupe ui node <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--include-hidden] [--fields node,parent,children,siblings]",
            "ui set": "Usage: loupe ui set (--test-id <id> | --ref <ref> | --role <role> | --text <text>) <property> <value> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "act": "Usage: loupe act <subcommand>",
            "act tap": "Usage: loupe act tap (--test-id <id> | --ref <ref> | --x <n> --y <n>) --udid <sim> [--host <url>] [--snapshot <snapshot.json>] [--trace-dir <path>] [--expect-visible <testID>]",
            "act press": "Usage: loupe act press up|down|left|right|select|menu|playPause --udid <sim> [--host <url>] [--trace-dir <path>] [--expect-visible <testID>]",
            "act wait": "Usage: loupe act wait visible|gone|value <selector> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--timeout <seconds>]",
            "debug": "Usage: loupe debug <subcommand>",
            "debug logs": "Usage: loupe debug logs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug network": "Usage: loupe debug network [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug refs": "Usage: loupe debug refs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug object-graph": "Usage: loupe debug object-graph [target|--target <name>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug keychain": "Usage: loupe debug keychain [list] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug flags": "Usage: loupe debug flags get|set|unset <key> [value] [--bool true|false] [--number n] [--host <url>] [--output <path>]",
            "debug trace summary": "Usage: loupe debug trace summary <trace-dir> [--json] [--limit <n>]",
            "debug scroll": "Usage: loupe debug scroll --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--trace-dir <path>] [--output <path>]",
        ]

        for (command, expected) in expectedUsage {
            #expect(try firstNonEmptyLine(from: LoupeCLI.commandUsage(command)) == expected)
        }
    }

    @Test func launchAndScrollHelpIncludePlatformNeutralWording() throws {
        let launch = try #require(LoupeCLI.commandUsage("app launch"))
        let scroll = try #require(LoupeCLI.commandUsage("debug scroll"))

        #expect(launch.contains("bundle-id"))
        #expect(!launch.contains("iOS Simulator app"))
        #expect(scroll.contains("--from x,y --to x,y --udid <sim>"))
        #expect(scroll.contains("--delta dx,dy|--to-offset x,y"))
        #expect(scroll.contains("[--bundle-id <id>]"))
    }

    @Test func publicCommandHelpIsAvailableForGroupedCommands() {
        let publicCommands = [
            "app",
            "app launch",
            "app list",
            "app use",
            "app current",
            "app info",
            "app cleanup",
            "ui",
            "ui report",
            "ui snapshot",
            "ui compact",
            "ui tree",
            "ui screen",
            "ui accessibility",
            "ui screenshot",
            "ui node",
            "ui query",
            "ui subtree",
            "ui paint",
            "ui audit",
            "ui constraints",
            "ui hit-test",
            "ui responder-chain",
            "ui appearance",
            "ui mutations",
            "ui set",
            "ui set-many",
            "ui set-constraint",
            "ui deactivate-constraint",
            "ui reflect",
            "ui compare-design",
            "act",
            "act tap",
            "act swipe",
            "act drag",
            "act type",
            "act press",
            "act wait",
            "debug",
            "debug logs",
            "debug network",
            "debug refs",
            "debug object-graph",
            "debug heap",
            "debug keychain",
            "debug defaults",
            "debug flags",
            "debug trace",
            "debug trace summary",
            "debug trace diff",
            "debug trace explore",
            "debug trace cleanup",
            "debug scroll",
        ]

        for command in publicCommands {
            #expect(LoupeCLI.commandUsage(command) != nil)
        }
    }

    @Test func ambiguousCompatibilityCommandsAreNotPublic() {
        let removedCommands = [
            "target", "runtime", "observe", "capture", "inspect", "state", "env", "perf", "trace",
            "start", "launch", "tree", "tap", "set", "set-many", "constraints", "logs", "diff",
            "debug console", "act pinch",
        ]

        for command in removedCommands {
            #expect(LoupeCLI.commandUsage(command) == nil)
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
