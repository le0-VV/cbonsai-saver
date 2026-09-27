# Homebrew tap

This repository can be used as a custom Homebrew tap for `cbonsai-saver`.

```sh
brew tap le0-VV/cbonsai-saver https://github.com/le0-VV/cbonsai-saver
brew install cbonsai-saver
```

The tap ships `cbonsai-saver` as a cask so `brew install cbonsai-saver` and
`brew install --cask cbonsai-saver` both install the screen saver into the user
screen saver folder automatically. The cask is Apple Silicon only; Intel Mac
users should download the `cbonsai-saver-<version>-x86_64-macos10.15.zip`
archive from the GitHub release page and install `cbonsai saver.saver` manually
into `~/Library/Screen Savers`.

The cask removes Homebrew's quarantine attribute from the staged screen saver
bundle before installation and asks macOS to relaunch the legacy screen saver
host so upgrades do not keep running a stale loaded bundle. If macOS still
blocks a local development build, run:

```sh
xattr -dr com.apple.quarantine "$HOME/Library/Screen Savers/cbonsai saver.saver"
```

## Release maintenance

Build the release asset before drafting or publishing a GitHub release:

```sh
./scripts/package-release.sh 1.1.7 arm64
./scripts/package-release.sh 1.1.4x x86_64
```

The arm64 build writes `build/release/artifacts/cbonsai-saver-1.1.7.zip`; this
is the Homebrew cask asset. The x86_64 build writes
`build/release/artifacts/cbonsai-saver-1.1.4x-x86_64-macos10.15.zip` for manual
Intel Mac installs. Both commands print SHA-256 values. The cask URL and
SHA-256 must match the uploaded arm64 GitHub release asset.

Publishing a stable release whose tag is a three-part numeric version, such as
`1.2.3`, triggers `.github/workflows/update-homebrew-cask.yml`. The workflow
downloads the exact `cbonsai-saver-<version>.zip` asset, calculates its SHA-256,
checks any digest reported by GitHub, updates the cask and aligned arm64 release
metadata, and runs the local test suite. It then creates a GitHub-signed commit
on an `automation/homebrew-<version>` branch, opens a ready pull request, and
dispatches CI explicitly for that branch. Pre-releases, draft releases, manual
Intel `x` releases, malformed versions, missing or duplicate assets, checksum
disagreements, downgrades, and retagged versions fail without changing the tap.

The repository must allow GitHub Actions to create pull requests. The workflow
does not push directly to protected `main`, approve its own pull request, or
merge automatically.

The `x` suffix is only for the manual Intel release version. Do not use it for
the Apple Silicon Homebrew cask version.

Release builds compile bundled `ncurses` from pinned upstream source. The
arm64 cask artifact targets macOS 11.5, and the Intel artifact targets macOS
10.15. Do not use Homebrew's prebuilt `ncurses` dylibs for release artifacts.

The release zip includes the screen saver bundle, `LICENSE`,
`THIRD_PARTY_NOTICES.md`, and `SECURITY.md`.
