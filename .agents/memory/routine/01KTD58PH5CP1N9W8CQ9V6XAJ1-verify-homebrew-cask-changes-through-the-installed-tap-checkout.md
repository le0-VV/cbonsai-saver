---
id: "01KTD58PH5CP1N9W8CQ9V6XAJ1"
title: "Verify Homebrew cask changes through the installed tap checkout"
type: "routine"
status: "active"
tags:
  - "homebrew"
  - "verification"
  - "cask"
  - "release"
created_at: "2026-06-06T00:27:59Z"
updated_at: "2026-06-06T00:27:59Z"
source:
  kind: "repository"
  ref: "PR #8 verification workflow"
evidence:
  -
    kind: "diagnostic"
    text: "Homebrew rejected local cask info with: Homebrew requires casks to be in a tap, rejecting: ./Casks/cbonsai-saver.rb."
  -
    kind: "diagnostic"
    text: "After updating the installed tap checkout, `brew info cbonsai-saver` resolved to cbonsai-saver (cbonsai saver) as a cask."
  -
    kind: "diagnostic"
    text: "After cask reinstall, xattr output contained provenance attributes but no com.apple.quarantine attributes, and strict codesign verification passed."
steps:
  - "Before merge, run `./tests/run.sh`, `git diff --check`, and `ruby -c Casks/cbonsai-saver.rb`."
  - "After merge, run `git -C /opt/homebrew/Library/Taps/le0-vv/homebrew-cbonsai-saver pull --ff-only`."
  - "Run `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 brew info cbonsai-saver` to confirm plain install resolves to the cask."
  - "When safe, run `HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall --cask cbonsai-saver` to exercise cask artifacts and postflight."
  - "Check `xattr -lr \"$HOME/Library/Screen Savers/cbonsai saver.saver\"` for absence of `com.apple.quarantine` and run `codesign --verify --deep --strict --verbose=4` on the installed saver."
verify: "The installed saver has no `com.apple.quarantine` attributes and passes strict codesign verification."
content_hash: "sha256:3503ef8882a3b91fd7e2ebb4366a4588e3f08567052d6876f470391be5e7e349"
---
Homebrew refuses full `brew info`, `brew audit`, and cask loader checks against `Casks/cbonsai-saver.rb` when it is not under an installed tap path. For local branch work, use `ruby -c Casks/cbonsai-saver.rb`, `./tests/run.sh`, and `git diff --check`. After the branch is merged, update `/opt/homebrew/Library/Taps/le0-vv/homebrew-cbonsai-saver` with `git pull --ff-only`, then verify through Homebrew using the tap checkout. For install behavior, run `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 brew info cbonsai-saver` and, when safe, `HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall --cask cbonsai-saver`, followed by `xattr -lr "$HOME/Library/Screen Savers/cbonsai saver.saver"` and strict `codesign` verification.
