---
id: "01KTD59HGSEJARP4WKB2PM18C6"
title: "Preserve cbonsai-saver runtime constraints"
type: "decision"
status: "active"
tags:
  - "runtime"
  - "security"
  - "configuration"
  - "multi-monitor"
created_at: "2026-06-06T00:28:27Z"
updated_at: "2026-06-06T00:28:27Z"
source:
  kind: "repository"
  ref: "CBCommandLine.m, cbonsai_saverView.m, tests/run.sh"
evidence:
  -
    kind: "quote"
    text: "return @\"/usr/bin:/bin:/usr/sbin:/sbin\";"
  -
    kind: "quote"
    text: "execve(processArgv[0], processArgv, processEnvironment)"
  -
    kind: "quote"
    text: "Screen saver should pass a display-salted automatic seed when launching cbonsai."
  -
    kind: "quote"
    text: "Live and infinite modes should always be enabled, not exposed as settings."
content_hash: "sha256:628d9ba09fbbee7b5adf66f5fef3bfee74c0806330922363bab91164b203531b"
---
The screen saver should run the bundled `cbonsai` binary from the saver bundle, not an external executable path and not through `/bin/sh`. It should launch with direct `execve`, keep the runtime `PATH` limited to system directories, and not expose an executable setting. Live and infinite cbonsai modes are always enabled rather than user-toggleable, and screensaver/print/help/save/load modes are not exposed as settings. Font size is automatic, not a user setting. Multi-monitor instances should use a display-salted automatic seed so different displays grow different trees unless the user explicitly sets a fixed seed.
