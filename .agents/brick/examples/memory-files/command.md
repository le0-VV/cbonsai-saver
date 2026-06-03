---
id: "01JX3Y1Y8H6TR4Y3Q38K1W9P2B"
title: "Rebuild Brick memory index"
type: "command"
status: "active"
tags:
  - "brick"
  - "index"
  - "search"
created_at: "2026-05-24T00:00:00Z"
updated_at: "2026-05-24T00:00:00Z"
source:
  kind: "example"
  ref: "Brick v1 examples"
evidence:
  -
    kind: "example"
    text: "brick rebuild regenerates the local SQLite index from canonical Markdown memory."
command: "./brick rebuild"
cwd: "."
expected_output: "The command reports an ok status or a readable rebuild summary."
failure_notes: "Fix invalid or blocked memory files before rebuilding again."
when_to_use: "After adding, editing, merging, or deleting Brick memory files."
content_hash: "sha256:572fa299771aa953cb8bb604ea1eba6a51f967a7d757136bf25b03feed336c73"
---
Run this after memory files change so local keyword and semantic retrieval reflect canonical Markdown memory.
