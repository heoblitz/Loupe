# Development Homebrew Overlay

This note is for local Loupe development when Homebrew already installed
`loupe`, but you want the executable and injector to come from your git clone.

Prefer the `brew reinstall --HEAD` path when possible. Use the manual overlay
only for quick local iteration.

## Current Homebrew Layout

```bash
brew --prefix
brew --prefix loupe
which loupe
ls -l /opt/homebrew/bin/loupe
```

Typical Apple Silicon layout:

```text
/opt/homebrew/bin/loupe -> ../Cellar/loupe/0.1.0/bin/loupe
/opt/homebrew/Cellar/loupe/0.1.0/bin/loupe
/opt/homebrew/Cellar/loupe/0.1.0/libexec/LoupeInjector.framework/LoupeInjector
```

Loupe resolves the injector through `loupe injector-path`, so the CLI and
injector should be updated together.

## Recommended: Install HEAD From The Tap

```bash
brew tap heoblitz/loupe https://github.com/heoblitz/Loupe.git
brew reinstall --HEAD heoblitz/loupe/loupe
loupe doctor
loupe injector-path
```

This keeps Homebrew metadata consistent and builds both:

- `bin/loupe`
- `libexec/LoupeInjector.framework/LoupeInjector`

## Manual Overlay From This Clone

Use this when you need the exact working tree without committing or pushing.

```bash
cd /Users/woody/Workspace/loupe

swift build \
  --configuration release \
  --disable-sandbox \
  --product loupe

SIMULATOR_TRIPLE="arm64-apple-ios15.0-simulator"
SIMULATOR_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
INJECTOR_SCRATCH=".build/dev-homebrew-loupe-injector"

swift build \
  --configuration release \
  --disable-sandbox \
  --scratch-path "$INJECTOR_SCRATCH" \
  --product LoupeInjector \
  --sdk "$SIMULATOR_SDK" \
  --triple "$SIMULATOR_TRIPLE"
```

Then replace the Homebrew-installed artifacts:

```bash
BREW_PREFIX="$(brew --prefix)"
LOUPE_PREFIX="$(brew --prefix loupe)"

cp .build/release/loupe "$LOUPE_PREFIX/bin/loupe"

mkdir -p "$LOUPE_PREFIX/libexec/LoupeInjector.framework"
cp "$INJECTOR_SCRATCH/arm64-apple-ios-simulator/release/libLoupeInjector.dylib" \
  "$LOUPE_PREFIX/libexec/LoupeInjector.framework/LoupeInjector"

"$BREW_PREFIX/bin/loupe" doctor
"$BREW_PREFIX/bin/loupe" injector-path
```

If the copy fails with permission errors, keep the same commands but run only the
`cp` lines with `sudo`.

## Safer Alternative: PATH Overlay

Instead of modifying Homebrew Cellar files, put a local wrapper directory before
Homebrew on `PATH`:

```bash
mkdir -p .dev-bin
ln -sf "$PWD/.build/release/loupe" .dev-bin/loupe
export PATH="$PWD/.dev-bin:$PATH"
```

For this mode, point Loupe at the local injector:

```bash
export LOUPE_INJECTOR_PATH="$PWD/.build/dev-homebrew-loupe-injector/arm64-apple-ios-simulator/release/libLoupeInjector.dylib"
loupe doctor
loupe injector-path
```

This avoids mutating `/opt/homebrew`, but the environment variables must be set
in every shell that uses the local build.

## Revert To Packaged Homebrew

```bash
brew reinstall heoblitz/loupe/loupe
loupe doctor
```

If you used the PATH overlay, remove `.dev-bin` from `PATH` and unset:

```bash
unset LOUPE_INJECTOR_PATH
```

## Notes

- Replacing only `bin/loupe` is risky because CLI and injector behavior can
  drift. Replace both artifacts together.
- Homebrew may overwrite manual Cellar changes on `brew upgrade`, `brew
  reinstall`, or `brew cleanup`.
- `loupe start` launches the simulator app with injection; it does not start a
  separate host-side daemon.
