"""
SOC AI Anomaly Detection Service
---------------------------------
Lightweight statistical anomaly detector for SOC log events.

Supported event types:
  - login_attempt   : failed login counts within a time window
  - cpu_usage       : CPU utilisation percentage
  - network_traffic : event count within a time window

Detection method:
  Z-score against configurable baselines. Values beyond 2σ are flagged as
  anomalies. Risk score is a 0–100 normalised representation of deviation.
"""

import math
import os

# ── Baselines (overridable via environment variables) ─────────────────────────

BASELINES: dict[str, dict[str, float]] = {
    "login_attempt": {
        "mean": float(os.getenv("BASELINE_LOGIN_MEAN", "2")),
        "std": float(os.getenv("BASELINE_LOGIN_STD", "1.5")),
    },
    "cpu_usage": {
        "mean": float(os.getenv("BASELINE_CPU_MEAN", "40")),
        "std": float(os.getenv("BASELINE_CPU_STD", "20")),
    },
    "network_traffic": {
        "mean": float(os.getenv("BASELINE_TRAFFIC_MEAN", "100")),
        "std": float(os.getenv("BASELINE_TRAFFIC_STD", "50")),
    },
}

# Sigma threshold above which an event is considered anomalous
ANOMALY_SIGMA: float = float(os.getenv("ANOMALY_SIGMA_THRESHOLD", "2.0"))

# Maximum sigma used for score normalisation (maps to risk_score = 100)
MAX_SIGMA: float = 4.0


# ── Core computation ──────────────────────────────────────────────────────────


def _z_score(value: float, mean: float, std: float) -> float:
    """Return the one-sided z-score (negative values clamped to 0)."""
    denom = std if std > 0 else 1.0
    return max(0.0, (value - mean) / denom)


def _risk_score(z: float) -> int:
    """Map a z-score to a 0–100 integer risk score."""
    return round(min(100, (z / MAX_SIGMA) * 100))


def _severity(score: int) -> str:
    if score >= 80:
        return "critical"
    if score >= 60:
        return "high"
    if score >= 35:
        return "medium"
    return "low"


# ── Public API ────────────────────────────────────────────────────────────────


def analyze_event(event_type: str, value: float, window_minutes: float = 5.0) -> dict:
    """
    Analyse a single metric observation and return an anomaly assessment.

    Args:
        event_type:     One of login_attempt | cpu_usage | network_traffic.
        value:          The observed metric value.
        window_minutes: Observation window length (informational).

    Returns:
        dict with keys: risk_score, is_anomaly, severity, reason.
    """
    baseline = BASELINES.get(event_type)

    if baseline is None:
        return {
            "risk_score": 0,
            "is_anomaly": False,
            "severity": "low",
            "reason": f"Unknown event type '{event_type}'; no baseline available.",
        }

    mean = baseline["mean"]
    std = baseline["std"]
    z = _z_score(value, mean, std)
    score = _risk_score(z)
    is_anomaly = z >= ANOMALY_SIGMA

    reason = (
        f"{event_type}: observed={value:.1f}, "
        f"baseline={mean:.1f}±{std:.1f}, "
        f"z-score={z:.2f}, "
        f"window={window_minutes:.0f}min"
    )

    return {
        "risk_score": score,
        "is_anomaly": is_anomaly,
        "severity": _severity(score),
        "reason": reason,
    }
