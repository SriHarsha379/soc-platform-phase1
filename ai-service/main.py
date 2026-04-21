"""
SOC AI Anomaly Detection – FastAPI entry point.
"""

from __future__ import annotations

import os

from fastapi import FastAPI
from pydantic import BaseModel, Field

from detector import analyze_event

app = FastAPI(
    title="SOC AI Anomaly Detection",
    description="Lightweight statistical anomaly detection for SOC log events.",
    version="1.0.0",
)


# ── Request / response models ─────────────────────────────────────────────────


class LogEvent(BaseModel):
    """A single metric observation to be scored."""

    event_type: str = Field(
        ...,
        description="Type of event: login_attempt | cpu_usage | network_traffic",
        examples=["login_attempt"],
    )
    value: float = Field(
        ...,
        description="The observed metric value (e.g. failed login count, CPU %)",
        ge=0,
        examples=[12],
    )
    window_minutes: float = Field(
        default=5.0,
        description="Observation window in minutes (informational)",
        gt=0,
        examples=[5],
    )
    source_ip: str | None = Field(default=None, description="Source IP address (optional)")
    metadata: dict = Field(default_factory=dict, description="Additional context")


class AnalysisResult(BaseModel):
    """Anomaly detection result."""

    risk_score: int = Field(..., ge=0, le=100, description="Risk score from 0 (safe) to 100 (critical)")
    is_anomaly: bool = Field(..., description="True if the observation is statistically anomalous")
    severity: str = Field(..., description="low | medium | high | critical")
    reason: str = Field(..., description="Human-readable explanation of the score")


# ── Endpoints ─────────────────────────────────────────────────────────────────


@app.get("/health", tags=["health"])
def health() -> dict:
    """Service health check."""
    return {"status": "ok", "service": "soc-ai"}


@app.post("/analyze", response_model=AnalysisResult, tags=["detection"])
def analyze(event: LogEvent) -> AnalysisResult:
    """
    Analyse a log event and return a risk score with anomaly flag.

    **Example request:**
    ```json
    {
      "event_type": "login_attempt",
      "value": 12,
      "window_minutes": 10,
      "source_ip": "203.0.113.42"
    }
    ```
    """
    result = analyze_event(event.event_type, event.value, event.window_minutes)
    return AnalysisResult(**result)
