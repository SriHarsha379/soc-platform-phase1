"""
SOC SOAR Service – FastAPI entry point.

Endpoints:
  GET  /health       – liveness probe
  GET  /playbooks    – list all playbook definitions
  POST /trigger      – evaluate & execute playbooks for an incident
  GET  /executions   – audit log of past executions
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import FastAPI
from pydantic import BaseModel, Field

import db
import engine

db.init_db()

app = FastAPI(
    title="SOC SOAR Service",
    description="Security Orchestration, Automation, and Response – playbook execution engine.",
    version="1.0.0",
)


# ── Request / response models ─────────────────────────────────────────────────


class IncidentPayload(BaseModel):
    """Incident data sent from the backend to trigger playbook evaluation."""

    id: int | None = None
    title: str = ""
    description: str = ""
    severity: str = "low"
    ruleType: str = ""
    status: str = "open"
    sourceIp: str | None = Field(default=None)
    affectedHost: str | None = Field(default=None)
    eventCount: int = 0
    riskScore: int | None = Field(default=None)
    aiReason: str | None = Field(default=None)
    firstSeen: str | None = Field(default=None)
    lastSeen: str | None = Field(default=None)


# ── Routes ────────────────────────────────────────────────────────────────────


@app.get("/health", tags=["health"])
def health() -> dict:
    """Liveness probe."""
    return {"status": "ok", "service": "soc-soar"}


@app.get("/playbooks", tags=["playbooks"])
def list_playbooks() -> list[dict]:
    """List all playbook definitions loaded from disk."""
    return engine.load_playbooks()


@app.post("/trigger", tags=["engine"])
def trigger(incident: IncidentPayload) -> dict:
    """
    Evaluate all enabled playbooks against the supplied incident and execute
    matching ones. Returns the list of execution results.
    """
    incident_dict = incident.model_dump()
    results = engine.run_playbooks(incident_dict)

    for r in results:
        db.save_execution(
            playbook_id=r["playbook_id"],
            playbook_name=r["playbook_name"],
            incident=incident_dict,
            actions_taken=r["actions"],
            status=r["status"],
        )

    return {
        "triggered": len(results),
        "executions": results,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/executions", tags=["audit"])
def get_executions(limit: int = 100) -> list[dict]:
    """Retrieve the last N SOAR execution records (audit log)."""
    return db.get_executions(min(limit, 500))
