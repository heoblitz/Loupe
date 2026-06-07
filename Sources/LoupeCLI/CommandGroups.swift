import Foundation
import LoupeCLIModel

extension LoupeCLI {
    static func helpPath(command: String, arguments: [String]) -> [String] {
        guard isCommandGroup(command),
              let subcommand = arguments.first,
              !subcommand.hasPrefix("-") else {
            return [command]
        }
        if command == "debug",
           subcommand == "trace",
           arguments.count > 1,
           !arguments[1].hasPrefix("-") {
            return [command, subcommand, arguments[1]]
        }
        return [command, subcommand]
    }

    static func isCommandGroup(_ command: String) -> Bool {
        ["app", "ui", "act", "debug", "skills"].contains(command)
    }

    static func app(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError(appUsage)
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "launch":
            try await start(rest)
        case "list":
            try await runtimes(rest)
        case "use":
            try await use(rest)
        case "current":
            try await current(rest)
        case "info":
            try await runtimeFetch(
                rest,
                path: "/runtime",
                usage: "loupe app info [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
        case "cleanup":
            let cleanupArgs = rest.contains("--no-traces") ? rest : rest + ["--no-traces"]
            try await cleanup(cleanupArgs)
        default:
            throw CLIError("Unknown app command: \(subcommand)")
        }
    }

    static func ui(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError(uiUsage)
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "report":
            try await captureReport(rest)
        case "snapshot":
            try await runtimeFetch(
                rest,
                path: "/snapshot",
                usage: "loupe ui snapshot [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
            )
        case "compact":
            if let first = rest.first, !first.hasPrefix("-") {
                try compact(rest)
            } else {
                try await runtimeFetch(
                    rest,
                    path: "/observation",
                    usage: "loupe ui compact [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
                )
            }
        case "tree":
            try await tree(rest)
        case "text", "text-map":
            try await tree(rest + ["--text"])
        case "screen", "screen-map":
            try await screenMap(rest)
        case "accessibility":
            if let first = rest.first, !first.hasPrefix("-") {
                try accessibility(rest)
            } else {
                try await runtimeFetch(
                    rest,
                    path: "/accessibility",
                    usage: "loupe ui accessibility [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--include-hidden] [--output <path>]"
                )
            }
        case "screenshot":
            try screenshot(rest)
        case "node":
            try inspect(rest)
        case "query":
            try await query(rest)
        case "subtree":
            try subtree(rest)
        case "paint", "paint-stack":
            try await paintStack(rest)
        case "audit":
            try audit(rest)
        case "mutations":
            try await mutations(rest)
        case "set":
            try await set(rest)
        case "set-many":
            try await setMany(rest)
        case "constraints":
            try await constraints(rest)
        case "set-constraint":
            try await mutateConstraint(rest, deactivate: false)
        case "deactivate-constraint":
            try await mutateConstraint(rest, deactivate: true)
        case "reflect":
            try reflect(rest)
        case "compare-design":
            try compareDesign(rest)
        case "apply-design-suggestions":
            try await applyDesignSuggestions(rest)
        case "hit-test":
            try await hitTest(rest)
        case "responder-chain":
            try await responderChain(rest)
        case "appearance":
            try await env(["appearance"] + rest)
        default:
            throw CLIError("Unknown ui command: \(subcommand)")
        }
    }

    static func act(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError(actUsage)
        }
        let rest = Array(arguments.dropFirst())
        switch subcommand {
        case "tap", "swipe", "drag", "type", "press":
            try await action(command: subcommand, arguments: rest)
        case "wait":
            try await wait(rest)
        default:
            throw CLIError("Unknown act command: \(subcommand)")
        }
    }

    static func wait(_ arguments: [String]) async throws {
        guard let mode = arguments.first else {
            throw CLIError("Usage: loupe act wait visible|gone|value (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--timeout <seconds>]")
        }
        let rest = Array(arguments.dropFirst())
        switch mode {
        case "visible":
            try await waitFor(rest, mode: .visible)
        case "gone":
            try await waitFor(rest, mode: .gone)
        case "value":
            try await waitFor(rest, mode: .value)
        default:
            throw CLIError("Unknown wait mode: \(mode)")
        }
    }
}
