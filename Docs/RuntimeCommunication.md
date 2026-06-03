# Runtime Communication

Loupe starts `LoupeServer` inside the app process, either through simulator
injection or by linking `LoupeKit`, and binds HTTP to `127.0.0.1`. The CLI talks
to that local server with `--host`; it uses `--udid` only to validate that the
contacted server belongs to the expected simulator when the runtime is simulator
backed.

The SDK default port is `8765` when an app starts LoupeKit directly. Treat that
as an SDK fallback, not as a CLI workflow assumption. The CLI launch path is
stricter: when `loupe app launch` is used without `LOUPE_PORT`, it assigns an
available localhost port, stores the UDID+bundle
mapping under `~/.loupe/runtimes`, and waits for `/runtime` before returning.
Later commands can pass `--udid` or `--bundle-id` and omit `--host`.

For fixed-port workflows, use `loupe app launch --port <port>` or launch with
`--env LOUPE_PORT=<port>`. If that port is already serving a Loupe runtime for
another simulator or app, launch fails with a port collision error instead of
silently talking to the wrong runtime.

HTTPS is not required for this path. Loupe is not making the app call an
external service; the host CLI is calling the app's loopback server inside the
same machine's app runtime. The server binds only to localhost.

## App To Loupe

When an app links `LoupeKit`, it can call the Swift APIs directly. When Loupe is
injected and the app does not import `LoupeKit`, app code can still send logs and
view metadata through `NotificationCenter` string names.

Injected runtimes install the notification bridge before the localhost server is
started, so app lifecycle logs posted during the first visible screen can be read
through `/logs` or `loupe debug logs`.

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

Fetch the collected runtime logs from the host:

```bash
loupe debug logs --bundle-id com.example.App --output /tmp/loupe-logs.json
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
implementation views.
