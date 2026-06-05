# Homebrew tap

This repository can be used as a custom Homebrew tap for `cbonsai-saver`.

```sh
brew tap le0-VV/cbonsai-saver https://github.com/le0-VV/cbonsai-saver
brew install cbonsai-saver
```

The formula installs the release bundle into Homebrew's prefix. Link it into the
user screen saver folder after installation:

```sh
mkdir -p "$HOME/Library/Screen Savers"
ln -sfn "$(brew --prefix cbonsai-saver)/Screen Savers/cbonsai saver.saver" "$HOME/Library/Screen Savers/cbonsai saver.saver"
```

## Release maintenance

Build the release asset before drafting or publishing a GitHub release:

```sh
./scripts/package-release.sh 1.0
```

The script writes `build/release/artifacts/cbonsai-saver-1.0.zip` and prints its
SHA-256. The formula URL and SHA-256 must match the uploaded GitHub release
asset.
