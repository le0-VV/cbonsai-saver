from __future__ import annotations

import http.client
import json
import math
import os
import re
import sqlite3
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Mapping

from brick.memory import (
    MemoryDocument,
    ValidationResult,
    discover_memory_files,
    format_timestamp,
    load_memory,
    normalize_body,
    validate_memory_paths,
)


INDEX_SCHEMA_VERSION = 2
INDEX_RELATIVE_PATH = Path(".agents/brick/index/brick.sqlite3")
LOCAL_CONFIG_RELATIVE_PATH = Path(".agents/brick/config.local.json")
EMBEDDING_URL_FIELD = "embedding.url"
EMBEDDING_MODEL_FIELD = "embedding.model"
EMBEDDING_API_KEY_ENV_VAR = "BRICK_EMBEDDING_API_KEY"
EMBEDDING_TIMEOUT_SECONDS = 30
HYBRID_SEMANTIC_WEIGHT = 20.0
TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9_-]*")
MAX_SUMMARY_LENGTH = 240


class BrickIndexError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        code: str = "index_error",
        payload: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.payload = payload

    def to_dict(self) -> dict[str, Any]:
        if self.payload is not None:
            return self.payload
        return {
            "status": "error",
            "reason": self.code,
            "message": str(self),
        }


class EmbeddingError(RuntimeError):
    def __init__(self, reason: str, message: str) -> None:
        super().__init__(message)
        self.reason = reason


@dataclass(frozen=True)
class EmbeddingConfig:
    endpoint_url: str
    model: str
    api_key: str | None = None


@dataclass(frozen=True)
class LocalEmbeddingConfig:
    url: str = ""
    model: str = ""
    api_key_env: str = EMBEDDING_API_KEY_ENV_VAR


@dataclass(frozen=True)
class EmbeddingSettings:
    raw_url: str
    model: str
    api_key_env: str
    api_key: str | None


@dataclass
class RebuildResult:
    path: Path
    rebuilt_at: str
    memory_count: int
    validation_results: list[ValidationResult]
    embedding_count: int = 0
    embedding_model: str | None = None
    embedding_dimensions: int | None = None

    def to_dict(self, repo_root: Path) -> dict[str, Any]:
        index: dict[str, Any] = {
            "path": relative_to_repo(repo_root, self.path),
            "schema_version": INDEX_SCHEMA_VERSION,
            "rebuilt_at": self.rebuilt_at,
            "memory_count": self.memory_count,
            "embedding_count": self.embedding_count,
        }
        if self.embedding_model is not None:
            index["embedding_model"] = self.embedding_model
        if self.embedding_dimensions is not None:
            index["embedding_dimensions"] = self.embedding_dimensions
        return {
            "status": "ok",
            "index": index,
            "checked": len(self.validation_results),
            "results": [result.to_dict(repo_root) for result in self.validation_results],
        }


def index_path(repo_root: Path) -> Path:
    return repo_root / INDEX_RELATIVE_PATH


def rebuild_index(
    repo_root: Path,
    *,
    now: datetime | None = None,
    env: Mapping[str, str] | None = None,
) -> RebuildResult:
    repo_root = repo_root.resolve()
    env = os.environ if env is None else env
    paths = discover_memory_files(repo_root)
    validation_results = validate_memory_paths(repo_root, paths)
    validation_status = aggregate_validation_status(validation_results)
    if validation_status != "ok":
        raise BrickIndexError(
            "memory validation failed",
            code="memory_validation_failed",
            payload={
                "status": validation_status,
                "reason": "memory_validation_failed",
                "checked": len(validation_results),
                "results": [result.to_dict(repo_root) for result in validation_results],
            },
        )

    documents = [load_memory(path) for path in paths]
    memory_rows = [memory_row(repo_root, document) for document in documents]
    embedding_config = configured_embedding(repo_root, env)
    embedding_vectors: list[list[float]] = []
    embedding_dimensions: int | None = None
    if embedding_config is not None and memory_rows:
        try:
            embedding_vectors = request_embeddings(
                embedding_config,
                [row["search_text"] for row in memory_rows],
            )
            embedding_dimensions = validate_embedding_dimensions(embedding_vectors)
        except EmbeddingError as exc:
            raise BrickIndexError(
                str(exc),
                code=exc.reason,
                payload={
                    "status": "error",
                    "reason": exc.reason,
                    "message": str(exc),
                },
            ) from exc

    rebuilt_at = format_timestamp(now or datetime.now(UTC))
    target = index_path(repo_root)
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise index_write_error(repo_root, target, exc) from exc
    temporary = target.with_name(f".{target.name}.{os.getpid()}.tmp")
    try:
        if temporary.exists():
            temporary.unlink()
    except OSError as exc:
        raise index_write_error(repo_root, target, exc) from exc

    try:
        connection = sqlite3.connect(temporary)
        try:
            initialize_schema(connection)
            for row in memory_rows:
                insert_memory(connection, row)
            if embedding_config is not None:
                for row, vector in zip(memory_rows, embedding_vectors, strict=True):
                    insert_embedding(connection, row, embedding_config, vector)
            write_metadata(
                connection,
                rebuilt_at,
                len(memory_rows),
                embedding_count=len(embedding_vectors),
                embedding_model=embedding_config.model if embedding_config else None,
                embedding_dimensions=embedding_dimensions,
            )
            connection.commit()
        finally:
            connection.close()
        os.replace(temporary, target)
    except sqlite3.Error as exc:
        raise index_write_error(repo_root, target, exc) from exc
    except OSError as exc:
        raise index_write_error(repo_root, target, exc) from exc
    finally:
        try:
            if temporary.exists():
                temporary.unlink()
        except OSError:
            pass

    return RebuildResult(
        path=target,
        rebuilt_at=rebuilt_at,
        memory_count=len(memory_rows),
        validation_results=validation_results,
        embedding_count=len(embedding_vectors),
        embedding_model=embedding_config.model if embedding_config else None,
        embedding_dimensions=embedding_dimensions,
    )


def aggregate_validation_status(results: list[ValidationResult]) -> str:
    if any(result.status == "blocked" for result in results):
        return "blocked"
    if any(result.status == "invalid" for result in results):
        return "invalid"
    return "ok"


def initialize_schema(connection: sqlite3.Connection) -> None:
    connection.execute(f"PRAGMA user_version = {INDEX_SCHEMA_VERSION}")
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute(
        """
        CREATE TABLE metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """
    )
    connection.execute(
        """
        CREATE TABLE memories (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT NOT NULL,
            tags_json TEXT NOT NULL,
            source_json TEXT NOT NULL,
            evidence_json TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            summary TEXT NOT NULL,
            body TEXT NOT NULL,
            search_text TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
        """
    )
    connection.execute(
        """
        CREATE TABLE embeddings (
            memory_id TEXT PRIMARY KEY,
            content_hash TEXT NOT NULL,
            model TEXT NOT NULL,
            dimensions INTEGER NOT NULL,
            vector_json TEXT NOT NULL,
            FOREIGN KEY(memory_id) REFERENCES memories(id) ON DELETE CASCADE
        )
        """
    )
    connection.execute("CREATE INDEX memories_status_idx ON memories(status)")
    connection.execute("CREATE INDEX memories_type_idx ON memories(type)")
    connection.execute("CREATE INDEX embeddings_model_idx ON embeddings(model)")


def write_metadata(
    connection: sqlite3.Connection,
    rebuilt_at: str,
    memory_count: int,
    *,
    embedding_count: int = 0,
    embedding_model: str | None = None,
    embedding_dimensions: int | None = None,
) -> None:
    rows = {
        "schema_version": str(INDEX_SCHEMA_VERSION),
        "rebuilt_at": rebuilt_at,
        "memory_count": str(memory_count),
        "embedding_count": str(embedding_count),
    }
    if embedding_model is not None:
        rows["embedding_model"] = embedding_model
    if embedding_dimensions is not None:
        rows["embedding_dimensions"] = str(embedding_dimensions)
    connection.executemany(
        "INSERT INTO metadata (key, value) VALUES (?, ?)",
        sorted(rows.items()),
    )


def memory_row(repo_root: Path, document: MemoryDocument) -> dict[str, str]:
    frontmatter = document.frontmatter
    title = as_text(frontmatter["title"])
    body = normalize_body(document.body)
    summary = summarize_body(body, title)
    tags = frontmatter["tags"]
    source = frontmatter["source"]
    evidence = frontmatter["evidence"]
    return {
        "id": as_text(frontmatter["id"]),
        "path": relative_to_repo(repo_root, document.path),
        "title": title,
        "type": as_text(frontmatter["type"]),
        "status": as_text(frontmatter["status"]),
        "tags_json": json_dumps(tags),
        "source_json": json_dumps(source),
        "evidence_json": json_dumps(evidence),
        "content_hash": as_text(frontmatter["content_hash"]),
        "summary": summary,
        "body": body,
        "search_text": build_search_text(frontmatter, body, summary),
        "updated_at": as_text(frontmatter["updated_at"]),
    }


def insert_memory(connection: sqlite3.Connection, row: dict[str, str]) -> None:
    connection.execute(
        """
        INSERT INTO memories (
            id, path, title, type, status, tags_json, source_json, evidence_json,
            content_hash, summary, body, search_text, updated_at
        )
        VALUES (
            :id, :path, :title, :type, :status, :tags_json, :source_json,
            :evidence_json, :content_hash, :summary, :body, :search_text,
            :updated_at
        )
        """,
        row,
    )


def insert_embedding(
    connection: sqlite3.Connection,
    row: dict[str, str],
    config: EmbeddingConfig,
    vector: list[float],
) -> None:
    connection.execute(
        """
        INSERT INTO embeddings (
            memory_id, content_hash, model, dimensions, vector_json
        )
        VALUES (?, ?, ?, ?, ?)
        """,
        (
            row["id"],
            row["content_hash"],
            config.model,
            len(vector),
            json_dumps(vector),
        ),
    )


def search_index(
    repo_root: Path,
    query: str,
    *,
    limit: int = 10,
    include_superseded: bool = False,
    env: Mapping[str, str] | None = None,
) -> dict[str, Any]:
    repo_root = repo_root.resolve()
    env = os.environ if env is None else env
    if limit <= 0:
        raise BrickIndexError(
            "limit must be greater than zero",
            code="invalid_limit",
            payload={
                "status": "invalid",
                "reason": "invalid_limit",
                "message": "limit must be greater than zero",
            },
        )
    terms = unique_terms(query)
    if not terms:
        raise BrickIndexError(
            "query must contain at least one searchable term",
            code="invalid_query",
            payload={
                "status": "invalid",
                "reason": "invalid_query",
                "message": "query must contain at least one searchable term",
            },
        )

    target = index_path(repo_root)
    if not target.exists():
        raise BrickIndexError(
            "Brick index has not been built",
            code="index_missing",
            payload={
                "status": "error",
                "reason": "index_missing",
                "message": "Brick index has not been built. Run `brick rebuild` first.",
                "action": "run brick rebuild",
            },
        )

    try:
        connection = sqlite3.connect(target)
    except sqlite3.Error as exc:
        raise index_read_error(repo_root, target, exc) from exc
    try:
        connection.row_factory = sqlite3.Row
        metadata = read_metadata(connection)
        ensure_current_schema(repo_root, target, metadata)
        rows = read_search_rows(connection, include_superseded=include_superseded)
    except sqlite3.Error as exc:
        raise index_read_error(repo_root, target, exc) from exc
    finally:
        connection.close()

    embedding_config = configured_embedding(repo_root, env)
    query_vector: list[float] | None = None
    semantic = unavailable_semantic_status(repo_root, env)
    indexed_embedding_count = sum(1 for row in rows if row["embedding_vector_json"] is not None)
    if embedding_config is not None:
        semantic = semantic_status_for_index(
            repo_root,
            metadata,
            embedding_config,
            indexed_embedding_count,
        )
        if semantic["available"]:
            try:
                query_vector = request_embeddings(embedding_config, [query])[0]
                query_dimensions = len(query_vector)
                indexed_dimensions = metadata.get("embedding_dimensions")
                if indexed_dimensions != query_dimensions:
                    query_vector = None
                    semantic = {
                        "available": False,
                        "reason": "embedding_dimension_mismatch",
                        "config_path": local_config_relative_path(repo_root),
                        "model": embedding_config.model,
                        "indexed_dimensions": indexed_dimensions,
                        "query_dimensions": query_dimensions,
                    }
                else:
                    semantic["query_dimensions"] = query_dimensions
            except EmbeddingError as exc:
                query_vector = None
                semantic = {
                    "available": False,
                    "reason": exc.reason,
                    "config_path": local_config_relative_path(repo_root),
                    "model": embedding_config.model,
                    "message": str(exc),
                }

    scored = []
    for row in rows:
        keyword_score, matched_terms = score_row(row, query, terms)
        semantic_score = semantic_score_for_row(row, query_vector)
        score = combined_score(keyword_score, semantic_score)
        if score <= 0:
            continue
        scored.append((score, keyword_score, semantic_score, row["path"], matched_terms, row))
    scored.sort(key=lambda item: (-item[0], item[3]))
    limited = scored[:limit]

    return {
        "status": "ok",
        "query": query,
        "index": {
            "path": relative_to_repo(repo_root, target),
            "schema_version": metadata.get("schema_version", INDEX_SCHEMA_VERSION),
            "rebuilt_at": metadata.get("rebuilt_at"),
            "memory_count": metadata.get("memory_count", 0),
            "embedding_count": metadata.get("embedding_count", 0),
            **optional_metadata(metadata, "embedding_model"),
            **optional_metadata(metadata, "embedding_dimensions"),
        },
        "retrieval": {
            "mode": "hybrid" if semantic.get("available") else "keyword",
            "semantic": semantic,
        },
        "filters": {
            "include_superseded": include_superseded,
            "statuses": ["active", "superseded"] if include_superseded else ["active"],
        },
        "results": [
            result_from_row(repo_root, row, score, keyword_score, semantic_score, matched_terms)
            for score, keyword_score, semantic_score, _path, matched_terms, row in limited
        ],
    }


def read_metadata(connection: sqlite3.Connection) -> dict[str, Any]:
    rows = connection.execute("SELECT key, value FROM metadata").fetchall()
    metadata: dict[str, Any] = {}
    for key, value in rows:
        if key in {"schema_version", "memory_count", "embedding_count", "embedding_dimensions"}:
            metadata[key] = int(value)
        else:
            metadata[key] = value
    return metadata


def ensure_current_schema(repo_root: Path, target: Path, metadata: dict[str, Any]) -> None:
    found = metadata.get("schema_version")
    if found == INDEX_SCHEMA_VERSION:
        return
    raise BrickIndexError(
        "Brick index schema is out of date",
        code="index_schema_mismatch",
        payload={
            "status": "error",
            "reason": "index_schema_mismatch",
            "message": "Brick index schema is out of date. Run `brick rebuild` first.",
            "path": relative_to_repo(repo_root, target),
            "expected_schema_version": INDEX_SCHEMA_VERSION,
            "found_schema_version": found,
            "action": "run brick rebuild",
        },
    )


def optional_metadata(metadata: dict[str, Any], key: str) -> dict[str, Any]:
    if key not in metadata:
        return {}
    return {key: metadata[key]}


def read_search_rows(
    connection: sqlite3.Connection,
    *,
    include_superseded: bool,
) -> list[sqlite3.Row]:
    statuses = ("active", "superseded") if include_superseded else ("active",)
    placeholders = ", ".join("?" for _ in statuses)
    return connection.execute(
        f"""
        SELECT
            memories.id,
            memories.path,
            memories.title,
            memories.type,
            memories.status,
            memories.tags_json,
            memories.source_json,
            memories.evidence_json,
            memories.content_hash,
            memories.summary,
            memories.body,
            memories.search_text,
            memories.updated_at,
            embeddings.model AS embedding_model,
            embeddings.dimensions AS embedding_dimensions,
            embeddings.vector_json AS embedding_vector_json
        FROM memories
        LEFT JOIN embeddings
            ON embeddings.memory_id = memories.id
            AND embeddings.content_hash = memories.content_hash
        WHERE memories.status IN ({placeholders})
        ORDER BY memories.path
        """,
        statuses,
    ).fetchall()


def score_row(row: sqlite3.Row, query: str, terms: list[str]) -> tuple[int, list[str]]:
    tags = json.loads(row["tags_json"])
    source = json.loads(row["source_json"])
    evidence = json.loads(row["evidence_json"])
    fields = (
        (row["title"], 8, 12),
        (" ".join(tags), 6, 10),
        (row["type"], 4, 0),
        (json_dumps(evidence), 3, 5),
        (row["summary"], 3, 6),
        (json_dumps(source), 2, 3),
        (row["body"], 1, 4),
    )
    phrase = normalize_search_text(query)
    score = 0
    matched: set[str] = set()
    for text, term_weight, phrase_weight in fields:
        tokens = tokenize(text)
        token_counts = {term: tokens.count(term) for term in terms}
        for term, count in token_counts.items():
            if count:
                score += term_weight * count
                matched.add(term)
        if phrase and phrase_weight and phrase in normalize_search_text(text):
            score += phrase_weight
    return score, [term for term in terms if term in matched]


def result_from_row(
    repo_root: Path,
    row: sqlite3.Row,
    score: float,
    keyword_score: int,
    semantic_score: float | None,
    matched_terms: list[str],
) -> dict[str, Any]:
    source_path = row["path"]
    result: dict[str, Any] = {
        "id": row["id"],
        "title": row["title"],
        "type": row["type"],
        "status": row["status"],
        "tags": json.loads(row["tags_json"]),
        "source_path": source_path,
        "full_text_path": source_path,
        "source": json.loads(row["source_json"]),
        "evidence": json.loads(row["evidence_json"]),
        "summary": row["summary"],
        "content_hash": row["content_hash"],
        "score": round(score, 6),
        "keyword_score": keyword_score,
        "confidence": confidence_for_score(score),
        "matched_terms": matched_terms,
    }
    if semantic_score is not None:
        result["semantic_score"] = round(semantic_score, 6)
    return result


def unavailable_semantic_status(repo_root: Path, env: Mapping[str, str]) -> dict[str, Any]:
    settings = embedding_settings(repo_root, env)
    if not settings.raw_url:
        return {
            "available": False,
            "reason": "embedding_url_not_configured",
            "config_path": local_config_relative_path(repo_root),
            "field": EMBEDDING_URL_FIELD,
        }
    if not settings.model:
        return {
            "available": False,
            "reason": "embedding_model_not_configured",
            "config_path": local_config_relative_path(repo_root),
            "field": EMBEDDING_MODEL_FIELD,
        }
    return {
        "available": False,
        "reason": "index_has_no_embeddings",
        "config_path": local_config_relative_path(repo_root),
        "action": "run brick rebuild",
    }


def semantic_status_for_index(
    repo_root: Path,
    metadata: dict[str, Any],
    config: EmbeddingConfig,
    indexed_embedding_count: int,
) -> dict[str, Any]:
    if indexed_embedding_count <= 0:
        return {
            "available": False,
            "reason": "index_has_no_embeddings",
            "config_path": local_config_relative_path(repo_root),
            "model": config.model,
            "action": "run brick rebuild",
        }
    indexed_model = metadata.get("embedding_model")
    if indexed_model != config.model:
        return {
            "available": False,
            "reason": "embedding_model_mismatch",
            "config_path": local_config_relative_path(repo_root),
            "field": EMBEDDING_MODEL_FIELD,
            "configured_model": config.model,
            "indexed_model": indexed_model,
            "action": "run brick rebuild",
        }
    return {
        "available": True,
        "config_path": local_config_relative_path(repo_root),
        "model": config.model,
        "indexed_count": indexed_embedding_count,
        "dimensions": metadata.get("embedding_dimensions"),
    }


def configured_embedding(repo_root: Path, env: Mapping[str, str]) -> EmbeddingConfig | None:
    settings = embedding_settings(repo_root, env)
    if not settings.raw_url or not settings.model:
        return None
    return EmbeddingConfig(
        endpoint_url=embedding_endpoint_url(settings.raw_url),
        model=settings.model,
        api_key=settings.api_key,
    )


def embedding_settings(repo_root: Path, env: Mapping[str, str]) -> EmbeddingSettings:
    local = load_local_embedding_config(repo_root)
    api_key_env = local.api_key_env or EMBEDDING_API_KEY_ENV_VAR
    api_key = env.get(api_key_env, "").strip()
    return EmbeddingSettings(
        raw_url=local.url,
        model=local.model,
        api_key_env=api_key_env,
        api_key=api_key or None,
    )


def load_local_embedding_config(repo_root: Path) -> LocalEmbeddingConfig:
    config_path = repo_root / LOCAL_CONFIG_RELATIVE_PATH
    if not config_path.exists():
        return LocalEmbeddingConfig()
    try:
        payload = json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise local_config_error(repo_root, f"invalid JSON: {exc}") from exc
    except OSError as exc:
        raise local_config_error(repo_root, f"could not read local config: {exc}") from exc

    if not isinstance(payload, dict):
        raise local_config_error(repo_root, "local config must be a JSON object")
    unknown_top_level = sorted(set(payload) - {"embedding"})
    if unknown_top_level:
        raise local_config_error(
            repo_root,
            f"unknown local config fields: {', '.join(unknown_top_level)}",
        )

    embedding = payload.get("embedding", {})
    if not isinstance(embedding, dict):
        raise local_config_error(repo_root, "embedding config must be a JSON object")
    if "api_key" in embedding:
        raise local_config_error(
            repo_root,
            "embedding.api_key is not allowed; set embedding.api_key_env instead",
        )
    unknown_embedding = sorted(set(embedding) - {"url", "base_url", "model", "api_key_env"})
    if unknown_embedding:
        raise local_config_error(
            repo_root,
            f"unknown embedding config fields: {', '.join(unknown_embedding)}",
        )

    url = local_config_string(repo_root, embedding, "url")
    base_url = local_config_string(repo_root, embedding, "base_url")
    if url and base_url and url != base_url:
        raise local_config_error(
            repo_root,
            "embedding.url and embedding.base_url must not disagree",
        )
    api_key_env = local_config_string(repo_root, embedding, "api_key_env")
    return LocalEmbeddingConfig(
        url=url or base_url,
        model=local_config_string(repo_root, embedding, "model"),
        api_key_env=api_key_env or EMBEDDING_API_KEY_ENV_VAR,
    )


def local_config_string(repo_root: Path, payload: dict[str, Any], key: str) -> str:
    value = payload.get(key, "")
    if not isinstance(value, str):
        raise local_config_error(repo_root, f"embedding.{key} must be a string")
    return value.strip()


def local_config_error(repo_root: Path, message: str) -> BrickIndexError:
    return BrickIndexError(
        f"invalid Brick local config: {message}",
        code="invalid_local_config",
        payload={
            "status": "invalid",
            "reason": "invalid_local_config",
            "path": local_config_relative_path(repo_root),
            "message": message,
        },
    )


def local_config_relative_path(repo_root: Path) -> str:
    return relative_to_repo(repo_root, repo_root / LOCAL_CONFIG_RELATIVE_PATH)


def embedding_endpoint_url(raw_url: str) -> str:
    stripped = raw_url.rstrip("/")
    if stripped.endswith("/embeddings"):
        return stripped
    return f"{stripped}/embeddings"


def request_embeddings(config: EmbeddingConfig, inputs: list[str]) -> list[list[float]]:
    if not inputs:
        return []
    request_body = json.dumps(
        {
            "model": config.model,
            "input": inputs,
        },
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    if config.api_key is not None:
        headers["Authorization"] = f"Bearer {config.api_key}"
    request = urllib.request.Request(
        config.endpoint_url,
        data=request_body,
        headers=headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=EMBEDDING_TIMEOUT_SECONDS) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise EmbeddingError(
            "embedding_request_failed",
            f"embedding endpoint returned HTTP {exc.code}: {detail}",
        ) from exc
    except http.client.RemoteDisconnected as exc:
        raise EmbeddingError(
            "embedding_request_failed",
            f"embedding endpoint request failed: {exc}",
        ) from exc
    except urllib.error.URLError as exc:
        raise EmbeddingError(
            "embedding_request_failed",
            f"embedding endpoint request failed: {exc.reason}",
        ) from exc
    except TimeoutError as exc:
        raise EmbeddingError(
            "embedding_request_failed",
            "embedding endpoint request timed out",
        ) from exc

    try:
        payload = json.loads(response_body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise EmbeddingError(
            "embedding_response_invalid",
            "embedding endpoint returned invalid JSON",
        ) from exc
    return parse_embedding_response(payload, len(inputs))


def parse_embedding_response(payload: Any, expected_count: int) -> list[list[float]]:
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
        raise EmbeddingError(
            "embedding_response_invalid",
            "embedding response must contain a data array",
        )
    data = payload["data"]
    if len(data) != expected_count:
        raise EmbeddingError(
            "embedding_response_invalid",
            f"embedding response returned {len(data)} vectors for {expected_count} inputs",
        )
    if all(isinstance(item, dict) and isinstance(item.get("index"), int) for item in data):
        data = sorted(data, key=lambda item: item["index"])
    vectors = []
    for item in data:
        if not isinstance(item, dict):
            raise EmbeddingError("embedding_response_invalid", "embedding data items must be objects")
        embedding = item.get("embedding")
        if not isinstance(embedding, list) or not embedding:
            raise EmbeddingError(
                "embedding_response_invalid",
                "embedding data items must contain non-empty embedding arrays",
            )
        vector = []
        for value in embedding:
            if not isinstance(value, (int, float)) or isinstance(value, bool):
                raise EmbeddingError(
                    "embedding_response_invalid",
                    "embedding values must be numeric",
                )
            vector.append(float(value))
        vectors.append(vector)
    validate_embedding_dimensions(vectors)
    return vectors


def validate_embedding_dimensions(vectors: list[list[float]]) -> int:
    if not vectors:
        return 0
    dimensions = len(vectors[0])
    if dimensions == 0:
        raise EmbeddingError("embedding_response_invalid", "embedding vectors must not be empty")
    for vector in vectors:
        if len(vector) != dimensions:
            raise EmbeddingError(
                "embedding_response_invalid",
                "embedding vectors must all have the same dimensions",
            )
    return dimensions


def semantic_score_for_row(row: sqlite3.Row, query_vector: list[float] | None) -> float | None:
    if query_vector is None or row["embedding_vector_json"] is None:
        return None
    try:
        vector = json.loads(row["embedding_vector_json"])
    except json.JSONDecodeError:
        return None
    if not isinstance(vector, list):
        return None
    try:
        memory_vector = [float(value) for value in vector]
    except (TypeError, ValueError):
        return None
    if len(memory_vector) != len(query_vector):
        return None
    return cosine_similarity(query_vector, memory_vector)


def cosine_similarity(left: list[float], right: list[float]) -> float:
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        return 0.0
    dot = sum(left_value * right_value for left_value, right_value in zip(left, right, strict=True))
    return dot / (left_norm * right_norm)


def combined_score(keyword_score: int, semantic_score: float | None) -> float:
    if semantic_score is None:
        return float(keyword_score)
    return float(keyword_score) + max(0.0, semantic_score) * HYBRID_SEMANTIC_WEIGHT


def index_write_error(repo_root: Path, target: Path, exc: BaseException) -> BrickIndexError:
    return BrickIndexError(
        f"could not write Brick index: {exc}",
        code="index_write_failed",
        payload={
            "status": "error",
            "reason": "index_write_failed",
            "path": relative_to_repo(repo_root, target),
            "message": str(exc),
        },
    )


def index_read_error(repo_root: Path, target: Path, exc: BaseException) -> BrickIndexError:
    return BrickIndexError(
        f"could not read Brick index: {exc}",
        code="index_read_failed",
        payload={
            "status": "error",
            "reason": "index_read_failed",
            "path": relative_to_repo(repo_root, target),
            "message": str(exc),
        },
    )


def build_search_text(frontmatter: dict[str, Any], body: str, summary: str) -> str:
    parts = [
        as_text(frontmatter.get("title", "")),
        as_text(frontmatter.get("type", "")),
        " ".join(frontmatter.get("tags", [])),
        json_dumps(frontmatter.get("source", {})),
        json_dumps(frontmatter.get("evidence", [])),
        summary,
        body,
    ]
    return normalize_search_text(" ".join(parts))


def summarize_body(body: str, fallback_title: str) -> str:
    collapsed = re.sub(r"\s+", " ", normalize_body(body)).strip()
    if not collapsed:
        return fallback_title
    if len(collapsed) <= MAX_SUMMARY_LENGTH:
        return collapsed
    return collapsed[: MAX_SUMMARY_LENGTH - 3].rstrip() + "..."


def confidence_for_score(score: float) -> str:
    if score >= 20:
        return "high"
    if score >= 8:
        return "medium"
    return "low"


def unique_terms(query: str) -> list[str]:
    return list(dict.fromkeys(tokenize(query)))


def tokenize(value: str) -> list[str]:
    return TOKEN_RE.findall(value.lower())


def normalize_search_text(value: str) -> str:
    return " ".join(tokenize(value))


def json_dumps(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def as_text(value: Any) -> str:
    return str(value)


def relative_to_repo(repo_root: Path, path: Path) -> str:
    return str(path.resolve().relative_to(repo_root.resolve()))
