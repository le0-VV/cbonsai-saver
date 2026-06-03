# Brick Agent Usage

Use Brick whenever project context, preferences, decisions, routines, commands,
or merge-review memory may affect your work.

## Start Of Work

1. Run `./brick setup` if Brick directories, the root `brick` symlink, or Git
   merge-driver config appear incomplete.
   Setup also creates or repairs `.agents/brick/.venv`, preferring `uv` and
   falling back to `pip` for dependencies declared in
   `.agents/brick/pyproject.toml`.
2. Check whether semantic retrieval is configured for this machine. Brick reads
   `embedding.url` and `embedding.model` from the gitignored
   `.agents/brick/config.local.json` file. After first setup, if there is no
   clear user answer on whether to use semantic retrieval, ask it as an
   important setup question. If the user opts in, ask for the embedding server
   URL and model name, write both values to the local config file, and run
   `./brick rebuild`. If they opt out, `./brick memory search` still works, but
   it is keyword-only; report that limitation before relying on retrieval
   quality.
3. Search memory before relying on assumptions:

   ```sh
   ./brick memory search "topic or task" --pretty
   ```

4. If `.agents/brick/index/brick.sqlite3` is missing or stale, or if embedding
   settings changed, run:

   ```sh
   ./brick rebuild
   ```

## Adding Memory

Do not hand-edit canonical memory files unless the user explicitly asks. Prepare
a JSON candidate and send it through Brick:

```sh
./brick memory add < .agents/brick/examples/memory-add/decision.json
```

Valid candidates need:

- `title`, `type`, `tags`, `body`, `source`, and `evidence`.
- Concrete source/evidence that lets maintainers judge trust.
- No secrets.
- No possible PII unless the user has explicitly confirmed it is public with
  `confirm_public: true`.

When using an LLM to compose memory, use
`.agents/brick/examples/llm-ingest/instructions.md` and constrain the response
with `.agents/brick/examples/llm-ingest/memory-ingest.schema.json` when the LLM
endpoint supports JSON Schema output. The LLM should return an ingest decision:
`add`, `clarify`, or `reject`. Only pass the nested `candidate` object to
`./brick memory add` after agent review. Do not add memory when the LLM returns
`clarify` or `reject`; ask the user or skip the write.

After a memory is accepted, rebuild search:

```sh
./brick rebuild
```

## Redacting Memory

If sensitive text has already entered canonical memory, do not edit it by hand.
Use exact text redaction through Brick:

```sh
./brick memory redact --pretty < redaction.json
```

The redaction JSON must include `path`, `redactions`, and `reason`. Brick
replaces matching text with `[REDACTED]`, appends redaction evidence, marks the
memory `redacted`, recomputes the hash, validates the file, and rebuilds the
index by default.

## Useful Commands

```sh
./brick memory validate --pretty
./brick memory redact --pretty < redaction.json
./brick memory search "release process" --limit 5 --pretty
./brick conflicts list --pretty
./brick conflicts export <conflict-id> --pretty
./brick conflicts propose <conflict-id> --pretty < proposal.json
```

## Merge Conflicts

Brick's merge driver only resolves exact or fast-forward-safe memory cases.
When it writes a conflict report, export and inspect it before proposing a
resolution:

```sh
./brick conflicts list --pretty
./brick conflicts export <conflict-id> --pretty
```

Human review is required before writing a final merged memory when Brick reports
`required_action: human_review`.

Agents may attach a proposed merged memory to a conflict report:

```sh
./brick conflicts propose <conflict-id> --pretty < proposal.json
```

The proposal JSON must include `summary` and `memory_markdown`, with optional
`notes`. This updates only the local conflict report's `proposed_resolution`;
the final canonical memory must still be accepted by a human.

## Examples

- `memory-add/decision.json`: valid decision candidate.
- `memory-add/command.json`: valid command candidate with structured command fields.
- `memory-add/routine.json`: valid routine candidate with steps.
- `memory-add/skill.json`: valid skill candidate with steps.
- `memory-add/blocked-unsafe.json`: unsafe example that Brick should reject.
- `llm-ingest/instructions.md`: agent rules for LLM-assisted memory ingest.
- `llm-ingest/memory-ingest.schema.json`: JSON Schema for LLM ingest decisions.
- `memory-files/*.md`: rendered examples of canonical Markdown memory files.
