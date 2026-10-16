# idb PoC results — 2026-10-16

**Recommendation: keep the current implementation. Consider idb as an optional
input backend; this PoC does not support a wholesale replacement or establish
that idb fixes CI reliability.** No production source, tests, fixtures or formula
were changed. PR #24 remains a draft and release validation is suspended.

## Input comparison

Official idb 1.7.3, with fresh UIKit and SwiftUI processes for each backend.
All actions require observed app-state changes. There is no action replay or
deadline increase. The order is native then idb, so this single-run capability
check cannot establish relative failure rates.

| Environment | Native gestures | idb gestures | idb AX Unicode + change event | Additional failures |
| --- | --- | --- | --- | --- |
| Local Xcode 26.3 / iOS 26.2 | 12/12 | 12/12 | 2/2 | Basic idb text: 3 failures |
| CI Xcode 26.3 / iOS 26.2 stock | 6/6 measured | 12/12 | 2/2 | Native UIKit launch exceeded 30s; basic idb text: 3 failures |
| CI Xcode 27.0 / iOS 27.0 stock | Not reached | Not reached | Not reached | Companion startup exceeded 30s |
| CI Xcode 27.0 / iOS 27.0 widget profile | 12/12 | 12/12 | 2/2 | Basic idb text: 3 failures; idb SwiftUI AX read and screenshot timed out |

Six gestures per screen: button, gesture tap, long press, forward scroll,
backward scroll, and held drag. idb's Xcode 27 companion log confirms
`Negotiated the dtuhid HID transport`.

The final local native comparison passed **18/18** checks, including ASCII and
Unicode insertion and focus. The Xcode 27 widget-profile native comparison also
passed **18/18**. The idb comparisons intentionally fail overall: unsupported
input and observation failures are retained as failed results.

### Text is not interchangeable

With the UIKit fixture's Korean keyboard, `idb ui text 'Hello Loupe 123!'`
produced `ㅗ디ㅣㅐ ㅣㅐㅕㅔㄷ 123!`. On both screens, the mixed Korean/emoji
string was rejected with `No keycode found for 한`.

An explicitly separate `idb ui set-value --api axbridge` probe set
`Hello Loupe 123! 한글 👋🏼` and triggered the fixture's input-change callback
on both screens, locally and in CI. This is AX value setting, not keyboard
typing; it was never silently substituted for a failed HID text command.

This follows the pinned [idb key-map implementation](https://github.com/facebook/idb/blob/v1.7.3/idb/common/hid.py#L255-L262).

## Independent idb-only proof

The app is launched without Loupe injection. idb discovers elements through AX,
sends real HID button/gesture taps and long presses, sets Unicode through AX,
checks text and change callbacks through AX, and captures a screenshot.

| Environment | Result |
| --- | --- |
| Local Xcode 26.3 / iOS 26.2 | Both screens passed |
| CI Xcode 26.3 / iOS 26.2 stock | Both screens passed |
| CI Xcode 27.0 / iOS 27.0 widget profile | Both screens passed, DTUHID confirmed |
| CI Xcode 27.0 / iOS 27.0 stock | Companion startup exceeded 30s; app/input checks were not reached |

The final independent CI is **2/3 environments passed, overall failed**. The
stock Xcode 27 startup failure remains even with simulator-only discovery.

idb launch acknowledges process creation before the scene is ready. The PoC
uses `idb ui wait` inside the same original 30-second launch budget. The final
companion invocation also uses `--only simulator`, avoiding the default
physical-device discovery path during a simulator-only experiment. An earlier
stock Xcode 27 companion published its port about 67 seconds after startup;
that run is reported as setup-blocked, not as a failed touch operation.
Narrowing discovery did not resolve the stock-host initialization failure;
no longer timeout or automatic action retry was introduced.

## What this establishes

idb can replace the exercised coordinate/gesture primitives, and the fixture
can also be driven without the Loupe observer in the passing environments.
Basic idb text is not a drop-in
replacement for Loupe literal-text input. Independent idb AX reads and screen
capture can also time out on hosted Xcode 27.

The original PR's last failure was a Loupe snapshot process timing out after
earlier gestures passed. Swapping only input transport does not directly fix
that observation path. Replacing the observer would require separate parity
work for Loupe's UIKit/view/style/layout diagnostics; the AX element tree in
this PoC does not test that parity.

## Reproduction and evidence

- Branch: `codex/idb-poc`; setup/commands: [README](README.md).
- Comparison source: `30457701dbf07e214c03e474047ad92c57708471`.
- [Comparison CI and downloadable raw evidence](https://github.com/heoblitz/Loupe/actions/runs/38864720067).
- Final simulator-only standalone source: `15061c175f42019e810ac0e44c12edc52d9cc6bc`.
- [Final independent CI](https://github.com/heoblitz/Loupe/actions/runs/38865750571).
- Local raw evidence: `/tmp/loupe-idb-poc/local-final` and
  `/tmp/loupe-idb-poc/local-simulator-only`.

The initial standalone attempt without scene-readiness waiting is retained at
`/tmp/loupe-idb-poc/local-standalone`. The intermediate CI run 38865308211 was
superseded when simulator-only discovery was selected; it is not validation of
the final invocation. Local keyboard preferences and the original Shutdown
device state are restored. Existing Homebrew installations are preserved.
