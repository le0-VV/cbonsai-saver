---
id: "01KT701RPFSE5FZNAQR1C5Y6W5"
title: "Use Brick semantic retrieval for this repository"
type: "decision"
status: "active"
tags:
  - "brick"
  - "semantic-search"
  - "embeddings"
created_at: "2026-06-03T15:01:23Z"
updated_at: "2026-06-03T15:01:23Z"
source:
  kind: "conversation"
  ref: "Current user setup request"
evidence:
  -
    kind: "quote"
    text: "Setup this project to use https://github.com/le0-VV/brick. Use semantic search using embedding model on http://localhost:8745/v1"
content_hash: "sha256:c0d1d93bd73e4893277d4fa21ef59b7db1ff5cf92a9517a6208bd69b101136c3"
---
This repository is set up to use Brick for agent memory, with semantic retrieval configured locally through `.agents/brick/config.local.json` using the OpenAI-compatible embedding base URL `http://localhost:8745/v1` and model `mlx-community/embeddinggemma-300m-4bit`. The local config and generated index are device-local and should not be committed.
