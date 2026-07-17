@testable import LoupeCLI
import Foundation
import Testing

@Suite struct CLIHelpTests {
    @Test func versionFallsBackToDevelopmentVersionOutsideHomebrew() {
        #expect(LoupeCLI.versionString(executablePath: "/tmp/loupe/.build/debug/loupe") == "0.1.5-dev")
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

    @Test func summaryHelpUsesStableCommandGroups() {
        let output = LoupeCLI.summaryHelp(version: "1.2.3")

        #expect(output.contains("OVERVIEW:"))
        #expect(output.contains("VERSION: 1.2.3"))
        #expect(output.contains("USAGE: loupe <command-group> <subcommand>"))
        #expect(output.contains("COMMAND GROUPS:"))
        #expect(output.contains("app                     Launch, select, and inspect app runtimes."))
        #expect(output.contains("ui                      Capture, inspect, audit, and mutate UI state."))
        #expect(output.contains("act                     Dispatch input and wait for UI state."))
        #expect(output.contains("debug                   Read and change diagnostic app state."))
        #expect(output.contains("skills                  Install Loupe workflow skills."))
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
            "app launch": "Usage: loupe app launch --bundle-id <id> [--device <sim|device|udid>] [--inject|--linked] [--host <url>] [--port <port>] [--bind-host <ip>] [--env KEY=VALUE] [--timeout <seconds>]",
            "app list": "Usage: loupe app list [--json] [--timeout <seconds>]",
            "app use": "Usage: loupe app use <bundle-id> | --bundle-id <id> | --host <url> [--udid <sim>]",
            "app current": "Usage: loupe app current [--json] [--timeout <seconds>]",
            "app info": "Usage: loupe app info [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "ui": "Usage: loupe ui <subcommand>",
            "ui report": "Usage: loupe ui report [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <dir>] [--screen-map-limit <n>] [--timeout <seconds>]",
            "ui snapshot": "Usage: loupe ui snapshot [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>] [--timeout <seconds>]",
            "ui tree": "Usage: loupe ui tree [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--view|--accessibility] [--depth <n>]",
            "ui node": "Usage: loupe ui node <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--include-hidden] [--fields node,parent,children,siblings]",
            "ui query": "Usage: loupe ui query [snapshot.json] (--test-id <id> | --text <text> | --exact-text <text> | --role <role> | --ref <ref>) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--tree view|accessibility] [--include-hidden] [--max-results <n>] [--wait] [--timeout <seconds>]",
            "ui compare-design": "Usage: loupe ui compare-design <snapshot.json> <design.json> [--json] [--suggest-mutations] [--host <url>] [--limit <n>] [--frame-tolerance <n>] [--color-tolerance <n>] [--corner-radius-tolerance <n>] [--font-size-tolerance <n>] [--max-match-distance <n>] [--no-unexpected]",
            "ui apply-design-suggestions": "Usage: loupe ui apply-design-suggestions <compare-design.json> [--host <url>] [--snapshot <snapshot.json>] [--output-dir <dir>] [--max <n>] [--properties <list>] [--dry-run]",
            "ui set": "Usage: loupe ui set (--test-id <id> | --ref <ref> | --role <role> | --text <text>) <property> <value> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--snapshot <snapshot.json>] [--include-hidden] [--output <path>]",
            "act": "Usage: loupe act <subcommand>",
            "act targets": "Usage: loupe act targets [--udid <sim>] [--host <url>] [--timeout <seconds>]",
            "act tap": "Usage: loupe act tap ('#N' | --test-id <id> | --ref <view-or-ax-ref> | --x <n> --y <n>) [--udid <sim>] [--host <url>] [--backend native|runtime|auto] [--snapshot <snapshot.json>] [--trace-dir <path>] [--expect-visible <testID>] [--timeout <seconds>]",
            "act swipe": "Usage: loupe act swipe --from x,y --to x,y [--udid <sim>] [--host <url>] [--duration <seconds>] [--no-verify-scroll] [--trace-dir <path>] [--timeout <seconds>]",
            "act drag": "Usage: loupe act drag --from x,y --to x,y [--udid <sim>] [--host <url>] [--duration <seconds>] [--trace-dir <path>] [--timeout <seconds>]",
            "act type": "Usage: loupe act type <text> [--udid <sim>] [--host <url>] [--trace-dir <path>] [--timeout <seconds>]",
            "act press": "Usage: loupe act press up|down|left|right|select|menu|playPause [--udid <sim>] [--host <url>] [--trace-dir <path>] [--expect-visible <testID>] [--timeout <seconds>]",
            "act wait": "Usage: loupe act wait visible|gone (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--timeout <seconds>] [--output <path>]",
            "debug": "Usage: loupe debug <subcommand>",
            "debug logs": "Usage: loupe debug logs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug network": "Usage: loupe debug network [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug refs": "Usage: loupe debug refs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug object-graph": "Usage: loupe debug object-graph [target|--target <name>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug objects classes": "Usage: loupe debug objects classes [--matching <name>] [--limit <n>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug objects describe": "Usage: loupe debug objects describe <class|--class <name>> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug leaks": "Usage: loupe debug leaks [--alive-only] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug keychain": "Usage: loupe debug keychain [list] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]",
            "debug flags": "Usage: loupe debug flags get|set|unset <key> [value] [--bool true|false] [--number n] [--host <url>] [--output <path>]",
            "debug trace summary": "Usage: loupe debug trace summary <trace-dir> [--json] [--limit <n>]",
            "debug scroll": "Usage: loupe debug scroll --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--trace-dir <path>] [--output <path>]",
            "skills": "Usage: loupe skills <subcommand>",
            "skills install": "Usage: loupe skills install [--target all|codex|claude] [--source <skill-dir>]",
        ]

        for (command, expected) in expectedUsage {
            #expect(try firstNonEmptyLine(from: LoupeCLI.commandUsage(command)) == expected)
        }
    }

    @Test func launchScrollAndWaitHelpIncludeSpecificWording() throws {
        let launch = try #require(LoupeCLI.commandUsage("app launch"))
        let scroll = try #require(LoupeCLI.commandUsage("debug scroll"))
        let wait = try #require(LoupeCLI.commandUsage("act wait"))

        #expect(launch.contains("bundle-id"))
        #expect(!launch.contains("iOS Simulator app"))
        #expect(launch.contains("<sim|device|udid>"))
        #expect(launch.contains("LOUPE_INJECTOR_PATH"))
        #expect(launch.contains("Homebrew injector"))
        #expect(launch.contains("loupe injector-path"))
        #expect(scroll.contains("--from x,y --to x,y --udid <sim>"))
        #expect(scroll.contains("--delta dx,dy|--to-offset x,y"))
        #expect(scroll.contains("[--bundle-id <id>]"))
        #expect(wait.contains("loupe act wait value"))
        #expect(wait.contains("--key <path> --equals <value>"))
        #expect(wait.contains("[--interval <seconds>]"))
        #expect(wait.contains("[--output <path>]"))
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
            "ui apply-design-suggestions",
            "act",
            "act targets",
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
            "debug objects",
            "debug objects classes",
            "debug objects describe",
            "debug leaks",
            "debug keychain",
            "debug defaults",
            "debug flags",
            "debug trace",
            "debug trace summary",
            "debug trace diff",
            "debug trace explore",
            "debug trace cleanup",
            "debug scroll",
            "skills",
            "skills install",
        ]

        for command in publicCommands {
            #expect(LoupeCLI.commandUsage(command) != nil)
        }
    }

    @Test func debugLogsHelpMentionsNoImportNotificationBridge() throws {
        let help = try #require(LoupeCLI.commandUsage("debug logs"))

        #expect(help.contains("dev.loupe.log"))
        #expect(help.contains("NotificationCenter"))
    }

    @Test func actionTargetHelpQuotesHashAlias() throws {
        let act = try #require(LoupeCLI.commandUsage("act"))
        let targets = try #require(LoupeCLI.commandUsage("act targets"))
        let tap = try #require(LoupeCLI.commandUsage("act tap"))

        #expect(act.contains("targets"))
        #expect(targets.contains("loupe act targets"))
        #expect(tap.contains("loupe act tap '#2'"))
        #expect(tap.contains("'#N'"))
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

    @Test func deprecatedMainBranchCommandsHaveHiddenReplacements() {
        let expected: [String: [String]] = [
            "start": ["app", "launch"],
            "launch": ["app", "launch"],
            "fetch": ["ui", "snapshot"],
            "capture-report": ["ui", "report"],
            "compact": ["ui", "compact"],
            "screen-map": ["ui", "screen"],
            "tree": ["ui", "tree"],
            "inspect": ["ui", "node"],
            "query": ["ui", "query"],
            "logs": ["debug", "logs"],
            "trace-summary": ["debug", "trace", "summary"],
            "tap": ["act", "tap"],
            "set": ["ui", "set"],
            "set-many": ["ui", "set-many"],
            "wait-for-visible": ["act", "wait"],
        ]

        for (command, replacement) in expected {
            #expect(LoupeCLI.deprecatedCommandReplacement(command) == replacement)
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
