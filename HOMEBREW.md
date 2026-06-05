# Homebrew tap

This repository can be used as a custom Homebrew tap for `cbonsai-saver`.

```sh
brew tap le0-VV/cbonsai-saver https://github.com/le0-VV/cbonsai-saver
brew install --cask cbonsai-saver
```

The cask installs the screen saver into the user screen saver folder
automatically. The formula remains available for prefix-only installs:

```sh
brew install cbonsai-saver
```

Formula installs put the release bundle under Homebrew's prefix and print
manual linking caveats because formulae should not install into the user's
`~/Library/Screen Savers` folder directly.

## Release maintenance

Build the release asset before drafting or publishing a GitHub release:

```sh
./scripts/package-release.sh 1.1
```

The script writes `build/release/artifacts/cbonsai-saver-1.1.zip` and prints its
SHA-256. The formula and cask URL and SHA-256 must match the uploaded GitHub
release asset.

The release zip includes the screen saver bundle, `LICENSE`,
`THIRD_PARTY_NOTICES.md`, and `SECURITY.md`.
