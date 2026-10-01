# Homebrew Distribution

Loupe is distributed from this repository as a Homebrew tap formula.

## Install

```bash
brew tap heoblitz/loupe https://github.com/heoblitz/Loupe.git
brew install loupe
```

The formula installs the following files. With a matching bottle it downloads
prebuilt files; source installation builds them locally:

- `bin/loupe`
- `libexec/LoupeInjector.framework/LoupeInjector` (iOS Simulator)
- `libexec/LoupeInjector.framework/macos/LoupeInjector` (macOS)
- `share/loupe/skills/loupe`

The formula packages the Loupe skill so `loupe skills install` can install it
into supported local agent clients.

Loupe does not require a separate simulator action CLI; runtime actions use the
native HID backend packaged with `loupe`.

For a local macOS debug app, launch and attach in one command:

```bash
loupe app launch \
  --bundle-id com.example.App \
  --macos-app /path/to/App.app
```

This uses the macOS injector returned by `loupe injector-path --macos`. A
Hardened Runtime production app can reject dynamic-library injection; link the
injector into development builds when that is required.

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

2. Commit the release source and create the tag and a draft GitHub Release:

```bash
git tag vX.Y.Z
git push origin main vX.Y.Z
gh release create vX.Y.Z --draft --title vX.Y.Z --generate-notes
```

3. Download the tag archive and update `Formula/loupe.rb`:

```bash
curl -L -o /tmp/loupe-vX.Y.Z.tar.gz \
  https://github.com/heoblitz/Loupe/archive/refs/tags/vX.Y.Z.tar.gz
shasum -a 256 /tmp/loupe-vX.Y.Z.tar.gz
```

Update the source URL and checksum, remove the previous `bottle do` block, and
commit the Formula change to `main`.

4. In GitHub Actions, run **Homebrew Bottles** from `main` and enter `X.Y.Z`.
The workflow verifies the Formula and immutable source tag, then:

- builds Apple Silicon and Intel bottles;
- installs each generated bottle and requires `poured_from_bottle: true`;
- runs the Formula test and verifies the CLI and both injector code signatures
  on Apple Silicon;
- verifies that the matching GitHub Release is still a draft before uploading;
- uploads both bottles to the draft Release; and
- generates and commits the new Formula `bottle do` block.

Pull requests that change the Formula or bottle workflow run the build and pour
checks but never upload assets or modify `main`.

5. After the bottle workflow completes, run **Verify** from `main`. The workflow's
Formula commit uses `GITHUB_TOKEN`, so its push does not start another workflow
automatically. Wait for all Verify jobs to pass on that commit, then publish the
draft Release:

```bash
gh workflow run verify.yml --ref main
# Wait for every Verify job to pass before publishing.
gh release edit vX.Y.Z --draft=false
```

6. Verify both the public bottle and source-build paths:

```bash
brew update
brew audit --strict --online heoblitz/loupe/loupe
HOMEBREW_NO_BOTTLE_SOURCE_FALLBACK=1 \
  brew reinstall --force-bottle heoblitz/loupe/loupe
brew info --json=v2 heoblitz/loupe/loupe | \
  jq -e '.formulae[0].installed[0].poured_from_bottle == true'
brew test heoblitz/loupe/loupe
loupe doctor
loupe injector-path
loupe injector-path --macos

brew reinstall --build-from-source heoblitz/loupe/loupe
brew test heoblitz/loupe/loupe
loupe doctor
loupe injector-path
loupe injector-path --macos
```

## Current Status

The stable formula currently points at `v0.4.0`. The workflow above publishes
Apple Silicon and Intel bottles built on macOS 15; compatible installs avoid local Swift
compilation. Other supported source-build environments retain that path. Xcode
is still needed for simulator/device tooling during Loupe use.

The bottle includes the CLI, iOS Simulator injector, macOS injector, and skill.
It does not include a physical-device injector: physical iOS debug apps link
and embed LoupeInjector through SwiftPM in their own signed development build.

PR checks package the PR source and prove a bottle can be poured, so they do
not accidentally test an older tagged release. Release publication uses the
immutable source tag in the formula. Both architectures must pass before the
manual publication job uploads any package.
