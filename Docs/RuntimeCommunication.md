# Runtime Communication

Loupe injection starts `LoupeServer` inside the simulator app process and binds
HTTP to `127.0.0.1`. The CLI talks to that local server with `--host`; it uses
`--udid` only to validate that the contacted server belongs to the expected
simulator.

The SDK default port is `8765`. The CLI launch path is stricter: when
`loupe start` or `loupe launch --inject` is used without `LOUPE_PORT`, it assigns a stable
per-simulator localhost port, stores the mapping under `~/.loupe/runtimes`, and
waits for `/runtime` before returning. Later commands can pass `--udid` and omit
`--host`.

For fixed-port workflows, prefer `loupe start --port <port>` or launch with
`--env LOUPE_PORT=<port>`. If that port is already serving a Loupe runtime for
another simulator, launch fails with a port collision error instead of silently
talking to the wrong app.

HTTPS is not required for this path. Loupe is not making the app call an
external service; the host CLI is calling the app's loopback server inside the
iOS Simulator. The server binds only to localhost.

## App To Loupe

When an app links `LoupeKit`, it can call the Swift APIs directly. When Loupe is
injected and the app does not import `LoupeKit`, app code can still send logs and
view metadata through `NotificationCenter` string names.

```swift
NotificationCenter.default.post(
    name: Notification.Name("dev.loupe.log"),
    object: nil,
    userInfo: [
        "level": "info",
        "message": "checkout_visible",
        "metadata": ["cartID": "cart-123", "itemCount": 3]
    ]
)
```

Attach metadata to a concrete UIKit view:

```swift
NotificationCenter.default.post(
    name: Notification.Name("dev.loupe.viewMetadata"),
    object: payButton,
    userInfo: [
        "metadata": ["screen": "checkout", "variant": "primary"]
    ]
)
```

Attach metadata by stable test id when the view object is inconvenient:

```swift
NotificationCenter.default.post(
    name: Notification.Name("dev.loupe.viewMetadata"),
    object: nil,
    userInfo: [
        "testID": "checkout.payButton",
        "metadata": ["screen": "checkout", "variant": "primary"]
    ]
)
```

Metadata values are intentionally scalar: `String`, `Bool`, `Int`, `Double`, and
`Float`/`NSNumber` values that map to those types.

## SwiftUI Boundary

Loupe does not synthesize a SwiftUI view tree. SwiftUI elements are valid
movement/input targets only when they are exposed through the accessibility tree.
If a SwiftUI `.accessibilityIdentifier(...)` is not visible through the runtime
accessibility tree, Loupe will not invent a selector for it from private SwiftUI
implementation views. Recording follows the same rule: SwiftUI-backed view-tree
nodes are skipped as replay selector candidates, while accessibility nodes remain
eligible.
