# Homebrew tap

This repository can be used as a custom Homebrew tap for `cbonsai-saver`.

```sh
brew tap le0-VV/cbonsai-saver https://github.com/le0-VV/cbonsai-saver
brew install cbonsai-saver
```

The tap ships `cbonsai-saver` as a cask so `brew install cbonsai-saver` and
`brew install --cask cbonsai-saver` both install the screen saver into the user
screen saver folder automatically.

The cask postflight removes Homebrew's quarantine attribute from the installed
screen saver bundle. If macOS still blocks a local development build, run:

```sh
xattr -dr com.apple.quarantine "$HOME/Library/Screen Savers/cbonsai saver.saver"
```

## Release maintenance

Build the release asset before drafting or publishing a GitHub release:

```sh
./scripts/package-release.sh 1.1.1
```

The script writes `build/release/artifacts/cbonsai-saver-1.1.1.zip` and prints its
SHA-256. The cask URL and SHA-256 must match the uploaded GitHub release asset.

The release zip includes the screen saver bundle, `LICENSE`,
`THIRD_PARTY_NOTICES.md`, and `SECURITY.md`.
