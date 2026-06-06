---
id: "01KTD57RCQTWW8M92MV4XZ2Z86"
title: "Keep the Homebrew tap cask-only for cbonsai-saver"
type: "decision"
status: "active"
tags:
  - "homebrew"
  - "cask"
  - "install"
  - "quarantine"
created_at: "2026-06-06T00:27:29Z"
updated_at: "2026-06-06T00:27:29Z"
source:
  kind: "repository"
  ref: "PR #8, Casks/cbonsai-saver.rb, HOMEBREW.md, tests/run.sh"
evidence:
  -
    kind: "quote"
    text: "Plain brew install should resolve to the cask; do not keep a formula with the same token."
  -
    kind: "quote"
    text: "system_command \"/usr/bin/xattr\""
  -
    kind: "quote"
    text: "args: [\"-dr\", \"com.apple.quarantine\", installed_saver.to_s]"
content_hash: "sha256:a8e73cc5977744de60d50047826cff0b7c9b22bf522869ff50a0c8deadf7fe98"
---
The Homebrew tap should not contain `Formula/cbonsai-saver.rb`. Keeping only `Casks/cbonsai-saver.rb` makes plain `brew install cbonsai-saver` resolve to the cask, matching `brew install --cask cbonsai-saver`. Re-adding a formula with the same token makes Homebrew prefer the formula, which installs under the prefix and bypasses the screen saver artifact handling and cask postflight. The cask postflight removes `com.apple.quarantine` from the installed screen saver bundle with `/usr/bin/xattr -dr`.
