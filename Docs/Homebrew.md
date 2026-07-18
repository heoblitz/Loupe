# Homebrew Distribution

Loupe is distributed from this repository as a Homebrew tap formula.

## Install

```bash
brew tap heoblitz/loupe https://github.com/heoblitz/Loupe.git
brew install loupe
```

The formula installs:

- `bin/loupe`
- `libexec/LoupeInjector.framework/LoupeInjector`
- `share/loupe/skills/loupe`

The formula packages the Loupe skill so `loupe skills install` can install it
into supported local agent clients.

Releases published with the Homebrew Bottles workflow provide bottles for
Apple Silicon and Intel on macOS 15 or newer. Homebrew skips the build-only
Xcode requirement when it pours a bottle. Xcode and Simulator are still
required to use Loupe with iOS Simulator apps. Systems without a matching
bottle fall back to a source build.

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
The workflow verifies that the Formula, tag, and draft Release agree, then:

- builds Apple Silicon and Intel bottles;
- installs each generated bottle and requires `poured_from_bottle: true`;
- runs the Formula test and verifies both code signatures;
- uploads both bottles to the draft Release; and
- generates and commits the new Formula `bottle do` block.

Pull requests that change the Formula or bottle workflow run the build and pour
checks but never upload assets or modify `main`.

5. Wait for the Formula commit's Verify workflow, then publish the draft
Release:

```bash
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

brew reinstall --build-from-source heoblitz/loupe/loupe
brew test heoblitz/loupe/loupe
loupe doctor
loupe injector-path
```

## Current Status

The stable formula currently points at `v0.2.0` and is source-built. Bottle
publication starts with the next release that uses the workflow above.
