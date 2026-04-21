"""
SOAR execution audit log backed by a local SQLite database (stdlib sqlite3).
"""

from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime, timezone
from typing import Any

DB_PATH = os.getenv("SOAR_DB_PATH", "/data/soar.db")


def _connect() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    """Create the executions table if it does not exist."""
    with _connect() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS executions (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                playbook_id   TEXT    NOT NULL,
                playbook_name TEXT    NOT NULL,
                incident_id   INTEGER,
                rule_type     TEXT,
                severity      TEXT,
                source_ip     TEXT,
                triggered_at  TEXT    NOT NULL,
                actions_taken TEXT    NOT NULL,
                status        TEXT    NOT NULL
            )
            """
        )
        conn.commit()


def save_execution(
    *,
    playbook_id: str,
    playbook_name: str,
    incident: dict[str, Any],
    actions_taken: list[dict],
    status: str,
) -> int:
    triggered_at = datetime.now(timezone.utc).isoformat()
    with _connect() as conn:
        cur = conn.execute(
            """
            INSERT INTO executions
                (playbook_id, playbook_name, incident_id, rule_type, severity,
                 source_ip, triggered_at, actions_taken, status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                playbook_id,
                playbook_name,
                incident.get("id"),
                incident.get("ruleType"),
                incident.get("severity"),
                incident.get("sourceIp"),
                triggered_at,
                json.dumps(actions_taken),
                status,
            ),
        )
        conn.commit()
        return cur.lastrowid or 0


def get_executions(limit: int = 100) -> list[dict]:
    with _connect() as conn:
        rows = conn.execute(
            "SELECT * FROM executions ORDER BY triggered_at DESC LIMIT ?",
            (limit,),
        ).fetchall()

    result = []
    for row in rows:
        d = dict(row)
        d["actions_taken"] = json.loads(d["actions_taken"])
        result.append(d)
    return result
