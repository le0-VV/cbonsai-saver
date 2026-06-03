# LLM-Assisted Memory Ingest

Use this flow when an agent asks an LLM to compose Brick memory from a
conversation, work summary, commit, issue, PR, or file excerpt.

## Decision Policy

Return one ingest decision:

- `add`: the source contains durable, project-relevant context with concrete
  evidence and no unresolved safety concern.
- `clarify`: the source probably contains useful memory, but durability,
  meaning, source, or public-safety status is ambiguous.
- `reject`: the source is transient, test-only, already superseded, low
  confidence, sensitive, or not useful for future agent work.

Do not add memories for one-off commands, temporary test facts, generic
assistant explanations, guesses, or statements that only describe the current
turn. If the user corrects an earlier fact, keep only the latest durable
version. If the user says not to remember something, reject that item. The
phrase "remember that" is only a signal to consider memory; do not preserve that
phrase in the memory body and do not reject durable content merely because the
user used those words.

A direct user statement is valid evidence. If the user explicitly asks to save
or remember durable project context, choose `add` unless the content is
transient, unsafe, already superseded, or genuinely ambiguous. Do not require
the assistant to add new information before saving a user-provided durable fact.

## Candidate Rules

When `action` is `add`, produce one Brick memory candidate in `candidate`.
The candidate must be ready for agent review before it is passed to:

```sh
./brick memory add
```

Write the memory body as one concise, standalone canonical statement. Do not
copy the whole transcript, include "remember that", or preserve temporary
phrasing unless the phrasing itself is the durable fact. Quote source text only
inside `evidence`.

Choose the narrowest useful type:

- `decision`: settled project direction, architecture constraints, policy, or
  implementation choices.
- `fact`: observed project, environment, integration, or compatibility facts.
- `preference`: user or maintainer preferences that should guide future work.
- `command`: a reusable command with when-to-use context.
- `routine`: a repeatable workflow.
- `skill`: a capability or procedure agents should reuse.
- `task`: durable open work only when it should remain in project memory.
- `pattern`, `incident`, or `policy`: use only when those meanings are clearer
  than the options above.

Use concrete `source` and `evidence`. Prefer short quoted user text, file
excerpts, commit/PR/issue references, or agent work summaries with enough
detail for maintainers to judge trust. Set `confirm_public` to `true` only when
the user explicitly confirms the content is safe for the repository's intended
audience.

Keep `source.ref` as a short locator such as `current conversation`,
`work summary`, a file path, a commit hash, or a PR/issue reference. Do not put
quoted source text or role labels such as `User:` or `Assistant:` in
`source.ref`; quoted text belongs only in `evidence`.

Do not emit `fields` in LLM output. The reviewing agent may add Brick's
type-specific `fields` manually for command, routine, or skill memories when
the structure is clear.

## Agent Review

The agent must inspect the LLM output before writing:

1. If `action` is `clarify`, ask the listed questions before adding memory.
2. If `action` is `reject`, do not write memory.
3. If `action` is `add`, review and normalize `candidate`, then pass only the
   candidate object to `./brick memory add`.
4. If Brick returns `blocked`, follow the returned actions instead of forcing
   the write.
5. After Brick accepts a memory, run `./brick rebuild`.

Use `memory-ingest.schema.json` as the response schema when the LLM endpoint
supports JSON Schema constrained output.
