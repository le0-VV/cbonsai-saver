---
id: "01JX3Y1Y8H6TR4Y3Q38K1W9P2C"
title: "Add memory during agent work"
type: "routine"
status: "active"
tags:
  - "brick"
  - "agent-workflow"
created_at: "2026-05-24T00:00:00Z"
updated_at: "2026-05-24T00:00:00Z"
source:
  kind: "example"
  ref: "Brick v1 examples"
evidence:
  -
    kind: "example"
    text: "Agents should route memory writes through Brick commands."
prerequisites:
  - "The candidate contains no secrets or unconfirmed PII."
  - "The memory has concrete evidence."
steps:
  - "Search existing memory for related context."
  - "Prepare a JSON memory candidate with source and evidence."
  - "Run ./brick memory add using JSON stdin."
  - "Run ./brick rebuild after the memory is accepted."
verify: "brick memory validate returns ok for the written memory file."
content_hash: "sha256:1034f70ec1da029f724dbd38ce87d4c51d10c8f932fc492ea48f1c027f8a8731"
---
Capture durable project context through Brick instead of hand-editing canonical memory files.
