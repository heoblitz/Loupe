extension LoupeCLI {
    static let appUsage = """
    Usage: loupe app <subcommand>

    SUBCOMMANDS:
      launch                  Launch and inject an app runtime.
      list                    List known app runtimes.
      use                     Select the current app runtime.
      current                 Show the current app runtime.
      info                    Fetch runtime identity and health.
      cleanup                 Prune stale app runtime records.
    """

    static let uiUsage = """
    Usage: loupe ui <subcommand>

    SUBCOMMANDS:
      report                  Capture screenshot and runtime structure artifacts.
      snapshot                Fetch the current full UI snapshot.
      compact                 Fetch or build compact UI context for agents.
      tree                    Print view or accessibility trees.
      screen                  Print visible semantic and styled elements.
      accessibility           Export an accessibility tree.
      screenshot              Save a platform screenshot to a path.
      node                    Inspect one matched node with local context.
      query                   Query by selector.
      subtree                 Print a bounded subtree around a matched node.
      paint                   Inspect paint stack ordering.
      audit                   Audit layout, contrast, and target sizing.
      constraints             Inspect captured layout constraints.
      hit-test                Inspect the view intercepting a point.
      responder-chain         Inspect responders for a selector.
      appearance              Read or change appearance.
      mutations               List supported UI mutations.
      set                     Mutate one supported UI property.
      set-many                Mutate matching UI properties in a batch.
      set-constraint          Mutate a captured constraint.
      deactivate-constraint   Deactivate a captured constraint.
      reflect                 Reflect a mutation response into source.
      compare-design          Compare a snapshot with exported design data.
    """

    static let actUsage = """
    Usage: loupe act <subcommand>

    SUBCOMMANDS:
      tap                     Tap a selector, ref, or coordinate.
      swipe                   Dispatch a one-finger swipe.
      drag                    Dispatch a one-finger drag.
      type                    Type text into the focused field.
      press                   Press a simulator remote or keyboard button.
      wait                    Wait for visible, gone, or value state.
    """

    static func commandUsage(_ command: String) -> String? {
        switch command {
        case "app":
            return appUsage
        case "ui":
            return uiUsage
        case "act":
            return actUsage
        case "debug":
            return debugUsage
        case "app launch":
            return "Usage: loupe app launch --bundle-id <id> [--device <sim>|--udid <sim>] [--port <port>] [--env KEY=VALUE] [--timeout <seconds>]"
        case "app list":
            return "Usage: loupe app list [--json] [--timeout <seconds>]"
        case "app use":
            return "Usage: loupe app use <bundle-id> | --bundle-id <id> | --host <url> [--udid <sim>]"
        case "app current":
            return "Usage: loupe app current [--json] [--timeout <seconds>]"
        case "app info":
            return "Usage: loupe app info [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "app cleanup":
            return "Usage: loupe app cleanup [--dry-run] [--timeout <seconds>]"
        case "ui report":
            return "Usage: loupe ui report [--host <url>] [--udid <sim>] [--bundle-id <id>] --output <dir> [--screen-map-limit <n>] [--timeout <seconds>]"
        case "ui snapshot":
            return "Usage: loupe ui snapshot [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>] [--timeout <seconds>]"
        case "ui compact":
            return "Usage: loupe ui compact [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>] [--timeout <seconds>]"
        case "ui tree":
            return """
            Usage: loupe ui tree [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--view|--accessibility] [--depth <n>]
                   loupe ui tree --interesting|--visible-leaves|--text|--mutable

            Print a human-readable tree. Use --mutable to discover refs likely useful for runtime mutation.
            """
        case "ui text", "ui text-map":
            return "Usage: loupe ui text [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--accessibility]"
        case "ui screen", "ui screen-map":
            return "Usage: loupe ui screen [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--include-hidden] [--include-containers] [--limit <n>]"
        case "ui accessibility":
            return "Usage: loupe ui accessibility [snapshot.json] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "ui screenshot":
            return "Usage: loupe ui screenshot --udid <sim> --output <path> [--timeout <seconds>]"
        case "ui node":
            return "Usage: loupe ui node <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--include-hidden] [--fields node,parent,children,siblings]"
        case "ui query":
            return "Usage: loupe ui query [snapshot.json] (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--host <url>] [--bundle-id <id>] [--tree view|accessibility]"
        case "ui subtree":
            return "Usage: loupe ui subtree <snapshot.json> (--test-id <id> | --text <text> | --role <role> | --ref <ref>) [--depth <n>] [--include-hidden]"
        case "ui paint", "ui paint-stack":
            return "Usage: loupe ui paint [snapshot.json] (--point x,y | --ref <ref>) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--limit <n>] [--json]"
        case "ui audit":
            return AuditOptions.usage
        case "ui constraints":
            return ConstraintListOptions.usage
        case "ui hit-test":
            return "Usage: loupe ui hit-test --point x,y [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "ui responder-chain":
            return "Usage: loupe ui responder-chain (--test-id <id> | --ref <ref> | --text <text> | --role <role>) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "ui appearance":
            return "Usage: loupe ui appearance [light|dark|system] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "ui mutations":
            return "Usage: loupe ui mutations [--host <url>] [--udid <sim>] [--bundle-id <id>]"
        case "ui set":
            return MutationSetOptions.usage
        case "ui set-many":
            return BatchMutationOptions.usage
        case "ui set-constraint":
            return ConstraintMutationOptions.usage(deactivate: false)
        case "ui deactivate-constraint":
            return ConstraintMutationOptions.usage(deactivate: true)
        case "ui reflect":
            return "Usage: loupe ui reflect <mutation-response.json> --source <dir> [--output <path>]"
        case "ui compare-design":
            return "Usage: loupe ui compare-design <snapshot.json> <design.json> [--json] [--limit <n>]"
        case "act tap":
            return "Usage: loupe act tap (--test-id <id> | --ref <ref> | --x <n> --y <n>) --udid <sim> [--host <url>] [--snapshot <snapshot.json>] [--trace-dir <path>] [--expect-visible <testID>]"
        case "act swipe":
            return "Usage: loupe act swipe --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--no-verify-scroll] [--trace-dir <path>]"
        case "act drag":
            return "Usage: loupe act drag --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--trace-dir <path>]"
        case "act type":
            return "Usage: loupe act type <text> --udid <sim> [--host <url>] [--trace-dir <path>]"
        case "act press":
            return "Usage: loupe act press up|down|left|right|select|menu|playPause --udid <sim> [--host <url>] [--trace-dir <path>] [--expect-visible <testID>]"
        case "act wait":
            return "Usage: loupe act wait visible|gone|value <selector> [--host <url>] [--udid <sim>] [--bundle-id <id>] [--timeout <seconds>]"
        case "debug logs":
            return "Usage: loupe debug logs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "debug network":
            return "Usage: loupe debug network [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "debug refs":
            return "Usage: loupe debug refs [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "debug object-graph":
            return "Usage: loupe debug object-graph [target|--target <name>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "debug heap":
            return "Usage: loupe debug heap [target|--target <name>] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "debug keychain":
            return "Usage: loupe debug keychain [list] [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]"
        case "debug defaults":
            return "Usage: loupe debug defaults get|set|unset <key> [value] [--bool true|false] [--number n] [--host <url>] [--output <path>]"
        case "debug flags":
            return "Usage: loupe debug flags get|set|unset <key> [value] [--bool true|false] [--number n] [--host <url>] [--output <path>]"
        case "debug trace":
            return "Usage: loupe debug trace summary|diff|explore|cleanup <args>"
        case "debug trace summary":
            return "Usage: loupe debug trace summary <trace-dir> [--json] [--limit <n>]"
        case "debug trace diff":
            return "Usage: loupe debug trace diff <before-snapshot.json> <after-snapshot.json> [--json] [--changed-only] [--limit <n>]"
        case "debug trace explore":
            return "Usage: loupe debug trace explore [--host <url>] [--udid <sim>] [--bundle-id <id>] [--limit <n>] [--settle <seconds>] [--back-point x,y] [--trace-dir <dir>] [--output <path>] [--json]"
        case "debug trace cleanup":
            return "Usage: loupe debug trace cleanup [--dry-run] [--traces-older-than <duration>|--all-traces]"
        case "debug scroll":
            return """
            Usage: loupe debug scroll --from x,y --to x,y --udid <sim> [--host <url>] [--duration <seconds>] [--trace-dir <path>] [--output <path>]
                   loupe debug scroll (--test-id <id>|--ref <ref>|--text <text>|--role <role>) (--delta dx,dy|--to-offset x,y) [--host <url>] [--udid <sim>] [--bundle-id <id>] [--output <path>]
            """
        case "version", "--version":
            return "Usage: loupe version\n       loupe --version"
        case "doctor":
            return "Usage: loupe doctor"
        case "injector-path":
            return "Usage: loupe injector-path"
        default:
            return nil
        }
    }
}
