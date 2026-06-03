from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Sequence
from venv import EnvBuilder

from brick import __version__
from brick.conflicts import (
    BrickConflictError,
    export_conflict_report,
    list_conflict_reports,
    propose_conflict_resolution,
    run_merge_driver,
)
from brick.index import (
    BrickIndexError,
    LOCAL_CONFIG_RELATIVE_PATH,
    rebuild_index,
    search_index,
)
from brick.memory import (
    MemoryAddError,
    MemoryParseError,
    MemoryRedactError,
    create_memory_from_candidate,
    discover_memory_files,
    redact_memory_from_candidate,
    validate_memory_paths,
)


GITIGNORE_ENTRIES = (
    ".agents/brick/.venv/",
    ".agents/brick/index/",
    ".agents/brick/conflicts/",
    ".agents/brick/config.local.json",
    "__pycache__/",
    "*.pyc",
)
GITATTRIBUTES_ENTRY = ".agents/memory/**/*.md merge=brick-memory"
BRICK_VENV_RELATIVE_PATH = Path(".agents/brick/.venv")
BRICK_PYPROJECT_RELATIVE_PATH = Path(".agents/brick/pyproject.toml")
LOCAL_CONFIG_TEMPLATE = (
    '{\n'
    '  "embedding": {\n'
    '    "url": "",\n'
    '    "model": "",\n'
    '    "api_key_env": "BRICK_EMBEDDING_API_KEY"\n'
    '  }\n'
    '}\n'
)
MEMORY_TYPES = (
    "decision",
    "command",
    "routine",
    "skill",
    "preference",
    "fact",
    "incident",
    "pattern",
    "task",
    "policy",
)
AGENTS_BACKUP_NAME = "AGENTS.md.brick-backup"
BRICK_AGENT_MARKER = "<!-- brick-agent-instructions:v1 -->"
AGENTS_TEMPLATE_RELATIVE_PATH = Path(".agents/brick/templates/AGENTS.md")
DEPENDENCY_PATTERN = re.compile(r"""["']([^"']+)["']""")


class BrickError(RuntimeError):
    pass


@dataclass
class SetupResult:
    repo_root: Path
    actions: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, object]:
        return {
            "status": "ok",
            "repo_root": str(self.repo_root),
            "actions": self.actions,
            "warnings": self.warnings,
        }


def run_git(repo_root: Path, args: Sequence[str]) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise BrickError(f"git {' '.join(args)} failed: {detail}")
    return completed.stdout.strip()


def find_repo_root(start: Path | None = None) -> Path:
    cwd = (start or Path.cwd()).resolve()
    completed = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        raise BrickError("Brick must be run inside a Git worktree.")
    return Path(completed.stdout.strip()).resolve()


def ensure_dir(path: Path, result: SetupResult) -> None:
    if path.is_dir():
        return
    if path.exists():
        raise BrickError(f"Expected directory path but found file: {path}")
    path.mkdir(parents=True, exist_ok=True)
    result.actions.append(f"created directory {path.relative_to(result.repo_root)}")


def ensure_executable(path: Path, result: SetupResult) -> None:
    if not path.is_file():
        raise BrickError(f"Brick executable is missing: {path}")
    mode = path.stat().st_mode
    wanted = mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    if wanted != mode:
        path.chmod(wanted)
        result.actions.append(f"made executable {path.relative_to(result.repo_root)}")


def ensure_root_symlink(repo_root: Path, result: SetupResult) -> None:
    link = repo_root / "brick"
    target = Path(".agents/brick/bin/brick")
    if link.is_symlink():
        current = Path(os.readlink(link))
        if current == target:
            return
        raise BrickError(f"Refusing to replace existing brick symlink to {current}")
    if link.exists():
        raise BrickError("Refusing to replace existing repo-root brick path.")
    link.symlink_to(target)
    result.actions.append("created repo-root brick symlink")


def ensure_list_file(path: Path, entries: Iterable[str], result: SetupResult) -> None:
    existing_text = path.read_text(encoding="utf-8") if path.exists() else ""
    existing_lines = set(existing_text.splitlines())
    missing = [entry for entry in entries if entry not in existing_lines]
    if not missing:
        return
    prefix = existing_text
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    path.write_text(prefix + "\n".join(missing) + "\n", encoding="utf-8")
    result.actions.append(f"updated {path.relative_to(result.repo_root)}")


def ensure_local_config(repo_root: Path, result: SetupResult) -> None:
    config_path = repo_root / LOCAL_CONFIG_RELATIVE_PATH
    if config_path.exists():
        return
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config_path.write_text(LOCAL_CONFIG_TEMPLATE, encoding="utf-8")
    result.actions.append(f"created {config_path.relative_to(result.repo_root)}")


def brick_agents_text(repo_root: Path) -> str:
    template_path = repo_root / AGENTS_TEMPLATE_RELATIVE_PATH
    try:
        return template_path.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise BrickError(
            f"Brick AGENTS.md template is missing: {template_path}. "
            "Re-run the Brick installer, then run `./brick setup` again."
        ) from exc


def ensure_agents_file(repo_root: Path, result: SetupResult) -> None:
    agents_path = repo_root / "AGENTS.md"
    backup_path = repo_root / AGENTS_BACKUP_NAME
    desired = brick_agents_text(repo_root)
    if not agents_path.exists():
        agents_path.write_text(desired, encoding="utf-8")
        result.actions.append("created AGENTS.md with Brick instructions")
        return

    current = agents_path.read_text(encoding="utf-8")
    if current == desired:
        return
    if BRICK_AGENT_MARKER in current:
        agents_path.write_text(desired, encoding="utf-8")
        result.actions.append("updated Brick AGENTS.md instructions")
        return

    if backup_path.exists():
        raise BrickError(
            f"Existing AGENTS.md is not Brick-managed and {AGENTS_BACKUP_NAME} "
            "already exists; refusing to overwrite either file."
        )
    backup_path.write_text(current, encoding="utf-8")
    agents_path.write_text(desired, encoding="utf-8")
    result.actions.append(f"backed up AGENTS.md to {AGENTS_BACKUP_NAME}")
    result.actions.append("installed Brick AGENTS.md instructions")


def ensure_venv(repo_root: Path, result: SetupResult, skip_venv: bool) -> None:
    venv_dir = repo_root / BRICK_VENV_RELATIVE_PATH
    if skip_venv:
        result.warnings.append("skipped Brick virtual environment creation")
        return
    python_bin = venv_python_path(venv_dir)
    if python_bin.exists():
        install_brick_dependencies(repo_root, python_bin, result)
        return

    uv_path = shutil.which("uv")
    if uv_path:
        completed = run_dependency_command([uv_path, "venv", str(venv_dir)], repo_root)
        if completed.returncode == 0:
            result.actions.append("created Brick virtual environment with uv")
        else:
            result.warnings.append(
                "uv venv failed; falling back to Python venv: "
                f"{command_failure_detail(completed)}"
            )
            create_venv_with_stdlib(venv_dir, result)
    else:
        create_venv_with_stdlib(venv_dir, result)

    if not python_bin.exists():
        raise BrickError(
            f"Brick virtual environment was created but Python is missing at {python_bin}. "
            "Remove `.agents/brick/.venv` and run `./brick setup` again."
        )
    install_brick_dependencies(repo_root, python_bin, result)


def venv_python_path(venv_dir: Path) -> Path:
    return venv_dir / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def create_venv_with_stdlib(venv_dir: Path, result: SetupResult) -> None:
    try:
        EnvBuilder(with_pip=True).create(venv_dir)
    except Exception as exc:
        raise BrickError(
            "Could not create Brick virtual environment. Install `uv` or ensure "
            "Python's `venv` module is available, then run `./brick setup` again. "
            f"Detail: {exc}"
        ) from exc
    result.actions.append("created Brick virtual environment with Python venv")


def install_brick_dependencies(repo_root: Path, python_bin: Path, result: SetupResult) -> None:
    dependencies = read_project_dependencies(repo_root / BRICK_PYPROJECT_RELATIVE_PATH)
    if not dependencies:
        return

    uv_path = shutil.which("uv")
    if uv_path:
        completed = run_dependency_command(
            [uv_path, "pip", "install", "--python", str(python_bin), *dependencies],
            repo_root,
        )
        if completed.returncode == 0:
            result.actions.append("installed Brick dependencies with uv")
            return
        result.warnings.append(
            "uv dependency install failed; trying pip fallback: "
            f"{command_failure_detail(completed)}"
        )

    completed = run_dependency_command(
        [str(python_bin), "-m", "pip", "install", *dependencies],
        repo_root,
    )
    if completed.returncode != 0:
        raise BrickError(
            "Could not install Brick dependencies with pip. Install `uv` or repair "
            "pip in `.agents/brick/.venv`, then run `./brick setup` again. "
            f"Detail: {command_failure_detail(completed)}"
        )
    result.actions.append("installed Brick dependencies with pip")


def read_project_dependencies(pyproject_path: Path) -> list[str]:
    if not pyproject_path.exists():
        raise BrickError(
            f"Brick dependency file is missing: {pyproject_path}. "
            "Re-run the Brick installer, then run `./brick setup` again."
        )
    text = pyproject_path.read_text(encoding="utf-8")
    try:
        import tomllib
    except ModuleNotFoundError:
        return parse_project_dependencies(text)

    payload = tomllib.loads(text)
    project = payload.get("project", {})
    dependencies = project.get("dependencies", [])
    if not isinstance(dependencies, list) or not all(
        isinstance(item, str) for item in dependencies
    ):
        raise BrickError("Brick pyproject dependencies must be a list of strings.")
    return dependencies


def parse_project_dependencies(pyproject_text: str) -> list[str]:
    in_project = False
    collecting = False
    buffer: list[str] = []
    for raw_line in pyproject_text.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            in_project = line == "[project]"
            collecting = False
            buffer.clear()
            continue
        if not in_project:
            continue
        if collecting:
            buffer.append(line)
            if "]" in line:
                return DEPENDENCY_PATTERN.findall(" ".join(buffer))
            continue
        if line.startswith("dependencies"):
            _, value = line.split("=", 1)
            buffer.append(value.strip())
            if "]" in value:
                return DEPENDENCY_PATTERN.findall(" ".join(buffer))
            collecting = True
    return []


def run_dependency_command(command: Sequence[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(command),
        cwd=cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def command_failure_detail(completed: subprocess.CompletedProcess[str]) -> str:
    detail = completed.stderr.strip() or completed.stdout.strip()
    return detail or f"exit code {completed.returncode}"


def ensure_merge_driver(repo_root: Path, result: SetupResult) -> None:
    run_git(
        repo_root,
        ["config", "--local", "merge.brick-memory.name", "Brick memory merge driver"],
    )
    run_git(
        repo_root,
        [
            "config",
            "--local",
            "merge.brick-memory.driver",
            "./brick merge-driver %O %A %B %L %P",
        ],
    )
    result.actions.append("configured local Git merge driver")


def setup_repo(
    repo_root: Path,
    *,
    skip_venv: bool = False,
    install_agents: bool = True,
    configure_git: bool = True,
) -> SetupResult:
    repo_root = repo_root.resolve()
    result = SetupResult(repo_root=repo_root)
    brick_root = repo_root / ".agents/brick"

    ensure_dir(brick_root / "index", result)
    ensure_dir(brick_root / "conflicts", result)
    for memory_type in MEMORY_TYPES:
        ensure_dir(repo_root / ".agents/memory" / memory_type, result)

    ensure_executable(brick_root / "bin/brick", result)
    ensure_root_symlink(repo_root, result)
    ensure_list_file(repo_root / ".gitignore", GITIGNORE_ENTRIES, result)
    ensure_local_config(repo_root, result)
    ensure_list_file(repo_root / ".gitattributes", (GITATTRIBUTES_ENTRY,), result)

    if configure_git:
        ensure_merge_driver(repo_root, result)
    if install_agents:
        ensure_agents_file(repo_root, result)
    ensure_venv(repo_root, result, skip_venv)
    return result


def emit_json(payload: dict[str, object], pretty: bool = False) -> None:
    if pretty:
        print(json.dumps(payload, indent=2, sort_keys=True))
        return
    print(json.dumps(payload, separators=(",", ":"), sort_keys=True))


def emit_error(message: str, *, pretty: bool = False, as_json: bool = True) -> int:
    payload = {"status": "error", "reason": message}
    if as_json:
        emit_json(payload, pretty)
    else:
        print(f"error: {message}", file=sys.stderr)
    return 1


def command_not_implemented(command: str, pretty: bool) -> int:
    emit_json(
        {
            "status": "error",
            "reason": "not_implemented",
            "command": command,
        },
        pretty,
    )
    return 2


def cmd_setup(args: argparse.Namespace) -> int:
    try:
        result = setup_repo(
            find_repo_root(),
            skip_venv=args.skip_venv,
            install_agents=not args.no_agent_instructions,
            configure_git=not args.no_git_config,
        )
    except BrickError as exc:
        return emit_error(str(exc), as_json=args.json)

    if args.json:
        emit_json(result.to_dict(), args.pretty)
        return 0

    print("Brick setup complete.")
    for action in result.actions:
        print(f"- {action}")
    for warning in result.warnings:
        print(f"- warning: {warning}")
    if not result.actions and not result.warnings:
        print("- no changes needed")
    return 0


def cmd_stub(name: str):
    def _inner(args: argparse.Namespace) -> int:
        return command_not_implemented(name, getattr(args, "pretty", False))

    return _inner


def cmd_rebuild(args: argparse.Namespace) -> int:
    try:
        repo_root = find_repo_root()
        result = rebuild_index(repo_root)
    except BrickError as exc:
        return emit_error(str(exc), pretty=args.pretty, as_json=args.json)
    except BrickIndexError as exc:
        if args.json:
            emit_json(exc.to_dict(), args.pretty)
        else:
            print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.json:
        emit_json(result.to_dict(repo_root), args.pretty)
        return 0

    print("Brick index rebuilt.")
    print(f"- index: {result.path.relative_to(repo_root)}")
    print(f"- memories: {result.memory_count}")
    print(f"- rebuilt_at: {result.rebuilt_at}")
    return 0


def cmd_memory_validate(args: argparse.Namespace) -> int:
    try:
        repo_root = find_repo_root()
        paths = discover_memory_files(repo_root, args.path)
    except (BrickError, MemoryParseError) as exc:
        return emit_error(str(exc), pretty=args.pretty)

    results = validate_memory_paths(repo_root, paths)
    status = "ok"
    if any(result.status == "blocked" for result in results):
        status = "blocked"
    elif any(result.status == "invalid" for result in results):
        status = "invalid"

    emit_json(
        {
            "status": status,
            "checked": len(results),
            "results": [result.to_dict(repo_root) for result in results],
        },
        args.pretty,
    )
    return 0 if status == "ok" else 1


def cmd_memory_add(args: argparse.Namespace) -> int:
    raw_input = sys.stdin.read()
    try:
        candidate = json.loads(raw_input)
    except json.JSONDecodeError as exc:
        emit_json(
            {
                "status": "invalid",
                "reason": "invalid_json",
                "message": str(exc),
            },
            args.pretty,
        )
        return 1
    if not isinstance(candidate, dict):
        emit_json(
            {
                "status": "invalid",
                "reason": "invalid_candidate",
                "issues": [
                    {
                        "code": "invalid_field_type",
                        "message": "memory candidate must be a JSON object",
                    }
                ],
            },
            args.pretty,
        )
        return 1

    try:
        repo_root = find_repo_root()
        result = create_memory_from_candidate(repo_root, candidate)
    except BrickError as exc:
        return emit_error(str(exc), pretty=args.pretty)
    except MemoryAddError as exc:
        issue_payloads = [issue.to_dict() for issue in exc.issues]
        status = (
            "blocked"
            if any(
                issue.get("code") in {"secret_detected", "possible_pii"}
                for issue in issue_payloads
            )
            else "invalid"
        )
        emit_json(
            {
                "status": status,
                "reason": exc.code,
                "issues": issue_payloads,
                "actions": ["redact", "confirm_public", "reject"] if status == "blocked" else ["reject"],
            },
            args.pretty,
        )
        return 1

    emit_json(result.to_dict(repo_root), args.pretty)
    return 0


def cmd_memory_redact(args: argparse.Namespace) -> int:
    raw_input = sys.stdin.read()
    try:
        candidate = json.loads(raw_input)
    except json.JSONDecodeError as exc:
        emit_json(
            {
                "status": "invalid",
                "reason": "invalid_json",
                "message": str(exc),
            },
            args.pretty,
        )
        return 1
    if not isinstance(candidate, dict):
        emit_json(
            {
                "status": "invalid",
                "reason": "invalid_redaction",
                "issues": [
                    {
                        "code": "invalid_field_type",
                        "message": "redaction candidate must be a JSON object",
                    }
                ],
            },
            args.pretty,
        )
        return 1

    try:
        repo_root = find_repo_root()
    except BrickError as exc:
        return emit_error(str(exc), pretty=args.pretty)

    redaction_result = None
    try:
        redaction_result = redact_memory_from_candidate(repo_root, candidate)
        index_result = None
        if candidate.get("rebuild", True):
            index_result = rebuild_index(repo_root)
    except MemoryRedactError as exc:
        issue_payloads = [issue.to_dict() for issue in exc.issues]
        status = (
            "blocked"
            if any(
                issue.get("code") in {"secret_detected", "possible_pii"}
                for issue in issue_payloads
            )
            else "invalid"
        )
        emit_json(
            {
                "status": status,
                "reason": exc.code,
                "issues": issue_payloads,
                "actions": ["redact", "reject"] if status == "blocked" else ["reject"],
            },
            args.pretty,
        )
        return 1
    except BrickIndexError as exc:
        emit_json(
            {
                "status": "error",
                "reason": "redaction_rebuild_failed",
                "redaction": redaction_result.to_dict(repo_root) if redaction_result else None,
                "index_error": exc.to_dict(),
            },
            args.pretty,
        )
        return 1

    payload = redaction_result.to_dict(repo_root)
    payload["index_rebuilt"] = index_result is not None
    if index_result is not None:
        payload["index"] = index_result.to_dict(repo_root)["index"]
    emit_json(payload, args.pretty)
    return 0


def cmd_memory_search(args: argparse.Namespace) -> int:
    try:
        repo_root = find_repo_root()
        payload = search_index(
            repo_root,
            args.query,
            limit=args.limit,
            include_superseded=args.include_superseded,
        )
    except BrickError as exc:
        return emit_error(str(exc), pretty=args.pretty)
    except BrickIndexError as exc:
        emit_json(exc.to_dict(), args.pretty)
        return 1

    emit_json(payload, args.pretty)
    return 0


def cmd_merge_driver(args: argparse.Namespace) -> int:
    try:
        repo_root = find_repo_root()
        result = run_merge_driver(repo_root, args.merge_args)
    except (BrickError, BrickConflictError) as exc:
        print(f"brick merge-driver error: {exc}", file=sys.stderr)
        return 2

    if result.status == "ok":
        return 0
    if result.report is not None:
        print(
            f"brick merge-driver requires human review: "
            f"{result.report.path.relative_to(repo_root)}",
            file=sys.stderr,
        )
    return 1


def cmd_conflicts_list(args: argparse.Namespace) -> int:
    try:
        payload = list_conflict_reports(find_repo_root())
    except (BrickError, BrickConflictError) as exc:
        return emit_error(str(exc), pretty=args.pretty)
    emit_json(payload, args.pretty)
    return 0


def cmd_conflicts_export(args: argparse.Namespace) -> int:
    try:
        payload = export_conflict_report(find_repo_root(), args.id)
    except (BrickError, BrickConflictError) as exc:
        return emit_error(str(exc), pretty=args.pretty)
    emit_json(payload, args.pretty)
    return 0


def cmd_conflicts_propose(args: argparse.Namespace) -> int:
    raw_input = sys.stdin.read()
    try:
        proposal = json.loads(raw_input)
    except json.JSONDecodeError as exc:
        emit_json(
            {
                "status": "invalid",
                "reason": "invalid_json",
                "message": str(exc),
            },
            args.pretty,
        )
        return 1
    if not isinstance(proposal, dict):
        emit_json(
            {
                "status": "invalid",
                "reason": "invalid_proposal",
                "message": "conflict proposal must be a JSON object",
            },
            args.pretty,
        )
        return 1

    try:
        payload = propose_conflict_resolution(find_repo_root(), args.id, proposal)
    except (BrickError, BrickConflictError) as exc:
        return emit_error(str(exc), pretty=args.pretty)
    emit_json(payload, args.pretty)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="brick")
    parser.add_argument("--version", action="store_true", help="show Brick version")
    subparsers = parser.add_subparsers(dest="command")

    setup = subparsers.add_parser("setup", help="prepare this repository for Brick")
    setup.add_argument("--json", action="store_true", help="emit machine JSON")
    setup.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    setup.add_argument("--skip-venv", action="store_true", help="do not create .agents/brick/.venv")
    setup.add_argument(
        "--no-agent-instructions",
        action="store_true",
        help="do not create or update AGENTS.md",
    )
    setup.add_argument(
        "--no-git-config",
        action="store_true",
        help="do not write local Git merge-driver config",
    )
    setup.set_defaults(func=cmd_setup)

    rebuild = subparsers.add_parser("rebuild", help="rebuild the local Brick index")
    rebuild.add_argument("--json", action="store_true", help="emit machine JSON")
    rebuild.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    rebuild.set_defaults(func=cmd_rebuild)

    merge_driver = subparsers.add_parser("merge-driver", help="Git merge driver entrypoint")
    merge_driver.add_argument("merge_args", nargs=argparse.REMAINDER)
    merge_driver.set_defaults(func=cmd_merge_driver)

    memory = subparsers.add_parser("memory", help="memory operations")
    memory_subparsers = memory.add_subparsers(dest="memory_command")

    memory_add = memory_subparsers.add_parser("add", help="add a memory from JSON stdin")
    memory_add.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    memory_add.set_defaults(func=cmd_memory_add)

    memory_redact = memory_subparsers.add_parser(
        "redact",
        help="redact memory from JSON stdin",
    )
    memory_redact.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    memory_redact.set_defaults(func=cmd_memory_redact)

    memory_validate = memory_subparsers.add_parser("validate", help="validate memory files")
    memory_validate.add_argument("path", nargs="?")
    memory_validate.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    memory_validate.set_defaults(func=cmd_memory_validate)

    memory_search = memory_subparsers.add_parser("search", help="search memory")
    memory_search.add_argument("query")
    memory_search.add_argument("--limit", type=int, default=10, help="maximum number of results")
    memory_search.add_argument(
        "--include-superseded",
        action="store_true",
        help="include superseded memories in search results",
    )
    memory_search.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    memory_search.set_defaults(func=cmd_memory_search)

    conflicts = subparsers.add_parser("conflicts", help="conflict report operations")
    conflicts_subparsers = conflicts.add_subparsers(dest="conflicts_command")

    conflicts_list = conflicts_subparsers.add_parser("list", help="list conflict reports")
    conflicts_list.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    conflicts_list.set_defaults(func=cmd_conflicts_list)

    conflicts_export = conflicts_subparsers.add_parser("export", help="export a conflict report")
    conflicts_export.add_argument("id")
    conflicts_export.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    conflicts_export.set_defaults(func=cmd_conflicts_export)

    conflicts_propose = conflicts_subparsers.add_parser(
        "propose",
        help="attach a proposed resolution",
    )
    conflicts_propose.add_argument("id")
    conflicts_propose.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    conflicts_propose.set_defaults(func=cmd_conflicts_propose)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.version:
        print(__version__)
        return 0
    if not hasattr(args, "func"):
        parser.print_help()
        return 2
    return args.func(args)
