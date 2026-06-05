# Instructions for all agents

- **DO NOT**, unless explicitly instructed by the user, modify `AGENTS.md`.
- When given a problem, break it down into smaller, actionable steps, and work through each step logically.
- Always use the language of the user's message.
- Record any memory and extra instructions through Brick with `./brick memory add`; do not write memory files directly unless Brick is broken and the user approves the fallback.
- Never rely on assumptions about prior work; search Brick memory with `./brick memory search "query"` or clarify with the user.
- If you have questions or concerns that block safe progress, clarify with the user immediately.
- When delegating work to subagents is available, prefer delegating work to subagents.
- Subagents must working in their own git branch or worktree with clear ownership, separate from the main branch
- Subagents must not spawn their own subagents unless the user explicitly asks for nested delegation.
- The main agent owns supervision: review, integrate, resolve conflicts, and merge subagent work after they finish.
- Before doing any work, write a concrete plan in `.agents/TODO.md` as a check list and follow it.
- Tick off the relevant item in `.agents/TODO.md` as its completed to keep track of progress.
- For tracked-file changes, work on a task branch created from up-to-date `main`; use the `codex/` branch prefix unless the user explicitly requests a different branch name or an existing ref conflict makes that prefix impossible.
- Do not push directly to `main`. `main` is protected by the GitHub `Protect main` ruleset; push the task branch, open a pull request, and merge through GitHub after required checks pass.
- Keep each task branch focused on one logical change and do not mix unrelated edits into the same branch or pull request.
- All commits and release tags must be signed. Verify the latest commit with `git log -1 --show-signature` before pushing.
- Do not disable, bypass, or weaken branch protection, repository rulesets, required signed commits, or pull-request requirements unless the user explicitly instructs you to do so for that specific operation.
- Record any extra instructions present in the repo.
- After updating Brick memory, validate with `./brick memory validate`, rebuild retrieval state with `./brick rebuild` when needed, and commit only the resulting memory changes as a coherent `docs(memory): ...` commit.
- For non-trivial or long-running work, preserve direction in `ROADMAP.md` and current state in `.agents/TODO.md`.
- Read a file fully before editing it.
- Keep comments rare and useful. Explain why or constraints, not obvious mechanics.
- Keep diffs narrow and task-focused.
- Do not guess at attribute names, control flow, or config behaviour.
- Prefer fail-fast behaviour, never use silent fallback logic unless user explicitly requests so.
- Add tests for new behaviour unless the change is strictly docs/metadata cleanup.
- Commit each completed logical unit when the repo is verified and the staged changes are coherent.
- Only stop working when everything in `.agents/TODO.md` is complete or you are blocked by something that requires user intervention.
- If everything is ticked off in `.agents/TODO.md` and a new work round is needed, clear it and write the new plan.
- Set commit author name to `Coding agent supervised by {global git user.name}`, replacing `{global git user.name}` with `git config --global user.name`.
- Use the global git email unless the user explicitly instructs otherwise.
- Write commit messages as `{type}({scope}): {description}`; use `docs(memory): ...` for dedicated Brick memory commits.
- Use one of these commit types: `build`, `chore`, `CI`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`.
    1. Never rely on assumptions about prior work; search Brick memory with `./brick memory search "query"` or clarify with the user.
    2. Combine project context and clear reasoning to answer with concrete details.
    3. Keep answers direct and actionable.
