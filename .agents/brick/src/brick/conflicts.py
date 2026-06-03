from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from brick.memory import (
    MemoryDocument,
    MemoryParseError,
    parse_frontmatter,
    compute_content_hash,
    format_timestamp,
    generate_ulid,
    load_memory,
    render_memory_text,
    split_frontmatter,
    validate_memory,
)


CONFLICT_SCHEMA_VERSION = 1
CONFLICTS_RELATIVE_PATH = Path(".agents/brick/conflicts")
PROPOSAL_ALLOWED_FIELDS = {"summary", "memory_markdown", "notes"}
SEMANTIC_SIMILARITY_THRESHOLD = 0.5
SEMANTIC_SIMILARITY_MIN_TOKENS = 6
SEMANTIC_FRONTMATTER_EXCLUDED_FIELDS = {
    "id",
    "status",
    "created_at",
    "updated_at",
    "content_hash",
    "supersedes",
    "related",
}
SEMANTIC_STOP_WORDS = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "be",
    "by",
    "for",
    "from",
    "has",
    "have",
    "in",
    "into",
    "is",
    "it",
    "its",
    "of",
    "on",
    "or",
    "should",
    "that",
    "the",
    "this",
    "to",
    "when",
    "with",
}
TOKEN_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]*")


class BrickConflictError(RuntimeError):
    pass


@dataclass(frozen=True)
class SemanticSimilarity:
    method: str
    score: float


@dataclass
class ConflictReportResult:
    report: dict[str, Any]
    path: Path

    def to_dict(self, repo_root: Path) -> dict[str, Any]:
        return {
            "status": "ok",
            "report": self.report,
            "path": relative_to_repo(repo_root, self.path),
        }


@dataclass
class MergeDriverResult:
    status: str
    action: str
    report: ConflictReportResult | None = None

    def to_dict(self, repo_root: Path) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "status": self.status,
            "action": self.action,
        }
        if self.report is not None:
            payload["report_path"] = relative_to_repo(repo_root, self.report.path)
            payload["report_id"] = self.report.report["id"]
        return payload


@dataclass(frozen=True)
class MergeDriverArgs:
    base: Path
    ours: Path
    theirs: Path
    marker_size: str | None = None
    memory_path: str | None = None


def conflicts_dir(repo_root: Path) -> Path:
    return repo_root / CONFLICTS_RELATIVE_PATH


def list_conflict_reports(repo_root: Path) -> dict[str, Any]:
    reports = []
    root = conflicts_dir(repo_root)
    if root.exists():
        for path in sorted(root.glob("*.json")):
            report = read_json_file(path)
            reports.append(conflict_summary(repo_root, path, report))
    reports.sort(key=lambda item: (item.get("created_at") or "", item.get("id") or ""))
    return {
        "status": "ok",
        "count": len(reports),
        "reports": reports,
    }


def export_conflict_report(repo_root: Path, report_id: str) -> dict[str, Any]:
    path = conflict_path_for_id(repo_root, report_id)
    if not path.exists():
        raise BrickConflictError(f"conflict report not found: {report_id}")
    return {
        "status": "ok",
        "path": relative_to_repo(repo_root, path),
        "report": read_json_file(path),
    }


def propose_conflict_resolution(
    repo_root: Path,
    report_id: str,
    proposal: dict[str, Any],
) -> dict[str, Any]:
    validate_proposal_payload(proposal)
    path = conflict_path_for_id(repo_root, report_id)
    if not path.exists():
        raise BrickConflictError(f"conflict report not found: {report_id}")
    report = read_json_file(path)
    validation = validate_proposed_memory_markdown(proposal["memory_markdown"])
    if validation.status != "ok":
        issue_codes = ", ".join(issue.code for issue in validation.issues)
        raise BrickConflictError(
            f"proposed memory markdown did not validate: {issue_codes}"
        )

    proposed_resolution: dict[str, Any] = {
        "kind": "memory_markdown",
        "created_at": format_timestamp(datetime.now(UTC)),
        "summary": proposal["summary"],
        "memory_markdown": proposal["memory_markdown"],
        "validation": validation.to_dict(),
    }
    if "notes" in proposal:
        proposed_resolution["notes"] = proposal["notes"]
    report["proposed_resolution"] = proposed_resolution
    write_conflict_report(repo_root, report)
    return {
        "status": "ok",
        "path": relative_to_repo(repo_root, path),
        "report_id": report.get("id"),
        "proposed_resolution": proposed_resolution,
    }


def run_merge_driver(repo_root: Path, raw_args: list[str]) -> MergeDriverResult:
    args = parse_merge_driver_args(raw_args)
    base_text = read_text(args.base)
    ours_text = read_text(args.ours)
    theirs_text = read_text(args.theirs)

    if ours_text == theirs_text:
        args.ours.write_text(ours_text, encoding="utf-8")
        return MergeDriverResult(status="ok", action="identical")
    if base_text == ours_text:
        args.ours.write_text(theirs_text, encoding="utf-8")
        return MergeDriverResult(status="ok", action="use_theirs")
    if base_text == theirs_text:
        args.ours.write_text(ours_text, encoding="utf-8")
        return MergeDriverResult(status="ok", action="keep_ours")
    if same_memory_content(args.ours, args.theirs):
        args.ours.write_text(ours_text, encoding="utf-8")
        return MergeDriverResult(status="ok", action="same_memory_content")

    structured = structured_memory_merge(repo_root, args)
    if structured is not None:
        return structured

    report = create_merge_conflict_report(repo_root, args)
    return MergeDriverResult(status="conflict", action="human_review", report=report)


def parse_merge_driver_args(raw_args: list[str]) -> MergeDriverArgs:
    if len(raw_args) < 3:
        raise BrickConflictError("merge-driver requires at least base, ours, and theirs paths")
    return MergeDriverArgs(
        base=Path(raw_args[0]),
        ours=Path(raw_args[1]),
        theirs=Path(raw_args[2]),
        marker_size=raw_args[3] if len(raw_args) > 3 else None,
        memory_path=raw_args[4] if len(raw_args) > 4 else None,
    )


def structured_memory_merge(repo_root: Path, args: MergeDriverArgs) -> MergeDriverResult | None:
    try:
        base = load_memory(args.base)
        ours = load_memory(args.ours)
        theirs = load_memory(args.theirs)
    except (OSError, UnicodeDecodeError, MemoryParseError):
        return None

    memory_ids = {
        base.frontmatter.get("id"),
        ours.frontmatter.get("id"),
        theirs.frontmatter.get("id"),
    }
    if len(memory_ids) != 1 or None in memory_ids:
        return None

    merged_frontmatter, merge_conflicts, appendable_unions = merge_frontmatter(
        base.frontmatter,
        ours.frontmatter,
        theirs.frontmatter,
    )
    merged_body, body_conflict = merge_text_field("body", base.body, ours.body, theirs.body)
    if body_conflict is not None and not merge_conflicts:
        merged_frontmatter["content_hash"] = stale_content_hash(base, ours, theirs)
        conflict_body = git_style_body_conflict(args, ours.body, theirs.body)
        conflict_text = render_memory_text(merged_frontmatter, conflict_body)
        args.ours.write_text(conflict_text, encoding="utf-8")
        report = create_merge_conflict_report(
            repo_root,
            args,
            conflicts=[body_conflict],
            appendable_unions=appendable_unions,
        )
        return MergeDriverResult(status="conflict", action="human_review", report=report)

    if merge_conflicts:
        report_conflicts = merge_conflicts
        if body_conflict is not None:
            report_conflicts = [body_conflict, *merge_conflicts]
        report = create_merge_conflict_report(
            repo_root,
            args,
            conflicts=report_conflicts,
            appendable_unions=appendable_unions,
        )
        return MergeDriverResult(status="conflict", action="human_review", report=report)

    merged_frontmatter["content_hash"] = compute_content_hash(merged_frontmatter, merged_body)
    merged_text = render_memory_text(merged_frontmatter, merged_body)
    merged_document = MemoryDocument(
        path=args.ours,
        frontmatter=merged_frontmatter,
        body=merged_body,
        raw_text=merged_text,
    )
    validation = validate_memory(merged_document)
    if validation.status != "ok":
        report = create_merge_conflict_report(
            repo_root,
            args,
            conflicts=[
                {
                    "field": issue.field or "file",
                    "reason": issue.code,
                }
                for issue in validation.issues
            ],
            appendable_unions=appendable_unions,
        )
        return MergeDriverResult(status="conflict", action="human_review", report=report)

    args.ours.write_text(merged_text, encoding="utf-8")
    return MergeDriverResult(status="ok", action="structured_merge")


def merge_frontmatter(
    base: dict[str, Any],
    ours: dict[str, Any],
    theirs: dict[str, Any],
) -> tuple[dict[str, Any], list[dict[str, str]], dict[str, list[Any]]]:
    merged: dict[str, Any] = {}
    conflicts: list[dict[str, str]] = []
    appendable_unions: dict[str, list[Any]] = {}
    for key in sorted(set(base) | set(ours) | set(theirs)):
        if key == "content_hash":
            continue
        base_value = base.get(key)
        ours_has = key in ours
        theirs_has = key in theirs
        ours_value = ours.get(key)
        theirs_value = theirs.get(key)

        if ours_has and theirs_has and ours_value == theirs_value:
            merged[key] = ours_value
        elif ours_value == base_value and theirs_has:
            merged[key] = theirs_value
        elif theirs_value == base_value and ours_has:
            merged[key] = ours_value
        elif key == "evidence" and lists_available(base_value, ours_value, theirs_value):
            union = union_json_values(base_value, ours_value, theirs_value)
            merged[key] = union
            appendable_unions[key] = union
        elif key == "updated_at" and ours_has and theirs_has:
            merged[key] = max(str(ours_value), str(theirs_value))
        else:
            conflicts.append(
                {
                    "field": key,
                    "reason": "structured_frontmatter_conflict",
                }
            )
    return merged, conflicts, appendable_unions


def merge_text_field(
    field_name: str,
    base: str,
    ours: str,
    theirs: str,
) -> tuple[str, dict[str, str] | None]:
    if ours == theirs:
        return ours, None
    if ours == base:
        return theirs, None
    if theirs == base:
        return ours, None
    return ours, {
        "field": field_name,
        "reason": "both_sides_changed",
    }


def git_style_body_conflict(args: MergeDriverArgs, ours: str, theirs: str) -> str:
    size = conflict_marker_size(args.marker_size)
    return (
        f"{'<' * size} ours\n"
        f"{ensure_final_newline(ours)}"
        f"{'=' * size}\n"
        f"{ensure_final_newline(theirs)}"
        f"{'>' * size} theirs\n"
    )


def conflict_marker_size(raw_size: str | None) -> int:
    if raw_size is None:
        return 7
    try:
        size = int(raw_size)
    except ValueError:
        return 7
    return max(size, 7)


def ensure_final_newline(value: str) -> str:
    return value if value.endswith("\n") else f"{value}\n"


def stale_content_hash(*documents: MemoryDocument) -> str:
    for document in documents:
        value = document.frontmatter.get("content_hash")
        if isinstance(value, str):
            return value
    return "sha256:" + "0" * 64


def lists_available(*values: Any) -> bool:
    return all(isinstance(value, list) for value in values)


def union_json_values(*values: list[Any]) -> list[Any]:
    seen: set[str] = set()
    union: list[Any] = []
    for value_list in values:
        for item in value_list:
            key = json.dumps(item, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
            if key in seen:
                continue
            seen.add(key)
            union.append(item)
    return union


def create_merge_conflict_report(
    repo_root: Path,
    args: MergeDriverArgs,
    *,
    conflicts: list[dict[str, str]] | None = None,
    appendable_unions: dict[str, list[Any]] | None = None,
) -> ConflictReportResult:
    conflict_id = f"conflict-{generate_ulid()}"
    kind = "memory_merge_conflict"
    similarity: dict[str, Any] = {
        "method": "not_evaluated",
        "score": None,
    }
    report_conflicts = conflicts or [
        {
            "field": "file",
            "reason": "merge_driver_safe_resolution_not_available",
        }
    ]
    if conflicts is None:
        semantic_similarity = semantic_similarity_conflict(args.ours, args.theirs)
        if semantic_similarity is not None:
            kind = "semantic_similarity"
            similarity = {
                "method": semantic_similarity.method,
                "score": semantic_similarity.score,
            }
            report_conflicts = [
                {
                    "field": "body",
                    "reason": "semantically_similar_memory",
                }
            ]
    report = {
        "schema_version": CONFLICT_SCHEMA_VERSION,
        "id": conflict_id,
        "created_at": format_timestamp(datetime.now(UTC)),
        "kind": kind,
        "severity": "review_required",
        "merge": {
            "base_ref": path_ref(args.base),
            "ours_ref": path_ref(args.ours),
            "theirs_ref": path_ref(args.theirs),
            "path": args.memory_path,
        },
        "memories": [
            memory_report_entry(repo_root, "base", args.base),
            memory_report_entry(repo_root, "ours", args.ours),
            memory_report_entry(repo_root, "theirs", args.theirs),
        ],
        "similarity": similarity,
        "conflicts": report_conflicts,
        "appendable_unions": appendable_unions or {"evidence": []},
        "proposed_resolution": None,
        "required_action": "human_review",
    }
    path = write_conflict_report(repo_root, report)
    return ConflictReportResult(report=report, path=path)


def write_conflict_report(repo_root: Path, report: dict[str, Any]) -> Path:
    root = conflicts_dir(repo_root)
    root.mkdir(parents=True, exist_ok=True)
    conflict_id = report.get("id")
    if not isinstance(conflict_id, str) or not conflict_id:
        raise BrickConflictError("conflict report requires a non-empty id")
    path = root / f"{safe_report_id(conflict_id)}.json"
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def conflict_path_for_id(repo_root: Path, report_id: str) -> Path:
    stem = Path(report_id).name
    if stem.endswith(".json"):
        stem = stem[:-5]
    return conflicts_dir(repo_root) / f"{safe_report_id(stem)}.json"


def safe_report_id(report_id: str) -> str:
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    if not report_id or any(character not in allowed for character in report_id):
        raise BrickConflictError(f"invalid conflict report id: {report_id}")
    return report_id


def conflict_summary(repo_root: Path, path: Path, report: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": report.get("id"),
        "path": relative_to_repo(repo_root, path),
        "created_at": report.get("created_at"),
        "kind": report.get("kind"),
        "severity": report.get("severity"),
        "required_action": report.get("required_action"),
        "memory_count": len(report.get("memories", [])) if isinstance(report.get("memories"), list) else 0,
    }


def read_json_file(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BrickConflictError(f"could not read conflict report {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise BrickConflictError(f"conflict report must be a JSON object: {path}")
    return payload


def validate_proposal_payload(proposal: dict[str, Any]) -> None:
    unknown_fields = sorted(set(proposal) - PROPOSAL_ALLOWED_FIELDS)
    if unknown_fields:
        raise BrickConflictError(
            f"proposal contains unknown fields: {', '.join(unknown_fields)}"
        )
    for field_name in ("summary", "memory_markdown"):
        value = proposal.get(field_name)
        if not isinstance(value, str) or not value.strip():
            raise BrickConflictError(
                f"proposal field {field_name} must be a non-empty string"
            )
    if "notes" in proposal and not isinstance(proposal["notes"], str):
        raise BrickConflictError("proposal field notes must be a string")


def validate_proposed_memory_markdown(markdown: str):
    try:
        frontmatter_text, body = split_frontmatter(markdown)
        document = MemoryDocument(
            path=Path("<proposed_resolution>"),
            frontmatter=parse_frontmatter(frontmatter_text),
            body=body,
            raw_text=markdown,
        )
    except MemoryParseError as exc:
        raise BrickConflictError(f"proposed memory markdown could not be parsed: {exc}") from exc
    return validate_memory(document)


def same_memory_content(ours: Path, theirs: Path) -> bool:
    try:
        ours_memory = load_memory(ours)
        theirs_memory = load_memory(theirs)
    except (OSError, UnicodeDecodeError, MemoryParseError):
        return False
    return (
        ours_memory.frontmatter.get("id") == theirs_memory.frontmatter.get("id")
        and ours_memory.frontmatter.get("content_hash") == theirs_memory.frontmatter.get("content_hash")
    )


def semantic_similarity_conflict(ours: Path, theirs: Path) -> SemanticSimilarity | None:
    try:
        ours_memory = load_memory(ours)
        theirs_memory = load_memory(theirs)
    except (OSError, UnicodeDecodeError, MemoryParseError):
        return None

    ours_id = ours_memory.frontmatter.get("id")
    theirs_id = theirs_memory.frontmatter.get("id")
    if (
        not isinstance(ours_id, str)
        or not isinstance(theirs_id, str)
        or ours_id == theirs_id
    ):
        return None

    ours_tokens = memory_semantic_tokens(ours_memory)
    theirs_tokens = memory_semantic_tokens(theirs_memory)
    if (
        len(ours_tokens) < SEMANTIC_SIMILARITY_MIN_TOKENS
        or len(theirs_tokens) < SEMANTIC_SIMILARITY_MIN_TOKENS
    ):
        return None

    score = jaccard_score(ours_tokens, theirs_tokens)
    if score < SEMANTIC_SIMILARITY_THRESHOLD:
        return None
    return SemanticSimilarity(method="keyword", score=round(score, 6))


def memory_semantic_tokens(document: MemoryDocument) -> set[str]:
    parts = [document.body]
    for key, value in document.frontmatter.items():
        if key in SEMANTIC_FRONTMATTER_EXCLUDED_FIELDS:
            continue
        parts.extend(iter_semantic_strings(value))
    tokens: set[str] = set()
    for part in parts:
        tokens.update(tokenize_semantic_text(part))
    return tokens


def iter_semantic_strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        strings: list[str] = []
        for item in value:
            strings.extend(iter_semantic_strings(item))
        return strings
    if isinstance(value, dict):
        strings = []
        for item in value.values():
            strings.extend(iter_semantic_strings(item))
        return strings
    return []


def tokenize_semantic_text(text: str) -> set[str]:
    tokens: set[str] = set()
    for match in TOKEN_PATTERN.finditer(text.lower()):
        token = normalize_token(match.group(0))
        if len(token) < 3 or token in SEMANTIC_STOP_WORDS:
            continue
        tokens.add(token)
    return tokens


def normalize_token(token: str) -> str:
    if len(token) > 4 and token.endswith("ies"):
        return f"{token[:-3]}y"
    if len(token) > 4 and token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def jaccard_score(left: set[str], right: set[str]) -> float:
    union = left | right
    if not union:
        return 0.0
    return len(left & right) / len(union)


def memory_report_entry(repo_root: Path, side: str, path: Path) -> dict[str, Any]:
    entry: dict[str, Any] = {
        "side": side,
        "path": path_ref(path, repo_root),
    }
    try:
        document = load_memory(path)
    except (OSError, UnicodeDecodeError, MemoryParseError) as exc:
        entry["parse_error"] = str(exc)
        return entry
    frontmatter = document.frontmatter
    for field_name in ("id", "title", "type", "status", "content_hash"):
        if field_name in frontmatter:
            entry[field_name] = frontmatter[field_name]
    return entry


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        raise BrickConflictError(f"could not read merge file {path}: {exc}") from exc


def path_ref(path: Path, repo_root: Path | None = None) -> str:
    if repo_root is not None:
        try:
            return relative_to_repo(repo_root, path)
        except ValueError:
            pass
    return str(path)


def relative_to_repo(repo_root: Path, path: Path) -> str:
    return str(path.resolve().relative_to(repo_root.resolve()))
