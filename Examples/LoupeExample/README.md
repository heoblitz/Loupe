# LoupeExample

UIKit app used to verify simulator dylib injection and Loupe-driven coordinate
actions.

The app does not link `LoupeKit`. It only defines normal UIKit views and
`accessibilityIdentifier` values. `LoupeInjector` is injected at launch time and
starts the localhost observation server.

The app includes `LaunchScreen.storyboard` so the simulator does not fall back
to the legacy 320x480 compatibility viewport.

The app intentionally includes more than a single button:

- navigation controller
- large table view with many cells
- detail screen
- pan gesture target
- UIKit component screen with labels, image views, switches, sliders, steppers,
  segmented controls, date pickers, page controls, progress/activity views,
  text input, buttons, bar buttons, scroll views, collection views, picker
  views, tab bars, alerts, and design fixtures
- mixed fixture tab controller with SwiftUI host, WebKit, keyboard-heavy form,
  nested scroll views, and selector-addressable tab items
- modal form with text input

Run:

```bash
./run-injected.sh
```

Expected result:

- the app launches on a booted simulator
- the script prints the randomized Loupe runtime health response
- `/snapshot` contains the UIKit view hierarchy
- `loupe ui query ... --test-id example.customerList` returns the table node

Run the XCTest-free Loupe runtime smoke harness:

```bash
./run-runtime-e2e.sh
```

This launches the injected app, verifies richer UIKit/accessibility snapshot
fields, performs a drag through the public Loupe action surface, and captures a
screenshot.

Run the native HID scenario harness:

```bash
./run-native-scenarios.sh
```

This repeats routed navigation fixtures, gesture pop, synthetic `UIBarButtonItem`
selector node inspection, `act wait visible`, bounded `subtree`, accessibility
tree export/query, compact UIKit class identity, full component-specific
properties, mixed fixture tabs, text input, WebKit inspection, nested scroll
inspection, and the layout audit output path.

Run the UIKit and SwiftUI touch/input regression harness:

```bash
./run-touch-e2e.sh
```

The `touch` route is UIKit. It opens the separate `touch.swiftui` screen through
the public CLI, then the harness also launches SwiftUI in a fresh process.
Assertions inspect application counters, input values and editing notifications,
double taps, ordinary and held drags, and scroll offsets. Non-accessibility
double-tap and pan views must appear as meaningful targets while status labels
and recognizers without enabled handlers are excluded. The simulator temporarily enables
Korean and restores the affected keyboard/language preferences afterward,
restarting the simulator only when those preferences change. There is no XCTest runner.

To run the same assertions against a signed Debug app linked with LoupeInjector,
launch it on a physical device with `LOUPE_EXAMPLE_ROUTE=touch`, then pass its
host. The device must have Korean enabled for the keyboard regression:

```bash
LOUPE_TOUCH_HOST='http://[device-tunnel-ip]:port' ./run-touch-e2e.sh
```

For a fresh `touch.swiftui` device launch, use `LOUPE_TOUCH_MODE=--swiftui-only`.
The script does not install, sign, or relaunch an externally supplied device app.

Run the bookmark app-style E2E harness:

```bash
./run-bookmark-e2e.sh
```

This launches the bookmark route, verifies the tab bar plus list observation,
prints view/accessibility tree previews, blocks text-based tap, captures an
automatic failure trace, opens detail by `testID`, checks and toggles favorite
state with `loupe act wait value`, returns by `ref`, types into the add form, saves a
new bookmark, waits for the editor to disappear, switches to Favorites, opens
another detail screen, switches to Search, types a query, and audits the
resulting view tree.

Run the legacy Loupe-driven coordinate action proof:

```bash
./run-loupe-driven-ui-test.sh
```

This launches the app with injection, fetches Loupe snapshots from the UI test,
resolves nodes by `testID`, and uses `XCUICoordinate` to scroll, tap, and drag.
