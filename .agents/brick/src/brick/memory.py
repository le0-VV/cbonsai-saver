from __future__ import annotations

import hashlib
import json
import re
import secrets
import time
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Iterable


ALLOWED_TYPES = {
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
}
ALLOWED_STATUSES = {"active", "superseded", "tombstone", "redacted"}
REDACTION_REPLACEMENT = "[REDACTED]"
ADD_ALLOWED_FIELDS = {
    "title",
    "type",
    "tags",
    "body",
    "source",
    "evidence",
    "confirm_public",
    "supersedes",
    "related",
    "fields",
    "status",
    "id",
    "created_at",
    "updated_at",
}
REDACT_ALLOWED_FIELDS = {"path", "redactions", "reason", "rebuild"}
COMMAND_FIELDS = {"command", "cwd", "when_to_use", "expected_output", "failure_notes"}
ROUTINE_SKILL_FIELDS = {"steps", "prerequisites", "verify"}
REQUIRED_FIELDS = {
    "id",
    "title",
    "type",
    "status",
    "tags",
    "created_at",
    "updated_at",
    "content_hash",
    "source",
    "evidence",
}
ULID_RE = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")
CONTENT_HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
CROCKFORD_BASE32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
REDACTION_SKIP_FRONTMATTER_KEYS = {
    "id",
    "type",
    "status",
    "created_at",
    "updated_at",
    "content_hash",
    "supersedes",
    "related",
}

SECRET_PATTERNS = (
    ("private_key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    (
        "credential_assignment",
        re.compile(
            r"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|token|secret|password)"
            r"\b\s*[:=]\s*['\"]?[A-Za-z0-9_./+=-]{12,}"
        ),
    ),
)
PII_PATTERNS = (
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
    ("phone", re.compile(r"\b(?:\+?\d[\d ()-]{7,}\d)\b")),
    (
        "address",
        re.compile(
            r"\b\d{1,6}\s+[A-Z][A-Za-z0-9.-]*"
            r"(?:\s+[A-Z][A-Za-z0-9.-]*){0,4}\s+"
            r"(?:Street|St|Road|Rd|Avenue|Ave|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct)\b"
        ),
    ),
    (
        "person_name",
        re.compile(
            r"(?i)\b(?:name|user|author|maintainer|contributor|person)\s*[:=]\s*"
            r"([A-Z][a-z]{1,}\s+[A-Z][a-z]{1,})\b"
        ),
    ),
)


class MemoryParseError(ValueError):
    pass


class MemoryAddError(ValueError):
    def __init__(
        self,
        message: str,
        *,
        code: str = "invalid_candidate",
        issues: list[ValidationIssue] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.issues = issues or [
            ValidationIssue(code=code, message=message),
        ]


@dataclass
class MemoryDocument:
    path: Path
    frontmatter: dict[str, Any]
    body: str
    raw_text: str


@dataclass
class ValidationIssue:
    code: str
    message: str
    field: str | None = None
    line: int | None = None
    kind: str | None = None
    expected: str | None = None

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "code": self.code,
            "message": self.message,
        }
        if self.field is not None:
            payload["field"] = self.field
        if self.line is not None:
            payload["line"] = self.line
        if self.kind is not None:
            payload["kind"] = self.kind
            payload["text"] = "[REDACTED]"
        if self.expected is not None:
            payload["expected"] = self.expected
        return payload


class MemoryRedactError(ValueError):
    def __init__(
        self,
        message: str,
        *,
        code: str = "invalid_redaction",
        issues: list[ValidationIssue] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.issues = issues or [
            ValidationIssue(code=code, message=message),
        ]


@dataclass
class ValidationResult:
    path: Path
    issues: list[ValidationIssue] = field(default_factory=list)
    expected_content_hash: str | None = None

    @property
    def status(self) -> str:
        if not self.issues:
            return "ok"
        if any(issue.code in {"secret_detected", "possible_pii"} for issue in self.issues):
            return "blocked"
        return "invalid"

    def to_dict(self, repo_root: Path | None = None) -> dict[str, Any]:
        path = self.path
        if repo_root is not None:
            try:
                path_text = str(path.resolve().relative_to(repo_root.resolve()))
            except ValueError:
                path_text = str(path)
        else:
            path_text = str(path)
        payload: dict[str, Any] = {
            "path": path_text,
            "status": self.status,
            "issues": [issue.to_dict() for issue in self.issues],
        }
        if self.expected_content_hash is not None:
            payload["expected_content_hash"] = self.expected_content_hash
        return payload


@dataclass
class AddMemoryResult:
    path: Path
    memory_id: str
    validation: ValidationResult

    def to_dict(self, repo_root: Path) -> dict[str, Any]:
        return {
            "status": "ok",
            "id": self.memory_id,
            "path": str(self.path.resolve().relative_to(repo_root.resolve())),
            "validation": self.validation.to_dict(repo_root),
        }


@dataclass
class RedactMemoryResult:
    path: Path
    memory_id: str
    validation: ValidationResult
    redaction_count: int
    replacement_count: int

    def to_dict(self, repo_root: Path) -> dict[str, Any]:
        return {
            "status": "ok",
            "id": self.memory_id,
            "path": str(self.path.resolve().relative_to(repo_root.resolve())),
            "redaction_count": self.redaction_count,
            "replacement_count": self.replacement_count,
            "validation": self.validation.to_dict(repo_root),
        }


def split_frontmatter(text: str) -> tuple[str, str]:
    normalized = text.replace("\r\n", "\n")
    lines = normalized.split("\n")
    if not lines or lines[0] != "---":
        raise MemoryParseError("memory file must start with YAML frontmatter delimiter")
    for index in range(1, len(lines)):
        if lines[index] == "---":
            return "\n".join(lines[1:index]), "\n".join(lines[index + 1 :])
    raise MemoryParseError("memory file is missing closing YAML frontmatter delimiter")


def parse_frontmatter(frontmatter: str) -> dict[str, Any]:
    raw_lines = frontmatter.split("\n")
    lines: list[tuple[int, str, int]] = []
    for line_number, raw in enumerate(raw_lines, start=2):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if "\t" in raw:
            raise MemoryParseError(f"tabs are not supported in frontmatter at line {line_number}")
        indent = len(raw) - len(raw.lstrip(" "))
        lines.append((indent, raw.strip(), line_number))
    if not lines:
        return {}
    parsed, next_index = parse_block(lines, 0, lines[0][0])
    if next_index != len(lines):
        raise MemoryParseError(f"unexpected frontmatter content at line {lines[next_index][2]}")
    if not isinstance(parsed, dict):
        raise MemoryParseError("frontmatter root must be a mapping")
    return parsed


def parse_block(
    lines: list[tuple[int, str, int]],
    index: int,
    indent: int,
) -> tuple[Any, int]:
    if index >= len(lines):
        return {}, index
    current_indent, content, _line_number = lines[index]
    if current_indent < indent:
        return {}, index
    if current_indent > indent:
        raise MemoryParseError(f"unexpected indentation at line {lines[index][2]}")
    if content == "-" or content.startswith("- "):
        return parse_list(lines, index, indent)
    return parse_mapping(lines, index, indent)


def parse_mapping(
    lines: list[tuple[int, str, int]],
    index: int,
    indent: int,
) -> tuple[dict[str, Any], int]:
    mapping: dict[str, Any] = {}
    while index < len(lines):
        current_indent, content, line_number = lines[index]
        if current_indent < indent:
            break
        if current_indent > indent:
            raise MemoryParseError(f"unexpected indentation at line {line_number}")
        if content == "-" or content.startswith("- "):
            break
        key, value_text = split_key_value(content, line_number)
        if key in mapping:
            raise MemoryParseError(f"duplicate key {key!r} at line {line_number}")
        index += 1
        if value_text == "":
            if index < len(lines) and lines[index][0] > current_indent:
                value, index = parse_block(lines, index, lines[index][0])
            else:
                value = {}
        else:
            value = parse_scalar(value_text, line_number)
        mapping[key] = value
    return mapping, index


def parse_list(
    lines: list[tuple[int, str, int]],
    index: int,
    indent: int,
) -> tuple[list[Any], int]:
    items: list[Any] = []
    while index < len(lines):
        current_indent, content, line_number = lines[index]
        if current_indent < indent:
            break
        if current_indent > indent:
            raise MemoryParseError(f"unexpected indentation at line {line_number}")
        if content != "-" and not content.startswith("- "):
            break
        item_text = "" if content == "-" else content[2:].strip()
        index += 1
        if item_text == "":
            if index < len(lines) and lines[index][0] > current_indent:
                item, index = parse_block(lines, index, lines[index][0])
            else:
                item = None
        elif ":" in item_text and not is_quoted(item_text):
            key, value_text = split_key_value(item_text, line_number)
            item = {key: parse_scalar(value_text, line_number) if value_text else {}}
            if index < len(lines) and lines[index][0] > current_indent:
                extra, index = parse_block(lines, index, lines[index][0])
                if isinstance(extra, dict):
                    item.update(extra)
                else:
                    raise MemoryParseError(f"list item mapping expected at line {line_number}")
        else:
            item = parse_scalar(item_text, line_number)
        items.append(item)
    return items, index


def split_key_value(content: str, line_number: int) -> tuple[str, str]:
    if ":" not in content:
        raise MemoryParseError(f"expected key/value pair at line {line_number}")
    key, value = content.split(":", 1)
    key = key.strip()
    if not key:
        raise MemoryParseError(f"empty key at line {line_number}")
    return key, value.strip()


def parse_scalar(value: str, line_number: int) -> Any:
    if value == "[]":
        return []
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(part.strip(), line_number) for part in inner.split(",")]
    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered in {"null", "~"}:
        return None
    if is_quoted(value):
        quote = value[0]
        body = value[1:-1]
        if quote == '"':
            try:
                return json.loads(value)
            except json.JSONDecodeError as exc:
                raise MemoryParseError(f"invalid quoted string at line {line_number}") from exc
        return body.replace("''", "'")
    return value


def is_quoted(value: str) -> bool:
    return len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}


def load_memory(path: Path) -> MemoryDocument:
    raw_text = path.read_text(encoding="utf-8")
    frontmatter_text, body = split_frontmatter(raw_text)
    frontmatter = parse_frontmatter(frontmatter_text)
    return MemoryDocument(path=path, frontmatter=frontmatter, body=body, raw_text=raw_text)


def normalize_body(body: str) -> str:
    lines = body.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    normalized = "\n".join(line.rstrip() for line in lines).rstrip()
    return f"{normalized}\n" if normalized else ""


def canonical_frontmatter(frontmatter: dict[str, Any]) -> dict[str, Any]:
    return {
        key: value
        for key, value in frontmatter.items()
        if key not in {"content_hash", "updated_at"}
    }


def compute_content_hash(frontmatter: dict[str, Any], body: str) -> str:
    payload = {
        "frontmatter": canonical_frontmatter(frontmatter),
        "body": normalize_body(body),
    }
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def create_memory_from_candidate(
    repo_root: Path,
    candidate: dict[str, Any],
    *,
    now: datetime | None = None,
) -> AddMemoryResult:
    frontmatter, body = build_memory_frontmatter(candidate, now=now)
    text = render_memory_text(frontmatter, body)
    document = MemoryDocument(
        path=memory_path_for_frontmatter(repo_root, frontmatter),
        frontmatter=frontmatter,
        body=body,
        raw_text=text,
    )
    validation = validate_memory(document)
    if validation.status != "ok":
        raise MemoryAddError(
            "candidate memory did not pass validation",
            code=validation.status,
            issues=validation.issues,
        )
    path = document.path
    if path.exists():
        raise MemoryAddError(
            f"memory file already exists: {path}",
            code="memory_exists",
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return AddMemoryResult(path=path, memory_id=frontmatter["id"], validation=validation)


def redact_memory_from_candidate(
    repo_root: Path,
    candidate: dict[str, Any],
    *,
    now: datetime | None = None,
) -> RedactMemoryResult:
    validate_redaction_candidate_shape(candidate)
    path = resolve_memory_path(repo_root, candidate["path"])
    try:
        document = load_memory(path)
    except (OSError, UnicodeDecodeError, MemoryParseError) as exc:
        raise MemoryRedactError(
            f"could not load memory for redaction: {exc}",
            code="memory_load_failed",
        ) from exc

    frontmatter = clone_json_value(document.frontmatter)
    if not isinstance(frontmatter, dict):
        raise MemoryRedactError("memory frontmatter must be a mapping")
    body = document.body
    replacement_count = 0
    for target in candidate["redactions"]:
        frontmatter, frontmatter_count = redact_frontmatter_value(frontmatter, target)
        body_count = body.count(target)
        body = body.replace(target, REDACTION_REPLACEMENT)
        replacement_count += frontmatter_count + body_count

    if replacement_count == 0:
        raise MemoryRedactError(
            "none of the requested redaction text values were found",
            code="redaction_text_not_found",
            issues=[
                ValidationIssue(
                    code="redaction_text_not_found",
                    message="none of the requested redaction text values were found",
                    field="redactions",
                )
            ],
        )

    evidence = frontmatter.get("evidence")
    if not isinstance(evidence, list):
        raise MemoryRedactError(
            "memory evidence must be a list before redaction",
            code="invalid_existing_memory",
            issues=[
                ValidationIssue(
                    code="invalid_field_type",
                    message="evidence must be a list before redaction",
                    field="evidence",
                )
            ],
        )
    frontmatter["status"] = "redacted"
    frontmatter["updated_at"] = format_timestamp(now or datetime.now(UTC))
    evidence.append({"kind": "redaction", "text": candidate["reason"]})
    frontmatter["evidence"] = evidence
    frontmatter["content_hash"] = compute_content_hash(frontmatter, body)
    text = render_memory_text(frontmatter, body)
    redacted_document = MemoryDocument(
        path=path,
        frontmatter=frontmatter,
        body=body,
        raw_text=text,
    )
    validation = validate_memory(redacted_document)
    if validation.status != "ok":
        raise MemoryRedactError(
            "redacted memory did not pass validation",
            code=validation.status,
            issues=validation.issues,
        )

    path.write_text(text, encoding="utf-8")
    return RedactMemoryResult(
        path=path,
        memory_id=frontmatter["id"],
        validation=validation,
        redaction_count=len(candidate["redactions"]),
        replacement_count=replacement_count,
    )


def build_memory_frontmatter(
    candidate: dict[str, Any],
    *,
    now: datetime | None = None,
) -> tuple[dict[str, Any], str]:
    validate_candidate_shape(candidate)
    timestamp = format_timestamp(now or datetime.now(UTC))
    memory_type = candidate["type"]
    status = candidate.get("status", "active")
    memory_id = candidate.get("id") or generate_ulid()
    created_at = candidate.get("created_at") or timestamp
    updated_at = candidate.get("updated_at") or created_at
    body = normalize_body(candidate["body"])

    frontmatter: dict[str, Any] = {
        "id": memory_id,
        "title": candidate["title"],
        "type": memory_type,
        "status": status,
        "tags": candidate["tags"],
        "created_at": created_at,
        "updated_at": updated_at,
        "source": candidate["source"],
        "evidence": candidate["evidence"],
    }
    if candidate.get("confirm_public") is True:
        frontmatter["confirm_public"] = True
    if "supersedes" in candidate:
        frontmatter["supersedes"] = candidate["supersedes"]
    if "related" in candidate:
        frontmatter["related"] = candidate["related"]

    fields = candidate.get("fields", {})
    for key in sorted(fields):
        frontmatter[key] = fields[key]

    return storage_frontmatter(frontmatter, body), body


def storage_frontmatter(frontmatter: dict[str, Any], body: str) -> dict[str, Any]:
    normalized = clone_json_value(frontmatter)
    if not isinstance(normalized, dict):
        raise MemoryAddError("memory frontmatter must be a mapping")
    normalized.pop("content_hash", None)
    text = render_memory_text(normalized, body)
    parsed = parse_frontmatter(split_frontmatter(text)[0])
    parsed["content_hash"] = compute_content_hash(parsed, body)
    return parsed


def validate_candidate_shape(candidate: dict[str, Any]) -> None:
    issues: list[ValidationIssue] = []
    unknown_fields = sorted(set(candidate) - ADD_ALLOWED_FIELDS)
    for field_name in unknown_fields:
        issues.append(
            ValidationIssue(
                code="unknown_field",
                message=f"unknown top-level field {field_name}",
                field=field_name,
            )
        )

    for field_name in ("title", "type", "tags", "body", "source", "evidence"):
        if field_name not in candidate:
            issues.append(
                ValidationIssue(
                    code="missing_required_field",
                    message=f"missing required candidate field {field_name}",
                    field=field_name,
                )
            )

    if "title" in candidate and not isinstance(candidate["title"], str):
        issues.append(invalid_candidate_type("title", "string"))
    if "type" in candidate:
        if not isinstance(candidate["type"], str):
            issues.append(invalid_candidate_type("type", "string"))
        elif candidate["type"] not in ALLOWED_TYPES:
            issues.append(ValidationIssue(code="invalid_type", message="type is not allowed", field="type"))
    if "status" in candidate:
        if not isinstance(candidate["status"], str):
            issues.append(invalid_candidate_type("status", "string"))
        elif candidate["status"] not in ALLOWED_STATUSES:
            issues.append(
                ValidationIssue(code="invalid_status", message="status is not allowed", field="status")
            )
    if "tags" in candidate and not is_string_list(candidate["tags"]):
        issues.append(invalid_candidate_type("tags", "list of strings"))
    if "body" in candidate and not isinstance(candidate["body"], str):
        issues.append(invalid_candidate_type("body", "string"))
    if "source" in candidate:
        if not isinstance(candidate["source"], dict):
            issues.append(invalid_candidate_type("source", "mapping"))
        elif not isinstance(candidate["source"].get("kind"), str) or not candidate["source"].get("kind"):
            issues.append(
                ValidationIssue(
                    code="missing_required_field",
                    message="source.kind is required",
                    field="source.kind",
                )
            )
    if "evidence" in candidate and not valid_evidence_candidate(candidate["evidence"]):
        issues.append(
            ValidationIssue(
                code="missing_evidence",
                message="evidence must contain at least one non-empty string or mapping",
                field="evidence",
            )
        )
    if "confirm_public" in candidate and not isinstance(candidate["confirm_public"], bool):
        issues.append(invalid_candidate_type("confirm_public", "boolean"))
    for field_name in ("supersedes", "related"):
        if field_name in candidate and not valid_ulid_candidate_list(candidate[field_name]):
            issues.append(
                ValidationIssue(
                    code="invalid_ulid",
                    message=f"{field_name} must be a list of plain uppercase ULIDs",
                    field=field_name,
                )
            )
    for field_name in ("id",):
        if field_name in candidate:
            if not isinstance(candidate[field_name], str):
                issues.append(invalid_candidate_type(field_name, "string"))
            elif not ULID_RE.fullmatch(candidate[field_name]):
                issues.append(
                    ValidationIssue(
                        code="invalid_ulid",
                        message=f"{field_name} must be a plain uppercase ULID",
                        field=field_name,
                    )
                )
    for field_name in ("created_at", "updated_at"):
        if field_name in candidate and not isinstance(candidate[field_name], str):
            issues.append(invalid_candidate_type(field_name, "string"))

    validate_candidate_fields(candidate, issues)
    if issues:
        raise MemoryAddError("invalid memory candidate", issues=issues)


def validate_redaction_candidate_shape(candidate: dict[str, Any]) -> None:
    issues: list[ValidationIssue] = []
    unknown_fields = sorted(set(candidate) - REDACT_ALLOWED_FIELDS)
    for field_name in unknown_fields:
        issues.append(
            ValidationIssue(
                code="unknown_field",
                message=f"unknown top-level field {field_name}",
                field=field_name,
            )
        )

    for field_name in ("path", "redactions", "reason"):
        if field_name not in candidate:
            issues.append(
                ValidationIssue(
                    code="missing_required_field",
                    message=f"missing required redaction field {field_name}",
                    field=field_name,
                )
            )

    if "path" in candidate:
        if not isinstance(candidate["path"], str):
            issues.append(invalid_candidate_type("path", "string"))
        elif not candidate["path"].strip():
            issues.append(
                ValidationIssue(
                    code="empty_field",
                    message="path must not be empty",
                    field="path",
                )
            )
    if "redactions" in candidate:
        redactions = candidate["redactions"]
        if not isinstance(redactions, list) or not redactions:
            issues.append(
                invalid_candidate_type("redactions", "non-empty list of strings")
            )
        elif not all(isinstance(item, str) and item for item in redactions):
            issues.append(
                invalid_candidate_type("redactions", "non-empty list of strings")
            )
    if "reason" in candidate:
        if not isinstance(candidate["reason"], str):
            issues.append(invalid_candidate_type("reason", "string"))
        elif not candidate["reason"].strip():
            issues.append(
                ValidationIssue(
                    code="empty_field",
                    message="reason must not be empty",
                    field="reason",
                )
            )
    if "rebuild" in candidate and not isinstance(candidate["rebuild"], bool):
        issues.append(invalid_candidate_type("rebuild", "boolean"))

    if issues:
        raise MemoryRedactError("invalid redaction candidate", issues=issues)


def resolve_memory_path(repo_root: Path, path_text: str) -> Path:
    repo_root = repo_root.resolve()
    path = Path(path_text)
    if not path.is_absolute():
        path = repo_root / path
    path = path.resolve()
    try:
        relative = path.relative_to(repo_root)
    except ValueError as exc:
        raise MemoryRedactError(
            "redaction path must stay inside the repository",
            code="path_outside_repo",
            issues=[
                ValidationIssue(
                    code="path_outside_repo",
                    message="redaction path must stay inside the repository",
                    field="path",
                )
            ],
        ) from exc
    if relative.parts[:2] != (".agents", "memory") or path.suffix != ".md":
        raise MemoryRedactError(
            "redaction path must point to a canonical memory Markdown file",
            code="invalid_memory_path",
            issues=[
                ValidationIssue(
                    code="invalid_memory_path",
                    message="redaction path must point under .agents/memory/ and end in .md",
                    field="path",
                )
            ],
        )
    if not path.is_file():
        raise MemoryRedactError(
            f"memory file does not exist: {path}",
            code="memory_not_found",
            issues=[
                ValidationIssue(
                    code="memory_not_found",
                    message="memory file does not exist",
                    field="path",
                )
            ],
        )
    return path


def clone_json_value(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: clone_json_value(child) for key, child in value.items()}
    if isinstance(value, list):
        return [clone_json_value(item) for item in value]
    return value


def redact_frontmatter_value(
    value: Any,
    target: str,
    key: str | None = None,
) -> tuple[Any, int]:
    if key in REDACTION_SKIP_FRONTMATTER_KEYS:
        return value, 0
    if isinstance(value, str):
        return value.replace(target, REDACTION_REPLACEMENT), value.count(target)
    if isinstance(value, list):
        redacted_items = []
        replacement_count = 0
        for item in value:
            redacted_item, item_count = redact_frontmatter_value(item, target)
            redacted_items.append(redacted_item)
            replacement_count += item_count
        return redacted_items, replacement_count
    if isinstance(value, dict):
        redacted_mapping = {}
        replacement_count = 0
        for child_key, child_value in value.items():
            redacted_child, child_count = redact_frontmatter_value(
                child_value,
                target,
                child_key,
            )
            redacted_mapping[child_key] = redacted_child
            replacement_count += child_count
        return redacted_mapping, replacement_count
    return value, 0


def validate_candidate_fields(candidate: dict[str, Any], issues: list[ValidationIssue]) -> None:
    fields = candidate.get("fields", {})
    if not isinstance(fields, dict):
        issues.append(invalid_candidate_type("fields", "mapping"))
        return
    memory_type = candidate.get("type")
    allowed_fields: set[str]
    if memory_type == "command":
        allowed_fields = COMMAND_FIELDS
    elif memory_type in {"routine", "skill"}:
        allowed_fields = ROUTINE_SKILL_FIELDS
    else:
        allowed_fields = set()
    for field_name in sorted(set(fields) - allowed_fields):
        issues.append(
            ValidationIssue(
                code="unknown_field",
                message=f"{memory_type} memory does not allow field {field_name}",
                field=f"fields.{field_name}",
            )
        )
    if memory_type == "command":
        for field_name, value in fields.items():
            if not isinstance(value, str):
                issues.append(invalid_candidate_type(f"fields.{field_name}", "string"))
    elif memory_type in {"routine", "skill"}:
        for field_name in ("steps", "prerequisites"):
            if field_name in fields and not is_string_list(fields[field_name]):
                issues.append(invalid_candidate_type(f"fields.{field_name}", "list of strings"))
        if "verify" in fields and not isinstance(fields["verify"], str):
            issues.append(invalid_candidate_type("fields.verify", "string"))


def invalid_candidate_type(field_name: str, expected: str) -> ValidationIssue:
    return ValidationIssue(
        code="invalid_field_type",
        message=f"{field_name} must be {expected}",
        field=field_name,
    )


def is_string_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def valid_evidence_candidate(value: Any) -> bool:
    if not isinstance(value, list) or not value:
        return False
    for item in value:
        if isinstance(item, str) and item.strip():
            continue
        if isinstance(item, dict) and any(str(item_value).strip() for item_value in item.values()):
            continue
        return False
    return True


def valid_ulid_candidate_list(value: Any) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) and ULID_RE.fullmatch(item) for item in value)


def memory_path_for_frontmatter(repo_root: Path, frontmatter: dict[str, Any]) -> Path:
    slug = slugify(frontmatter["title"])
    return repo_root / ".agents/memory" / frontmatter["type"] / f"{frontmatter['id']}-{slug}.md"


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    slug = re.sub(r"-{2,}", "-", slug)
    return slug[:80].strip("-") or "memory"


def format_timestamp(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def render_memory_text(frontmatter: dict[str, Any], body: str) -> str:
    lines = ["---"]
    for key, value in frontmatter.items():
        append_yaml(lines, key, value, 0)
    lines.append("---")
    lines.append(normalize_body(body).rstrip())
    lines.append("")
    return "\n".join(lines)


def append_yaml(lines: list[str], key: str, value: Any, indent: int) -> None:
    prefix = " " * indent
    if isinstance(value, dict):
        lines.append(f"{prefix}{key}:")
        for child_key, child_value in value.items():
            append_yaml(lines, child_key, child_value, indent + 2)
    elif isinstance(value, list):
        if not value:
            lines.append(f"{prefix}{key}: []")
            return
        lines.append(f"{prefix}{key}:")
        for item in value:
            item_prefix = " " * (indent + 2)
            if isinstance(item, dict):
                lines.append(f"{item_prefix}-")
                for child_key, child_value in item.items():
                    append_yaml(lines, child_key, child_value, indent + 4)
            else:
                lines.append(f"{item_prefix}- {json.dumps(item, ensure_ascii=False)}")
    elif isinstance(value, bool):
        lines.append(f"{prefix}{key}: {'true' if value else 'false'}")
    else:
        lines.append(f"{prefix}{key}: {json.dumps(value, ensure_ascii=False)}")


def validate_memory(document: MemoryDocument) -> ValidationResult:
    result = ValidationResult(path=document.path)
    frontmatter = document.frontmatter

    for field_name in sorted(REQUIRED_FIELDS):
        if field_name not in frontmatter:
            result.issues.append(
                ValidationIssue(
                    code="missing_required_field",
                    message=f"missing required field {field_name}",
                    field=field_name,
                )
            )

    validate_scalar_string(result, frontmatter, "id")
    if isinstance(frontmatter.get("id"), str) and not ULID_RE.fullmatch(frontmatter["id"]):
        result.issues.append(
            ValidationIssue(code="invalid_ulid", message="id must be a plain uppercase ULID", field="id")
        )

    validate_scalar_string(result, frontmatter, "title")
    validate_scalar_string(result, frontmatter, "type")
    if isinstance(frontmatter.get("type"), str) and frontmatter["type"] not in ALLOWED_TYPES:
        result.issues.append(
            ValidationIssue(code="invalid_type", message="type is not allowed", field="type")
        )

    validate_scalar_string(result, frontmatter, "status")
    if isinstance(frontmatter.get("status"), str) and frontmatter["status"] not in ALLOWED_STATUSES:
        result.issues.append(
            ValidationIssue(code="invalid_status", message="status is not allowed", field="status")
        )
    validate_durable_confidence(result, frontmatter)

    validate_string_list(result, frontmatter, "tags")
    validate_timestamp(result, frontmatter, "created_at")
    validate_timestamp(result, frontmatter, "updated_at")
    validate_content_hash(result, document)
    validate_source(result, frontmatter)
    validate_evidence(result, frontmatter)
    validate_ulid_list(result, frontmatter, "supersedes")
    validate_ulid_list(result, frontmatter, "related")
    scan_safety(result, document)
    return result


def validate_scalar_string(
    result: ValidationResult,
    frontmatter: dict[str, Any],
    field_name: str,
) -> None:
    if field_name in frontmatter and not isinstance(frontmatter[field_name], str):
        result.issues.append(
            ValidationIssue(
                code="invalid_field_type",
                message=f"{field_name} must be a string",
                field=field_name,
            )
        )


def validate_string_list(
    result: ValidationResult,
    frontmatter: dict[str, Any],
    field_name: str,
) -> None:
    if field_name not in frontmatter:
        return
    value = frontmatter[field_name]
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        result.issues.append(
            ValidationIssue(
                code="invalid_field_type",
                message=f"{field_name} must be a list of strings",
                field=field_name,
            )
        )


def validate_timestamp(
    result: ValidationResult,
    frontmatter: dict[str, Any],
    field_name: str,
) -> None:
    if field_name not in frontmatter or not isinstance(frontmatter[field_name], str):
        return
    value = frontmatter[field_name]
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        result.issues.append(
            ValidationIssue(
                code="invalid_timestamp",
                message=f"{field_name} must be an ISO 8601 timestamp",
                field=field_name,
            )
        )


def validate_durable_confidence(result: ValidationResult, frontmatter: dict[str, Any]) -> None:
    confidence = frontmatter.get("confidence")
    if not isinstance(confidence, str):
        return
    if confidence.lower() in {"low", "medium", "uncertain", "unverified", "unsupported"}:
        result.issues.append(
            ValidationIssue(
                code="unsupported_durable_memory",
                message="low-confidence memory must be clarified or rejected before it is durable",
                field="confidence",
            )
        )


def validate_content_hash(result: ValidationResult, document: MemoryDocument) -> None:
    value = document.frontmatter.get("content_hash")
    if not isinstance(value, str):
        return
    expected = compute_content_hash(document.frontmatter, document.body)
    result.expected_content_hash = expected
    if not CONTENT_HASH_RE.fullmatch(value):
        result.issues.append(
            ValidationIssue(
                code="invalid_content_hash",
                message="content_hash must be sha256:<64 lowercase hex characters>",
                field="content_hash",
                expected=expected,
            )
        )
    elif value != expected:
        result.issues.append(
            ValidationIssue(
                code="content_hash_mismatch",
                message="content_hash does not match normalized memory content",
                field="content_hash",
                expected=expected,
            )
        )


def validate_source(result: ValidationResult, frontmatter: dict[str, Any]) -> None:
    source = frontmatter.get("source")
    if source is None:
        return
    if not isinstance(source, dict):
        result.issues.append(
            ValidationIssue(code="invalid_field_type", message="source must be a mapping", field="source")
        )
        return
    kind = source.get("kind")
    if not isinstance(kind, str) or not kind:
        result.issues.append(
            ValidationIssue(
                code="missing_required_field",
                message="source.kind is required",
                field="source.kind",
            )
        )


def validate_evidence(result: ValidationResult, frontmatter: dict[str, Any]) -> None:
    evidence = frontmatter.get("evidence")
    if evidence is None:
        return
    if not isinstance(evidence, list) or not evidence:
        result.issues.append(
            ValidationIssue(
                code="missing_evidence",
                message="evidence must contain at least one item",
                field="evidence",
            )
        )
        return
    for item in evidence:
        if isinstance(item, str) and item.strip():
            continue
        if isinstance(item, dict) and any(str(value).strip() for value in item.values()):
            continue
        result.issues.append(
            ValidationIssue(
                code="missing_evidence",
                message="evidence items must be non-empty strings or mappings",
                field="evidence",
            )
        )
        break


def validate_ulid_list(
    result: ValidationResult,
    frontmatter: dict[str, Any],
    field_name: str,
) -> None:
    if field_name not in frontmatter:
        return
    value = frontmatter[field_name]
    if not isinstance(value, list):
        result.issues.append(
            ValidationIssue(
                code="invalid_field_type",
                message=f"{field_name} must be a list of ULIDs",
                field=field_name,
            )
        )
        return
    for item in value:
        if not isinstance(item, str) or not ULID_RE.fullmatch(item):
            result.issues.append(
                ValidationIssue(
                    code="invalid_ulid",
                    message=f"{field_name} entries must be plain uppercase ULIDs",
                    field=field_name,
                )
            )
            return


def scan_safety(result: ValidationResult, document: MemoryDocument) -> None:
    scan_text = "\n".join(iter_safety_strings(document))
    for kind, pattern in SECRET_PATTERNS:
        for match in pattern.finditer(scan_text):
            result.issues.append(
                ValidationIssue(
                    code="secret_detected",
                    message=f"blocked likely secret: {kind}",
                    kind=kind,
                    line=line_number_for_match(document.raw_text, match.group(0)),
                )
            )
    if document.frontmatter.get("confirm_public") is True:
        return
    for kind, pattern in PII_PATTERNS:
        for match in pattern.finditer(scan_text):
            result.issues.append(
                ValidationIssue(
                    code="possible_pii",
                    message=f"blocked possible PII: {kind}",
                    kind=kind,
                    line=line_number_for_match(document.raw_text, match.group(0)),
                )
            )


def iter_safety_strings(document: MemoryDocument) -> Iterable[str]:
    yield document.body
    yield from iter_frontmatter_safety_strings(document.frontmatter)


def iter_frontmatter_safety_strings(value: Any, key: str | None = None) -> Iterable[str]:
    skipped_keys = {
        "id",
        "type",
        "status",
        "tags",
        "created_at",
        "updated_at",
        "content_hash",
        "supersedes",
        "related",
        "confirm_public",
    }
    if key in skipped_keys:
        return
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from iter_frontmatter_safety_strings(item)
    elif isinstance(value, dict):
        for child_key, child_value in value.items():
            yield from iter_frontmatter_safety_strings(child_value, child_key)


def line_number_for_match(text: str, matched_text: str) -> int | None:
    offset = text.find(matched_text)
    if offset < 0:
        return None
    return text.count("\n", 0, offset) + 1


def validate_memory_file(path: Path) -> ValidationResult:
    try:
        document = load_memory(path)
    except (OSError, UnicodeDecodeError, MemoryParseError) as exc:
        return ValidationResult(
            path=path,
            issues=[
                ValidationIssue(
                    code="parse_error",
                    message=str(exc),
                )
            ],
        )
    return validate_memory(document)


def discover_memory_files(repo_root: Path, path_arg: str | None = None) -> list[Path]:
    if path_arg is None:
        root = repo_root / ".agents/memory"
        if not root.exists():
            return []
        return sorted(path for path in root.rglob("*.md") if path.is_file())

    path = Path(path_arg)
    if not path.is_absolute():
        path = Path.cwd() / path
    path = path.resolve()
    if path.is_file():
        return [path]
    if path.is_dir():
        return sorted(candidate for candidate in path.rglob("*.md") if candidate.is_file())
    raise MemoryParseError(f"validation path does not exist: {path}")


def validate_memory_paths(repo_root: Path, paths: Iterable[Path]) -> list[ValidationResult]:
    return [validate_memory_file(path) for path in paths]


def generate_ulid(timestamp_ms: int | None = None) -> str:
    timestamp = int(time.time() * 1000) if timestamp_ms is None else timestamp_ms
    if timestamp < 0 or timestamp >= 2**48:
        raise ValueError("ULID timestamp must fit in 48 bits")
    value = (timestamp << 80) | secrets.randbits(80)
    return encode_crockford_base32(value, 26)


def encode_crockford_base32(value: int, length: int) -> str:
    chars = []
    for _ in range(length):
        chars.append(CROCKFORD_BASE32[value & 0b11111])
        value >>= 5
    if value:
        raise ValueError("value does not fit in requested Crockford base32 length")
    return "".join(reversed(chars))
