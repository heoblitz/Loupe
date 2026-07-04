# Homebrew Distribution

Loupe is distributed from this repository as a Homebrew tap formula.

## Install

```bash
brew tap heoblitz/loupe https://github.com/heoblitz/Loupe.git
brew install loupe
```

The formula builds and installs:

- `bin/loupe`
- `libexec/LoupeInjector.framework/LoupeInjector`
- `share/loupe/skills/loupe`

The formula packages the Loupe skill so `loupe skills install` can install it
into supported local agent clients.

Loupe does not require a separate simulator action CLI; runtime actions use the
native HID backend packaged with `loupe`.

## Formula Source

The canonical formula is:

```text
Formula/loupe.rb
```

The current repository can be tapped directly with the explicit URL above. A
separate `heoblitz/homebrew-loupe` tap is optional if a shorter tap command is
needed later.

## Release Checklist

1. Run the post-change harness:

```bash
scripts/verify-agent-work.sh
```

2. Commit changes and tag the release:

```bash
git tag vX.Y.Z
git push origin main vX.Y.Z
```

3. Download the tag archive and update `Formula/loupe.rb`:

```bash
curl -L -o /tmp/loupe-vX.Y.Z.tar.gz \
  https://github.com/heoblitz/Loupe/archive/refs/tags/vX.Y.Z.tar.gz
shasum -a 256 /tmp/loupe-vX.Y.Z.tar.gz
```

4. Commit and push the formula update.

5. Verify the public tap path:

```bash
brew update
brew audit --strict --online heoblitz/loupe/loupe
brew reinstall --build-from-source heoblitz/loupe/loupe
brew test heoblitz/loupe/loupe
loupe doctor
loupe injector-path
```

## Current Status

The stable formula currently points at `v0.1.8`.
