"""
PlaybookEngine

Loads JSON playbook definitions, evaluates them against an incident dict,
and dispatches the matching actions.
"""

from __future__ import annotations

import json
import logging
import re
from pathlib import Path
from typing import Any

from actions import block_ip, send_email, send_telegram

logger = logging.getLogger("soar.engine")

PLAYBOOKS_DIR = Path(__file__).parent / "playbooks"

SEVERITY_ORDER: dict[str, int] = {
    "low": 0,
    "medium": 1,
    "high": 2,
    "critical": 3,
}


# ── Template rendering ────────────────────────────────────────────────────────


def _render(template: str, context: dict[str, str]) -> str:
    """Replace {{field}} placeholders with values from context."""

    def replace(match: re.Match) -> str:
        key = match.group(1)
        return context.get(key, f"{{{{{key}}}}}")

    return re.sub(r"\{\{(\w+)\}\}", replace, template)


def _render_params(params: dict[str, Any], context: dict[str, str]) -> dict[str, Any]:
    return {
        k: _render(v, context) if isinstance(v, str) else v
        for k, v in params.items()
    }


# ── Condition evaluation ──────────────────────────────────────────────────────


def _matches_condition(incident: dict, condition: dict) -> bool:
    field = condition.get("field", "")
    operator = condition.get("operator", "")
    threshold = condition.get("value")
    actual = incident.get(field)

    if actual is None:
        return False

    try:
        if operator == "eq":
            return str(actual) == str(threshold)
        if operator == "neq":
            return str(actual) != str(threshold)
        if operator == "gte":
            return float(actual) >= float(threshold)
        if operator == "lte":
            return float(actual) <= float(threshold)
        if operator == "gt":
            return float(actual) > float(threshold)
        if operator == "lt":
            return float(actual) < float(threshold)
        if operator == "contains":
            return str(threshold).lower() in str(actual).lower()
    except (TypeError, ValueError):
        return False

    return False


# ── Playbook loading ──────────────────────────────────────────────────────────


def load_playbooks() -> list[dict]:
    """Read all *.json files from the playbooks directory."""
    playbooks = []
    for path in sorted(PLAYBOOKS_DIR.glob("*.json")):
        try:
            playbooks.append(json.loads(path.read_text()))
        except Exception as exc:
            logger.warning("Could not load playbook %s: %s", path.name, exc)
    return playbooks


# ── Playbook matching ─────────────────────────────────────────────────────────


def _playbook_matches(playbook: dict, incident: dict) -> bool:
    trigger = playbook.get("trigger", {})

    # rule_type filter
    rule_type = trigger.get("rule_type")
    if rule_type and incident.get("ruleType") != rule_type:
        return False

    # min_severity filter
    min_sev = trigger.get("min_severity", "low")
    inc_sev = (incident.get("severity") or "low").lower()
    if SEVERITY_ORDER.get(inc_sev, 0) < SEVERITY_ORDER.get(min_sev, 0):
        return False

    # all conditions must pass
    for cond in playbook.get("conditions", []):
        if not _matches_condition(incident, cond):
            return False

    return True


# ── Action dispatch ───────────────────────────────────────────────────────────


def _dispatch_action(action_type: str, params: dict) -> dict:
    if action_type == "block_ip":
        return block_ip(params)
    if action_type == "send_email":
        return send_email(params)
    if action_type == "send_telegram":
        return send_telegram(params)
    return {"status": "skipped", "reason": f"Unknown action type: {action_type}"}


def _execute_playbook(playbook: dict, incident: dict) -> list[dict]:
    """Run every action in a playbook and return per-action result dicts."""
    context = {k: str(v) if v is not None else "" for k, v in incident.items()}
    results = []

    for action in playbook.get("actions", []):
        action_type = action.get("type", "")
        raw_params = action.get("params", {})
        params = _render_params(raw_params, context)

        try:
            result = _dispatch_action(action_type, params)
        except Exception as exc:
            logger.exception("Action %s raised an exception: %s", action_type, exc)
            result = {"status": "error", "error": str(exc)}

        results.append({"action_type": action_type, **result})

    return results


# ── Public API ────────────────────────────────────────────────────────────────


def run_playbooks(incident: dict) -> list[dict]:
    """
    Evaluate all enabled playbooks against an incident.

    Returns a list of execution records, one per matched playbook.
    """
    playbooks = load_playbooks()
    executions = []

    for pb in playbooks:
        if not pb.get("enabled", True):
            continue
        if not _playbook_matches(pb, incident):
            continue

        logger.info(
            "Playbook '%s' matched incident id=%s ruleType=%s",
            pb.get("name"),
            incident.get("id"),
            incident.get("ruleType"),
        )

        action_results = _execute_playbook(pb, incident)

        statuses = {r.get("status") for r in action_results}
        if "error" in statuses:
            status = "error"
        elif statuses <= {"simulated", "skipped"}:
            status = "simulated"
        else:
            status = "success"

        executions.append(
            {
                "playbook_id": pb.get("id", ""),
                "playbook_name": pb.get("name", ""),
                "status": status,
                "actions": action_results,
            }
        )

    return executions
