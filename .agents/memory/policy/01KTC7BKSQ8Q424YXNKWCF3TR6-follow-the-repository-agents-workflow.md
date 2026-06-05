---
id: "01KTC7BKSQ8Q424YXNKWCF3TR6"
title: "Follow the repository AGENTS workflow"
type: "policy"
status: "active"
tags:
  - "agent-workflow"
  - "commits"
  - "memory"
  - "verification"
created_at: "2026-06-05T15:45:18Z"
updated_at: "2026-06-05T15:45:18Z"
source:
  kind: "repository"
  ref: "AGENTS.md"
evidence:
  -
    kind: "quote"
    text: "Before doing any work, write a concrete plan in .agents/TODO.md as a check list and follow it."
  -
    kind: "quote"
    text: "Commit each completed logical unit when the repo is verified and the staged changes are coherent."
content_hash: "sha256:9de09cb22fbcd6ae74260f29bea6ba9f20e6a5f07e737ce4afe17869bfdbbb6e"
---
Agents in this repository must follow AGENTS.md: search Brick memory before relying on prior context, keep a concrete checklist in .agents/TODO.md, read files fully before editing, keep diffs narrow, add tests for new behavior unless the change is docs or metadata only, commit each coherent logical unit after verification, and use supervised commit author formatting with conventional commit messages.
