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

The cask postflight removes Homebrew's quarantine attribute from the installed
screen saver bundle. If macOS still blocks a local development build, run:

```sh
xattr -dr com.apple.quarantine "$HOME/Library/Screen Savers/cbonsai saver.saver"
```

## Release maintenance

Build the release asset before drafting or publishing a GitHub release:

```sh
./scripts/package-release.sh 1.1.2x arm64
./scripts/package-release.sh 1.1.2x x86_64
```

The arm64 build writes `build/release/artifacts/cbonsai-saver-1.1.2x.zip`; this
is the Homebrew cask asset. The x86_64 build writes
`build/release/artifacts/cbonsai-saver-1.1.2x-x86_64-macos10.15.zip` for manual
Intel Mac installs. Both commands print SHA-256 values. The cask URL and
SHA-256 must match the uploaded arm64 GitHub release asset.

The Intel build compiles bundled `ncurses` from pinned upstream source with a
macOS 10.15 deployment target. Do not use Homebrew's prebuilt `ncurses` dylibs
for that artifact.

The release zip includes the screen saver bundle, `LICENSE`,
`THIRD_PARTY_NOTICES.md`, and `SECURITY.md`.
