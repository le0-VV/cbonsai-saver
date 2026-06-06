---
id: "01KTD570YYMGZZFXT2VEX2W7K5"
title: "Sign the completed screen saver bundle before release packaging"
type: "decision"
status: "active"
tags:
  - "release"
  - "codesigning"
  - "gatekeeper"
  - "screensaver"
created_at: "2026-06-06T00:27:05Z"
updated_at: "2026-06-06T00:27:05Z"
source:
  kind: "repository"
  ref: "PR #7 and scripts/package-release.sh"
evidence:
  -
    kind: "diagnostic"
    text: "The installed 1.1 saver failed `codesign --verify --deep --strict` with: code has no resources but signature indicates they must be present."
  -
    kind: "quote"
    text: "codesign --force --deep --sign - --timestamp=none \"$1\""
  -
    kind: "quote"
    text: "codesign --verify --deep --strict --verbose=4 \"$1\""
content_hash: "sha256:bef76ce298bf9886fa857a17740fd077cfa613a09c8294d057639c3ee192984c"
---
Official release archives must sign the completed `cbonsai saver.saver` bundle after `cbonsai`, ncurses dylibs, the manual, and `Info.plist` are present. The outer bundle needs its own resource seal; signing only the nested executable, bundled `cbonsai`, and dylibs is insufficient and can produce macOS's damaged-app dialog. `scripts/package-release.sh` should ad-hoc sign the finished bundle with `codesign --force --deep --sign - --timestamp=none` and immediately strict-verify it before zipping.
