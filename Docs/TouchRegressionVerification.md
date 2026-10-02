# Touch and input regression verification

## Architecture review: 2026-10-02

The release gate is **0/3 complete CI cycles**. PR #22 remains open. Product
edits and CI reruns paused for the upstream review before the corrections below;
an earlier 14-job cycle passed,
but the next cycle failed before input during screenshot capture and simulator
boot-status monitoring. A successful transport acknowledgement or a prior-source
pass does not establish that the final release is ready.

### Alternatives reviewed from pinned upstream sources

Target discovery, input delivery, and observing the result are separate
capabilities. A tool that can tap a coordinate does not necessarily discover
non-accessibility gesture targets or determine that the app handled the tap.

| Approach and upstream source | Discovery and delivery | Fit and limits for Loupe |
| --- | --- | --- |
| [Necto control runtime](https://github.com/toss/necto/blob/b5227f798b525c4e26949ce80bda638901e948b9/Sources/NectoDefaultPlugins/NectoControlRuntime.swift), [touch injector](https://github.com/toss/necto/blob/b5227f798b525c4e26949ce80bda638901e948b9/Sources/NectoTouchInjection/TouchInjector.m) | SDK walks public accessibility containers and native view gaps; clips frames, hit-tests and revalidates target identity, frame and label before input. In-app UITouch/IOHID sequences support UIKit and SwiftUI responder routing. Text uses UITextInput/UIKeyInput. | Strong reference for physical Debug input and stale-target rejection. Ordinary gesture views must be accessibility elements to become targets; scroll views are suggested without checking overflow. These policies do not meet Loupe's non-accessibility/no-noise discovery requirement by themselves. Routing both runtimes through the SDK would change the project's host-input architecture. |
| [idb connection](https://github.com/facebook/idb/blob/6c86cfcccf5e65ea7a8da73bb765a58af6a38851/FBSimulatorControl/HID/SimulatorSharedConnection.swift), [framebuffer](https://github.com/facebook/idb/blob/6c86cfcccf5e65ea7a8da73bb765a58af6a38851/FBSimulatorControl/Framebuffer/FramebufferSurface.swift), [boot verification](https://github.com/facebook/idb/blob/6c86cfcccf5e65ea7a8da73bb765a58af6a38851/FBSimulatorControl/Strategies/SimulatorBootVerification.swift) | Reuses native CoreSimulator connections; acknowledged HID delivery, direct IOSurface screenshots and native boot-status observation. Input operations own their contacts and cleanup. | Closest simulator architecture. Avoids a new simctl lifecycle for every screenshot. Booted state alone is insufficient; successful boot completion must be distinguished from migration failure. Private proxy calls need exception guards and bounded ownership. Full idb adoption adds substantially more framework and packaging scope than a narrow adapter. |
| [AXe HID broker](https://github.com/cameroncooke/AXe/blob/30f4bfa9bc81817906a60fadedbc913d7314b7e1/Sources/AXe/Utilities/HIDBroker%2BConnection.swift), [interactor](https://github.com/cameroncooke/AXe/blob/30f4bfa9bc81817906a60fadedbc913d7314b7e1/Sources/AXe/Utilities/HIDInteractor.swift) | idb-backed simulator HID with a persistent broker, readiness handshake and boot identity. Contacts are released after a partial gesture failure. | An alternative to reopening connections across CLI processes. Broker replacement is safe only before input; a missing response after dispatch cannot justify replay. Adds a daemon, socket ownership, startup and shutdown contracts. Consider only if a smaller native adapter still cannot meet the existing limits. |
| [WDA gesture synthesizer](https://github.com/appium/WebDriverAgent/blob/9d1d17ddb59e6097ddc3324b23ca9f4174507b12/WebDriverAgentLib/Utilities/FBW3CActionsSynthesizer.m), [Maestro touch handler](https://github.com/mobile-dev-inc/Maestro/blob/51538ec1d3bb0c5eb84f29fee1687d0ccd2817c7/maestro-ios-xctest-runner/maestro-driver-iosUITests/Routes/Handlers/TouchRouteHandler.swift) | XCTest/XCUI accessibility snapshots and synthesized pointer paths; coordinates can address views not represented in the accessibility hierarchy. | Separate signed test-runner/server architecture with system-level automation. It does not discover every non-AX handler. Replacing Loupe's public harness would conflict with its XCTest-free architecture rule. Maestro's optional retry-if-no-change policy must not be copied: unchanged content is not proof that an input was not delivered. |
| [KIF touch setup](https://github.com/kif-framework/KIF/blob/151cf7172f7afc795214b6def533b2d2d11b4e83/Sources/KIF/Additions/UITouch-KIFAdditions.m), [EarlGrey touch injector](https://github.com/google/EarlGrey/blob/aea2d32233dc2cd2eff7906426944c8f287c0855/EarlGrey/Event/GREYTouchInjector.m) | In-app touch lifetime, first-touch initialization, event phases and main-thread delivery; KIF handles iOS 18 SwiftUI hit-test responders. EarlGrey schedules bounded gesture phases rather than invoking a button callback. | Useful physical-input implementation references. EarlGrey's reviewed master revision is from 2023; it is a historical design reference, not evidence of iOS 26 compatibility. Neither project's successful tests substitute for Loupe's actual app-state assertions. |
| [pymobiledevice3 CoreDevice HID](https://github.com/doronz88/pymobiledevice3/blob/cd895d17ce8a97d883c10f87b26c7356d5e0ccb1/pymobiledevice3/remote/core_device/hid_service.py), [idb DTUHID connection](https://github.com/facebook/idb/blob/6c86cfcccf5e65ea7a8da73bb765a58af6a38851/FBSimulatorControl/HID/SimulatorDTUHIDConnection.swift) | Newer host-to-device/service HID paths, including physical touchscreen reports. The physical path requires an authenticated media-stream session; the simulator path proves daemon liveness before input. | A materially different physical-input alternative, potentially removing in-app synthetic touches. Device/OS/authentication, orientation, contact cleanup and app-state proof remain unverified here. A service port or accepted packet does not establish working touch delivery. Do not silently select it in this release. |
| [SimPilot desktop HID](https://github.com/ygrec-app/SimPilot/blob/995f6ae1558925dd107c56a1813e98ee833917d3/Sources/SimPilotCore/Drivers/HID/HIDDriver.swift) | Converts device coordinates to the visible Simulator window and posts macOS CGEvent mouse/keyboard events. | Requires window placement, visibility and desktop accessibility permission; unsuitable for the headless CI and physical-device requirements. |
| [ViewInspector gesture inspection](https://github.com/nalexn/ViewInspector/blob/2dacb6e514be19379c605a5a11564d0f3fea89d9/Sources/ViewInspector/SwiftUI/Gesture.swift) | Inspects SwiftUI gesture wrappers and invokes stored updating/changed/ended closures. | Useful for declaration structure and unit tests. Closure invocation bypasses hit testing and touch recognition, so it cannot verify tap, double tap or held drag. |
| Accessibility activation, control callbacks, OCR/visual coordinates | Activation/callbacks run declared semantic actions; visual approaches choose a screen location. | Keep accessibility activation under `act perform`. It cannot replace real `act tap`/`drag`. Pixels alone cannot establish an enabled handler, so visual guesses must not be published as proven actionable targets. Explicit coordinates remain available. |

### Evidence and selected implementation

The second paired CI attempt on `5384d16` had three confirmed failures:

- Native iOS job `110649355919`: the complete mixed-screen suite passed, but
  the first cold SwiftUI action's before screenshot produced no PNG within
  10 seconds. No touch was enqueued. Runtime snapshots continued to work.
- ARM bottle job `110652277619`: `simctl bootstatus` produced no output and
  exceeded the unchanged 180-second limit while guest startup processes existed.
  Process presence does not prove that boot finished.
- Intel bottle job `110652277603`: bootstatus printed `Status=4294967295`,
  `isTerminal=YES` and `Finished`, but its process did not exit before the
  180-second limit. Successful guest boot and host process teardown diverged.

A repository-independent read-only probe used the idb-style main-display
IOSurface lookup on Loupe-owned iOS 26.3 and 18.6 ARM simulators. It produced
decodable 1206×2622 PNGs in 1.466 and 0.263 seconds, respectively. Both images
were visually inspected. This establishes a viable local capture alternative;
it does **not** establish Intel, cold CI, rotation or timeout safety.

The selected adapter now reads the unique primary CoreSimulator display's
IOSurface through the same device connection used by host HID. It encodes PNG
bytes inside a bounded worker; only the waiting caller can publish a validated
complete image. A late native completion cannot replace evidence after timeout.
Unsupported framebuffer APIs alone fall back to simctl within the remaining
original 10-second budget; native errors do not trigger another capture or input.
The iOS 18.6 rotated-screen image was visually compared with simctl's default
raw framebuffer output: dimensions and direction agree. This preserves that
existing output convention rather than adding a new upright-image contract.
Observation loads CoreSimulator alone. SimulatorKit is loaded only when host
HID input is needed; screenshots and boot observation must not initialize that
input framework. Opt-in phase diagnostics distinguish the two framework loads.
An actual fresh-process PNG capture with dyld library diagnostics confirmed
that SimulatorKit was absent locally.

CI observes native boot status for its exact owned UUID. Success requires both
Booted device state and Finished boot status; terminal migration failure is
rejected. The observer emits fresh timestamped JSON over its stdout pipe,
allowing its parent to accept semantic completion and reap only its child even
if host teardown stalls. The parent persists the last record for diagnostics
after completion detection; filesystem publication never gates readiness.
The 180-second readiness deadline remains unchanged. The host helper is compiled
on the idle host before the first simulator service request, so its build does
not compete with guest first-boot migration. Build diagnostics and elapsed time
are retained separately. The helper observes only; bottled CLI and injector
artifacts are never rebuilt.

Local verification passed 367 Swift tests and fourteen readiness contracts,
including late frame completion, malformed PNG preservation, ignored termination,
wrong-device receipts, migration failure and build-before-service ordering.
Owned iOS 18.6 and 26.3 simulators
passed native completion observation after reboot and full/cold UIKit/SwiftUI
gesture and Unicode input suites. Release CLI, CLI contracts, available platform
builds and macOS E2E passed. The required local harness stops at the unavailable
Apple TV runtime. Intel and cold hosted CI remain release gates. The first
native-observer CI source failed before observation because its helper's
post-boot compilation exceeded 60 seconds; capture and input did not run. The
helper build was moved before boot without extending the 60-second build or
180-second boot limits.
On the next source, Verify passed 9/9 and both architecture bottles built and
poured successfully. The actual Intel bottle passed full/cold touch suites.
The ARM bottle failed at its first screenshot before input: combined framework
initialization took 8.3 seconds of the unchanged 10-second deadline, and service
connection resolution did not finish in the remainder. Removing the unnecessary
input-framework load from observation is the selected correction; the separate
framework timings will expose any remaining CoreSimulator startup stall.

That source passed two consecutive complete 14-job cycles. In its third cycle,
Verify passed 9/9 and the actual ARM bottle passed full/cold touch suites, but
Intel preparation timed out before input. Its fresh receipt contained Finished
and Booted. The receipt had no completion timestamp, so the failure evidence
cannot distinguish a late boot from a parent that resumed after its deadline.
A deterministic regression reproduced the latter: the observer completed in
19ms, but a delayed parent resumed at 413ms and rejected it under a 200ms limit.

Native receipts now record the shared Mach monotonic clock, and the parent logs
its original start/deadline on that same clock. This also avoids process-local
monotonic epochs in older Xcode Python versions. A delayed parent reads the
receipt once and accepts only a native completion observed within the original
budget. Genuinely late completion, missing timestamps and receipts predating
the launch remain failures. Four regression contracts exercise these cases.
The 180-second budget is unchanged; the final source still requires a fresh
three-cycle gate. No failed job is rerun to recover a cycle.

The Intel26 source subsequently reached native Finished+Booted at 162.007s
within that original budget. However, its atomic receipt remained at status4,
and the failure artifact contained an empty Foundation replacement temporary
file. The native completion was observed but its file publication did not
complete before the parent's timeout. The final observer therefore emits each
complete JSON record directly to the parent over a nonblocking pipe. The parent
drains queued records before checking its wakeup time, validates the native
timestamp and exact UUID, and saves the last record only as diagnostic evidence.
It rejects malformed/truncated records, unsuccessful observer exits and genuine
late completion. Fourteen contracts and an actual CoreSimulator C/Python pipe
observation passed locally. No readiness limit, runtime assertion or SDK source
was changed for this correction.

The timestamped source passed Verify 9/9 and ARM full/cold bottle tests, but
Intel iOS18 preparation remained incomplete within its actual 180-second
budget: native status 2 was observed at 55.427s and status 4 at 150.438s,
without a Finished receipt. This is a real readiness failure, not a timely
completion rejected by a delayed parent. It does not establish a touch or
CLI failure because input never started.

The Intel runtime matrix now uses the current native `macos-26-intel` host,
Xcode 26.2 and its preinstalled iOS26.2 iPhone17Pro fixture, matching the ARM
runtime toolchain without changing architecture. The [official image inventory
at reviewed revision 57b93f2](https://github.com/actions/runner-images/blob/57b93f2cf7eda14a6a71f3175d15218626cdbd4c/images/macos/macos-26-Readme.md)
lists that Xcode and fixture; the [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
supports this standard Intel label. Both bottle builds/pours remain on macOS15
to retain the package compatibility floor. Both actual runtime jobs still use
the downloaded immutable bottles without rebuilding their CLI or SDK. Local
iOS18 coverage remains in the regression evidence; the legacy Intel hosted
combination is not silently counted as passed. The new matrix must pass the
same three consecutive complete 14-job cycles and unchanged readiness limits.

Source `b4b3113` passed all nine Verify jobs and both native bottle builds/pours,
but neither bottled runtime passed. The Intel native pipe reported status4
(WaitingOnSystemApp) at 165.055s and never observed Finished within 180s.
This is still a real readiness failure; the pipe correction does not establish
that the guest finished booting. On a future failure, bounded host process,
memory and exact-device guest-service logs are retained after the unchanged
deadline, so the missing guest readiness can be investigated directly.

The ARM first input did not dispatch: its preparation loaded CoreSimulator,
then stopped in SimulatorKit loading at QoS25 until the original action bound.
Preparation now uses the same QoS33 serial input worker as gesture delivery.
The test checks actual preparation and gesture QoS alongside app state. A
standalone diagnostic also caught a main-thread nested `dispatch_async_and_wait`
crash in SimulatorKit's ROCKit proxy; the same call passed before this change,
and a genuine background caller passed. Enqueuing work asynchronously and
waiting for its completion keeps both preparation and gestures on an actual
interactive worker. The formerly crashing call and an actual QoS9 caller then
initialized successfully at preparation QoS33. With this final worker, all
367 Swift tests and 14 readiness contracts passed, together with full and
fresh SwiftUI-only CLI suites on iOS18.6 and iOS26.3.1. The local required
harness still stops at the missing Apple TV simulator after its available
checks pass. This local evidence does not count as a successful hosted CI cycle.

The follow-up source `bfe942f` passed Verify9/9 and the actual ARM bottle's
full/fresh SwiftUI suites. Intel still failed before input: its last native
record was WaitingOnDataMigration at 87.243s; Finished was not observed within
180s. Both the host process query and the exact-device guest-service query
then exceeded their bounded five-second diagnostic budgets. This evidence
does not establish the cause of the remaining Intel startup stall.

The [official runner-image cache correction](https://github.com/actions/runner-images/pull/13149)
cites Apple's first-boot workaround and prepares dyld caches using the image's
latest stable Xcode. CI now explicitly prepares only its selected runtime with
its pinned Xcode before boot, using `simctl runtime dyld_shared_cache update`
and the existing 60-second command bound. It uses no force or cache removal,
and records the cache output and elapsed preparation time separately. An
already usable local iOS26 cache returned successfully in 35ms. Whether this
preflight resolves hosted Intel startup remains unverified. Guest readiness
still requires native Finished+Booted within 180s, followed by every original
gesture/state assertion and three complete consecutive final-source CI cycles.

The first current-matrix source exposed an independent SwiftPM fixture race:
the slowloris test opened sixteen partial connections, slept for 800ms from
client time, then received `server_busy` from its health request. TCP connect
does not establish when the server accepted each connection, and fixed sleep
does not establish that its cleanup completed. The test now requires each
client's complete `request_timeout` response and connection closure before making
one health request. Closure can be EOF or `ECONNRESET`: a deadline that expires
before a queued worker reads the pending request bytes produces a Darwin TCP
reset. A loopback reproduction received the exact complete timeout response
followed by errno54. The test still rejects a truncated response or receive
timeout. The server releases admission capacity before closing the socket, so
observing that closure also establishes that its slot has been freed.
The fixture configures its two-second receive bound before `connect`: setting
`SO_RCVTIMEO` after the peer has reset is rejected by Darwin with `EINVAL`, as
confirmed by a second loopback reproduction. No socket setup depends on waiting
until the sixteen deadlines have already expired.
Its existing two-second client receive bound and the server's 250ms acceptance
deadline are unchanged. This strengthens the expiry assertion without allowing
a busy response or polling/retrying health. The only production transport change
is ordering admission cleanup before the existing socket close.

The native Intel26 probe ended while still in `Set up Homebrew`, before
simulator preparation or input. Its check record was cancelled; the final log
blob was not available when inspected, so no narrower failing subprocess is
claimed. The pinned setup action fetches Homebrew refs/tags and runs an explicit
update even though the image already provides Homebrew. Runtime jobs now use
the preinstalled version, assert native host architecture and disable automatic
update/API formula lookup. They register this checkout as a local tap and pour
the downloaded bottle. Build/pour jobs retain their existing setup. Actual
runtime, receipt, SDK reuse and three-cycle requirements are unchanged.

The current input transport, public CLI, strict before-capture failure and real
state assertions remain in place. A persistent broker or CoreDevice physical
transport remains a separate candidate if this smaller adapter cannot meet the
existing limits. No action is replayed after uncertain delivery.

Commit cleanup preserves the original 29-commit history in a backup branch and
Git bundle, plus a binary patch for the uncommitted changes. The final reviewed
source must receive three consecutive complete 14-job CI cycles after cleanup;
earlier source/attempt passes do not count. Current-SDK physical verification
also remains required before merge and release. The iPhone15 iOS26.2.1 run on
2026-10-02 passed both the full UIKit/SwiftUI suite and a fresh SwiftUI-only
process, with distinct runtime launch identities. It verified real counters,
offsets and bindings for non-accessibility gestures, taps/double taps, immediate
and held drag, Unicode input, aliases, coordinates and saved refs. After ordering
server admission cleanup before socket closure, the current SDK was rebuilt and
both physical suites passed again with fresh launch identities. The Darwin TCP
regression also verifies that a complete reset-close response passes while a
truncated response fails; receive and server deadlines remain unchanged.

The example has separate UIKit (`LOUPE_EXAMPLE_ROUTE=touch`) and SwiftUI
(`LOUPE_EXAMPLE_ROUTE=touch.swiftui`) screens. The UIKit screen opens SwiftUI
through a real navigation button. SwiftUI is also tested in a fresh process,
before any `act targets` call has initialized accessibility. These fixtures use
ordinary app controls and gesture recognizers, including double-tap and pan
surfaces hidden from accessibility. They contain no app-authored Loupe probes.

## Target discovery and dispatch

| Runtime / screen | Find the target | Deliver the touch |
| --- | --- | --- |
| iOS Simulator / UIKit | Accessibility match by testID or ref, using its activation point or frame center; fall back to the view frame when no match exists. Aliases use a fresh native action observation. | Host-side native HID down/move/up, acknowledged in order; UIKit hit testing delivers to the control or recognizer. |
| iOS Simulator / SwiftUI | The same selector/alias rules; Native accessibility remains preferred. Concrete SwiftUI gesture declarations supply additional targets; native frames or at least two agreeing geometry anchors establish coordinates. | The same host-side native HID; the simulator routes to SwiftUI's gesture recipient. |
| Physical iOS / UIKit | Native action observation first; full accessibility/view observation for gesture-only surfaces. | Debug runtime creates one UITouch with the first-touch-for-view flag, then delivers began/moved/ended through UIApplication. |
| Physical iOS / SwiftUI | Native accessibility locates controls; the same SwiftUI gesture-declaration and geometry checks discover gesture surfaces hidden from accessibility. | Debug runtime uses the SwiftUI-aware hit-test context to obtain the gesture recipient, then delivers the same UITouch phases. |

`act targets` combines declared accessibility actions with observed touch
contracts. UIKit captures wired controls, enabled single-finger recognizers with
real targets, and scroll views with overflow. SwiftUI captures concrete
`AddGestureModifier` nodes with callback/state-update wrappers, gesture counts
and masks rather than matching a parent type name. Handler-free gestures and
`allowsHitTesting(false)` surfaces are excluded. Disabled, hidden, occluded, handler-free and decorative UIKit
views are excluded. Touch capabilities are distinct from accessibility
callbacks: a `[double-tap]` target does not acquire an `act perform` action.

`loupe app launch` prepares `SWIFTUI_VIEW_DEBUG=27` before the app starts,
preserving an explicit caller value. This private Debug observation must be
available before SwiftUI initializes. Apps launched outside Loupe may need the
same launch environment. Unsupported declarations, missing geometry or
conflicting anchors are omitted; arbitrary drawing and multi-touch gestures
are not inferred.
Full snapshots prepare SwiftUI native accessibility before descending into
hosts. Touch discovery reads the hosting view's raw `_viewDebugData()` graph
and retains only the needed stored scalar fields of concrete modifiers, excluding
parent views whose generic type merely contains accessibility modifiers; it
avoids the full SwiftUI
`makeViewDebugData` serialization of retained UIKit representables. Nodes,
depth, child fields and shared attribute counts are bounded. The live graph uses
Swift node storage; it never boxes the entire hierarchy into JSON and parses it
again. Metatype names use the runtime's direct name lookup, avoiding printable
protocol-conformance searches performed by general string reflection.
Known scalar types are read directly; arbitrary Swift values are never cast
to `NSNumber` or `String`, avoiding user-defined Objective-C bridging during
observation. Boxed Foundation scalars are accepted only after class-type checks. Stored
debug collections use exact Swift metatypes, and field lookup stops at the first
match rather than conditionally bridging or visiting all remaining fields.
Private reflection prioritizes the user root, skips UIKit-owned internal hosts and has a shared
512-value budget, so branching graphs cannot expand without bound. CI samples the exact
fixture process and saves opt-in capture phase progress on failure without
replaying actions or increasing request deadlines. Phase diagnostics are
disabled in ordinary launches. Opt-in progress reuses one private file handle
instead of opening, seeking and closing the log at every field; it still writes
each phase immediately so a failure retains the latest completed work.
Only type, value, position and size are collected; unrelated display lists are
excluded. Extra native geometry traversal runs only when concrete gestures
require anchors, and hit testing skips views with no touch contract.

Native accessibility export collects view refs and visibility without repeating
the full style/layout/private-property capture already collected for traces.
Full view snapshots retain the complete inspection metadata.

Simulator inventory queries write subprocess output to a private temporary
file before parsing it. Waiting for termination with undrained stdout/stderr
pipes can block on large CI inventories; a large-output regression covers
this case without extending the existing deadline or changing device selection.

Explicit coordinates bypass selector discovery. No target is guessed from a
screenshot. A view absent from `act targets` can still be touched when its
testID/ref resolves to a usable frame, or when the caller supplies coordinates.
`act perform` retains declared accessibility-action semantics and does not retry
as a touch after failure. Ambiguous selectors fail instead of picking a match.

The first-touch and SwiftUI hit-test behavior is described in the primary
[KIF implementation](https://github.com/kif-framework/KIF/blob/master/Sources/KIF/Additions/UITouch-KIFAdditions.m).
Physical synthetic touch remains Debug-only. Simulator injectors provide the
same internal verification path in Debug and Release; public simulator actions
continue using host HID. Both architecture bottles are built and poured on
macOS 15 with its default toolchain, including real Intel Homebrew installation
and receipt checks. The ARM runtime job downloads and pours that exact bottle on
macOS 26, then runs iOS 26.2 / iPhone 17 Pro with Xcode 26.2. The Intel runtime
job pours the exact Intel bottle on a real Intel macOS 15 host, using an x86_64
iOS 18.6 / iPhone 16 Pro simulator with Xcode 16.4. Both runtime hosts require
Homebrew bottle receipts and run identical application-state assertions. The
selected fixture is prepared before `brew test` runs doctor. This preserves
the older build baseline and uses matching native
runtime toolchains rather than imposing iOS26/Rosetta startup on the Intel path.
Neither artifact is rebuilt by runtime jobs.
Each job owns a shutdown fixture from its disposable runner image and configures
English and Korean input before boot.
Publication requires both build/pour jobs and both runtime jobs to succeed.
HID uses the same resolved developer directory for SimulatorKit and its
CoreSimulator service context. Connection preparation finishes before trace
capture and fresh target observation without sending input; dispatch reuses the prepared client only
after target validation succeeds. Native and touch suites share their owned fixture,
avoiding factory data migration in a second simulator, prepare/restore reboots,
and `simctl spawn defaults` calls. One command starts the headless simulator;
the boot-status monitor observes that boot without starting the Simulator GUI.
After the fixture launches, setup waits for the real UIKit button to become
visible within the existing 15-second state-wait limit; server health alone
does not establish that the app's first scene is laid out. It then requires its rendered screenshot with the
CLI's same 10-second deadline, before any gesture. The input
preflight still checks the real active Korean input mode before any typing. The
simulator is removed after the job; ordinary local runs preserve and restore
their existing keyboard preferences.
Hosted CI reads the provisioned shutdown fixture's on-disk metadata to select
the exact iOS runtime and device type before starting CoreSimulator. It records
the claimed UUID, configures input offline, and makes the one-device boot the
first service request. It preserves the image's device name and verifies its
identity from the service-written device metadata after boot. Renaming
a booted fixture can block on startup services and adds no ownership evidence.
This removes the cold
all-runtime inventory from the startup path, including a post-boot `simctl list`
that can still stall while unrelated startup services are busy. Cleanup reads
only that UUID's small device metadata and validates the claimed
UUID and original name, with a hosted ownership marker that is accepted only
on disposable hosted runners. Local runs still
create a fresh fixture and never claim an existing user device. Query logs and
process metrics survive startup failure. The existing 60-second query and
180-second boot limits are unchanged. Native boot completion is recorded in a
fresh UUID-specific receipt; a stalled observer is terminated and collected by
its parent. Readiness contracts also run in the SwiftPM CI job.

Trace screenshots run alongside snapshot/accessibility collection, and target
crops use in-process ImageIO. Native framebuffer capture is the primary path;
missing private APIs use the bounded simctl fallback. Subprocess diagnostics go
to files rather than unread pipes. Screenshot completion requires a fresh PNG
with its final IEND marker, complete ImageIO status and a decodable image.
Native completion is accepted only within its deadline and only the caller
publishes the image atomically. When the fallback simctl
has written that image but stalls during process teardown, Loupe reaps its own
child and atomically delivers the image. Incomplete images time out at the same
10-second deadline and cannot reuse an earlier output. Regression tests cover
large stderr, a complete PNG followed by ignored termination, and an incomplete
PNG with a pre-existing output. Public `ui screenshot` and the fixture's first
rendered-frame preflight use this same capture path, preserving their
10-second deadline instead of waiting for raw simctl process termination.
The touch harness keeps a 15-second action/state
limit. Only a completed after snapshot/accessibility record within that limit
allows a separate 15-second budget for the remaining screenshot (10 seconds)
and log request (5 seconds). It still requires successful CLI exit and checks
the application's counters, offsets and input state; no action is replayed.
After dispatch, runtime checks and after-state capture succeed, an unavailable
after screenshot is a diagnostic warning rather than a failed action. The CLI
records `after.screenshot-error.json`, removes stale pixels, and keeps the
completed state. This prevents callers from repeating an action that already
succeeded. Before screenshots and explicit `ui screenshot` requests remain
strict; failed dispatch, observation or state verification still fails.

The simulator touch transport waits for each send completion and propagates
delivery errors, keeping the client alive through the final up event. It uses
the full SimulatorKit mouse-message signature, including size and edge. Tap
and drag sequences run asynchronously on a serial user-interactive worker,
with completion synchronized before returning to the caller. This observes the
queue QoS and avoids main-thread inline nesting in the private proxy. Opt-in
diagnostics record the actual class. Gesture waits remain bounded and use no busy
loop or real-time scheduling. A background-caller reproduction on iOS 26.3
recognized only one of two double taps with the preceding implementation;
the interactive queue recognized both, with down spacing near 165ms instead of
458ms. CI checks the actual gesture QoS together with application state. Tap
phases preserve a 50ms contact dwell after down acknowledgement. Double taps
share one timeline with nominal down events 155ms apart, leaving at least 16ms
after the preceding up acknowledgement. Each wait uses a one-shot strict
dispatch timer with zero leeway on an independent interactive queue. ARM CI
showed 150ms timer coalescing even at interactive QoS; precision is requested
only for the bounded gesture phase. Actions and screenshot workers declare
finite user-initiated activity, ending it on every return or error path and
allowing idle system sleep. A late wake-up does not add another
full inter-tap gap: CI showed accumulated waits stretching SwiftUI double taps
beyond recognition. Slow acknowledgement must not consume the dwell and
collapse down/up into consecutive messages; an Intel failure showed an 83ms
down acknowledgement followed immediately by up.
Movement still follows a monotonic duration without adding acknowledgement
latency to each sample. Opt-in HID diagnostics retain each enqueue and
acknowledgement time and the native builder's numeric message fields.
They also identify framework, service-context, device-set and client setup.
Host preparation uses the interactive input worker; screenshot workers use
explicit high task priority. Their phase logs include actual QoS;
CI previously spent over 15 seconds loading host frameworks before any touch
was sent. Host framework/client setup completes before trace work spawns
another CoreSimulator client. Selector resolution remains fresh after setup,
and no input is sent during preparation. Screenshot process startup consumes
the existing capture budget. Reusing an action trace directory clears Loupe's
previous generated evidence before input, including target crops and failure
records. Unrelated files are preserved; a directory at a generated file path
is rejected before dispatch rather than removed recursively.
Touch CI retains the last capture phase and a bounded fixture-process sample
on failure, including failures before the first input assertion.
Installation failures retain bundle metadata and bounded install-service logs;
the app is installed once and actions are never replayed.
The packed Indigo event union retains its 128-byte storage, making each
payload 144 bytes; the duplicated contact must use that complete stride.
Compile-time layout assertions protect it, and bottle E2E checks actual
application changes on both architectures rather than transport acknowledgement.
Movement follows the requested duration rather than adding acknowledgement
latency to each interval. The acknowledgement contract is also used by the
[idb HID client](https://github.com/facebook/idb/blob/main/FBSimulatorControl/HID/SimulatorIndigoHIDClient.swift).

## Assertions

`run-touch-e2e.sh` runs `verify-touch-scenarios.py` against the launched runtime.
The same Python assertions run on a linked physical device via `LOUPE_TOUCH_HOST`.

- UIKit UIButton and SwiftUI Button counters must change exactly once for
  testID, native target alias, coordinates, and saved-snapshot ref taps.
- Both screens exercise public taps, double taps, long presses, ordinary and
  held drags, internal touch delivery, and scroll drag/swipe with measured
  content offset changes. A single tap must not fire a double-tap-only handler;
  `--count 2` must fire it. Immediate drag must not complete a hold-before-drag
  recognizer; public held drag must complete with translation over 100 points.
- Non-accessibility double-tap and pan surfaces appear exactly once with their
  observed touch capabilities. Status labels and handler-free or disabled
  recognizers do not appear as targets.
- UIKit verifies that Korean input mode is active, then checks exact English,
  Korean, punctuation and emoji text plus editingChanged. SwiftUI verifies the
  same literal text in its TextField and binding-backed status.
- The existing bookmark E2E covers UISearchBar input through its nested
  first-responder text field, rather than treating the forwarding container as
  a UIKeyInput responder.
- Unfocused text input, invalid touch geometry, concurrent touch rejection,
  and successful subsequent input are checked without action retries.
- The CLI contract fixture verifies physical input uses `/input/touch` and
  `/input/text`, never simctl; 400/404/503 text errors cause one write and are
  propagated. It also covers a target missing from native accessibility whose
  coordinates come from the view tree.

`act input` inserts literal text through UIKeyInput on the foreground iOS
responder. Physical apps require a Debug injector; simulator packages support
Debug and Release. HID key codes were keyboard-layout-dependent and transformed English
under a Korean layout. The packaged Release simulator injector and linked physical Debug injector
provide this input route. It uses the existing CLI syntax and
preserves input selection and application editing behavior. A runtime without
the text endpoint returns an error; Loupe does not retry with layout-dependent
keys. Use a matching updated Debug injector when validating the new CLI.

Ordinary CLI `drag` starts movement immediately. `--hold-duration` holds the
same contact before movement; `--duration` measures only movement time.
`act tap --count 2` delivers two taps. Both options are explicit additions;
existing commands retain their defaults. A separate held tap followed by drag
creates separate contacts and cannot replace a held drag.

```bash
loupe act tap --test-id gesture.double --count 2
loupe act drag --from 80,300 --to 250,300 --hold-duration 0.6 --duration 0.4
```

## Run and evidence

```bash
Examples/LoupeExample/run-touch-e2e.sh

# Signed Debug fixture already launched with LOUPE_EXAMPLE_ROUTE=touch:
LOUPE_TOUCH_HOST='http://[device-tunnel-ip]:port' Examples/LoupeExample/run-touch-e2e.sh

# Fresh device launch with LOUPE_EXAMPLE_ROUTE=touch.swiftui:
LOUPE_TOUCH_HOST='http://[device-tunnel-ip]:port' LOUPE_TOUCH_MODE=--swiftui-only \
  Examples/LoupeExample/run-touch-e2e.sh
```

The simulator temporarily enables Korean and restores only the affected
keyboard and language preferences, including on assertion failure. It marks
the keyboard list expanded to preserve the requested list in an English
environment. It restarts the simulator only when those preferences change, because keyboard services cache enabled
input modes across app launches. Physical runs require
Korean already enabled and do not change device keyboard preferences.
The SwiftUI fixture uses a scrolling container so keyboard-driven layout
compression does not push its buttons behind the navigation bar.

Evidence directories printed by the harness contain runtime identity, full
snapshots, app state assertions, native target lists, public action traces,
internal request/response pairs, and separate UIKit/SwiftUI reports. Success
responses alone are not treated as proof of application behavior.

## Local verification on 2026-10-01 and 2026-10-02

- iPhone 17 Pro Simulator, iOS 26.3: the UIKit-to-SwiftUI suite and a fresh
  SwiftUI-only launch both passed.
- The same complete and fresh SwiftUI suites passed on an owned iOS 18.6 ARM
  simulator. A background-QoS caller recognized both double taps on each OS
  with the strict timer, with measured down spacing near 155ms. Actual Intel
  compatibility remains a separate bottled-runtime CI requirement.
- iPhone 15, iOS 26.2.1, signed Debug app: the complete suite and a fresh
  SwiftUI-only launch passed before the selective debug-graph optimization.
  Verification of the final linked SDK is pending device unlock.
- A fresh mixed SwiftUI snapshot with the Release SDK and immediate phase logs
  improved from 1.09s to 0.29s locally, preserving the fixture control IDs,
  labels, values and touch capabilities.
- 363 Swift Testing tests in 51 suites, release CLI build/contracts,
  available platform SDK builds, macOS E2E, iOS injection/runtime/native
  scenarios, and bookmark E2E passed.
- The required local harness stopped at tvOS E2E because no Apple TV simulator
  was installed. visionOS/watchOS simulator destinations were also unavailable;
  those runtime checks require CI or a host with the corresponding runtimes.

These results verify this source change; the published v0.4.0 bottles retain
their existing immutable release source until a subsequent release.
