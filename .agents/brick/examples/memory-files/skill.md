---
id: "01JX3Y1Y8H6TR4Y3Q38K1W9P2D"
title: "Investigate Brick merge conflict reports"
type: "skill"
status: "active"
tags:
  - "brick"
  - "merge"
  - "review"
created_at: "2026-05-24T00:00:00Z"
updated_at: "2026-05-24T00:00:00Z"
source:
  kind: "example"
  ref: "Brick v1 examples"
evidence:
  -
    kind: "example"
    text: "brick conflicts list and export expose generated merge review reports."
prerequisites:
  - "A Brick merge-driver conflict report exists under .agents/brick/conflicts/."
steps:
  - "Run ./brick conflicts list."
  - "Export the relevant report with ./brick conflicts export <id>."
  - "Compare base, ours, and theirs entries before proposing a resolution."
verify: "The proposed resolution preserves evidence and requires human approval before writing durable memory."
content_hash: "sha256:cbac93d2aa37f8350b9851611c75a9bf734f8e417998eb2205c8769194b63dc6"
---
Use Brick conflict reports to understand memory merge cases that require human review.
