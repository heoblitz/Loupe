# Development Homebrew Overlay

Use this when Homebrew already installed `loupe`, but local development needs a
newer CLI or injector.

Prefer `brew reinstall --HEAD`; use the manual overlay only for quick local
iteration.

## Recommended: Install HEAD

```bash
brew tap heoblitz/loupe https://github.com/heoblitz/Loupe.git
brew reinstall --HEAD heoblitz/loupe/loupe
loupe doctor
loupe injector-path
loupe injector-path --macos
```

This keeps Homebrew metadata consistent and updates both the CLI and injector.

## Manual Overlay

Build from this checkout:

```bash
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

Replace the installed artifacts:

```bash
BREW_PREFIX="$(brew --prefix)"
LOUPE_PREFIX="$(brew --prefix loupe)"

cp .build/release/loupe "$LOUPE_PREFIX/bin/loupe"

mkdir -p "$LOUPE_PREFIX/libexec/LoupeInjector.framework"
cp "$INJECTOR_SCRATCH/arm64-apple-ios-simulator/release/libLoupeInjector.dylib" \
  "$LOUPE_PREFIX/libexec/LoupeInjector.framework/LoupeInjector"

MACOS_INJECTOR_SCRATCH=".build/dev-homebrew-loupe-macos-injector"
MACOS_ARCH="$(uname -m)"
swift build \
  --configuration release \
  --disable-sandbox \
  --scratch-path "$MACOS_INJECTOR_SCRATCH" \
  --product LoupeInjector
mkdir -p "$LOUPE_PREFIX/libexec/LoupeInjector.framework/macos"
cp "$MACOS_INJECTOR_SCRATCH/$MACOS_ARCH-apple-macosx/release/libLoupeInjector.dylib" \
  "$LOUPE_PREFIX/libexec/LoupeInjector.framework/macos/LoupeInjector"

"$BREW_PREFIX/bin/loupe" doctor
"$BREW_PREFIX/bin/loupe" injector-path
"$BREW_PREFIX/bin/loupe" injector-path --macos
```

Replacing only `bin/loupe` is risky because CLI and injector behavior can drift.
Replace both together.

## PATH Overlay

If you do not want to modify Homebrew's Cellar, put a local wrapper directory
before Homebrew on `PATH`:

```bash
mkdir -p .dev-bin
ln -sf "$PWD/.build/release/loupe" .dev-bin/loupe
export PATH="$PWD/.dev-bin:$PATH"
export LOUPE_INJECTOR_PATH="$PWD/.build/dev-homebrew-loupe-injector/arm64-apple-ios-simulator/release/libLoupeInjector.dylib"
export LOUPE_MACOS_INJECTOR_PATH="$PWD/.build/dev-homebrew-loupe-macos-injector/release/libLoupeInjector.dylib"

loupe doctor
loupe injector-path
loupe injector-path --macos
```

This mode is shell-local; keep `PATH` and `LOUPE_INJECTOR_PATH` set in every
shell that should use the local build.

## Revert

```bash
brew reinstall heoblitz/loupe/loupe
unset LOUPE_INJECTOR_PATH
unset LOUPE_MACOS_INJECTOR_PATH
loupe doctor
```
