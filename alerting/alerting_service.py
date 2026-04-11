#!/usr/bin/env python3
"""
SOC Platform Phase 1 - Alerting Service
Monitors Elasticsearch for security events and sends email alerts via SMTP.
"""

import json
import logging
import os
import smtplib
import time
from datetime import datetime, timedelta, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

import schedule
from elasticsearch import Elasticsearch

# ── Logging ────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("soc-alerting")

# ── Configuration (from environment variables) ─────────────────────────────────
ES_HOST = os.getenv("ELASTICSEARCH_HOST", "http://elasticsearch:9200")
ES_USER = os.getenv("ELASTIC_USERNAME", "elastic")
ES_PASS = os.getenv("ELASTIC_PASSWORD", "elastic_secure_password")

SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASS = os.getenv("SMTP_PASSWORD", "")
SMTP_FROM = os.getenv("SMTP_FROM", "soc-alerts@yourdomain.com")
ALERT_RECIPIENTS = [r.strip() for r in os.getenv("ALERT_RECIPIENTS", "").split(",") if r.strip()]

CPU_THRESHOLD = float(os.getenv("CPU_ALERT_THRESHOLD", "85"))
MEMORY_THRESHOLD = float(os.getenv("MEMORY_ALERT_THRESHOLD", "90"))
DISK_THRESHOLD = float(os.getenv("DISK_ALERT_THRESHOLD", "85"))
FAILED_LOGIN_THRESHOLD = int(os.getenv("FAILED_LOGIN_THRESHOLD", "5"))

TEMPLATE_FILE = os.getenv("TEMPLATE_FILE", "/app/alert_templates.json")

# ── Load alert templates ────────────────────────────────────────────────────────
def load_templates() -> dict:
    try:
        with open(TEMPLATE_FILE) as f:
            return json.load(f).get("templates", {})
    except (FileNotFoundError, json.JSONDecodeError) as exc:
        logger.warning("Could not load alert templates: %s", exc)
        return {}


TEMPLATES = load_templates()

# ── Elasticsearch client ───────────────────────────────────────────────────────
def get_es_client() -> Elasticsearch:
    return Elasticsearch(
        ES_HOST,
        basic_auth=(ES_USER, ES_PASS),
        verify_certs=False,
        ssl_show_warn=False,
        retry_on_timeout=True,
        max_retries=3,
    )


# ── Email helper ───────────────────────────────────────────────────────────────
def send_alert_email(subject: str, body: str, recipients: list[str] | None = None) -> bool:
    """Send an alert email via SMTP.

    Args:
        subject: Email subject line.
        body: Plain-text email body.
        recipients: List of recipient email addresses. Falls back to ALERT_RECIPIENTS if None.

    Returns:
        True if the email was accepted by the SMTP server, False otherwise.
    """
    if not SMTP_USER or not SMTP_PASS:
        logger.warning("SMTP credentials not configured – skipping email send.")
        return False

    target = recipients or ALERT_RECIPIENTS
    if not target:
        logger.warning("No alert recipients configured – skipping email send.")
        return False

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM
    msg["To"] = ", ".join(target)
    msg.attach(MIMEText(body, "plain"))

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.sendmail(SMTP_FROM, target, msg.as_string())
        logger.info("Alert email sent to %s: %s", target, subject)
        return True
    except smtplib.SMTPException as exc:
        logger.error("Failed to send alert email: %s", exc)
        return False


# ── Format template ────────────────────────────────────────────────────────────
def format_alert(template_key: str, context: dict) -> tuple[str, str]:
    tmpl = TEMPLATES.get(template_key, {})
    subject = tmpl.get("subject", f"[SOC ALERT] {template_key}")
    body = tmpl.get("body", json.dumps(context, indent=2))
    for k, v in context.items():
        subject = subject.replace(f"{{{k}}}", str(v))
        body = body.replace(f"{{{k}}}", str(v))
    return subject, body


# ── Alert checks ───────────────────────────────────────────────────────────────
def check_failed_logins(es: Elasticsearch) -> None:
    """Query Wazuh indices for brute-force events in the last 5 minutes."""
    now = datetime.now(timezone.utc)
    five_min_ago = (now - timedelta(minutes=5)).isoformat()

    try:
        resp = es.search(
            index="wazuh-alerts-*",
            body={
                "query": {
                    "bool": {
                        "must": [
                            {"range": {"@timestamp": {"gte": five_min_ago}}},
                            {"terms": {"rule.groups": ["soc_high_priority", "brute_force"]}},
                        ]
                    }
                },
                "aggs": {
                    "by_source_ip": {
                        "terms": {"field": "data.srcip", "size": 20},
                        "aggs": {"by_host": {"terms": {"field": "agent.name", "size": 5}}},
                    }
                },
                "size": 0,
            },
            ignore_unavailable=True,
        )

        for bucket in resp.get("aggregations", {}).get("by_source_ip", {}).get("buckets", []):
            count = bucket["doc_count"]
            src_ip = bucket["key"]
            hostname = (
                bucket.get("by_host", {}).get("buckets", [{"key": "unknown"}])[0]["key"]
            )
            if count >= FAILED_LOGIN_THRESHOLD:
                logger.warning(
                    "Brute-force detected: %d attempts from %s on %s", count, src_ip, hostname
                )
                subject, body = format_alert(
                    "failed_logins",
                    {
                        "hostname": hostname,
                        "source_ip": src_ip,
                        "attempt_count": count,
                        "timeframe": 5,
                        "threshold": FAILED_LOGIN_THRESHOLD,
                        "targeted_user": "multiple",
                        "protocol": "SSH",
                        "timestamp": now.strftime("%Y-%m-%d %H:%M:%S UTC"),
                    },
                )
                send_alert_email(subject, body)

    except Exception as exc:
        logger.error("Error checking failed logins: %s", exc)


def check_critical_security_events(es: Elasticsearch) -> None:
    """Query Wazuh indices for critical-level security events in the last minute."""
    now = datetime.now(timezone.utc)
    one_min_ago = (now - timedelta(minutes=1)).isoformat()

    try:
        resp = es.search(
            index="wazuh-alerts-*",
            body={
                "query": {
                    "bool": {
                        "must": [
                            {"range": {"@timestamp": {"gte": one_min_ago}}},
                            {"range": {"rule.level": {"gte": 12}}},
                        ]
                    }
                },
                "sort": [{"rule.level": {"order": "desc"}}],
                "size": 10,
            },
            ignore_unavailable=True,
        )

        for hit in resp.get("hits", {}).get("hits", []):
            src = hit["_source"]
            rule = src.get("rule", {})
            agent = src.get("agent", {})
            data = src.get("data", {})

            logger.warning(
                "Critical security event (level %s): %s on %s",
                rule.get("level"),
                rule.get("description"),
                agent.get("name"),
            )

            subject, body = format_alert(
                "unauthorized_access",
                {
                    "hostname": agent.get("name", "unknown"),
                    "username": data.get("srcuser", "unknown"),
                    "action": rule.get("description", "Security event"),
                    "source_ip": data.get("srcip", "unknown"),
                    "rule_id": rule.get("id", ""),
                    "rule_description": rule.get("description", ""),
                    "mitre_id": ", ".join(
                        rule.get("mitre", {}).get("id", ["N/A"])
                    ),
                    "timestamp": now.strftime("%Y-%m-%d %H:%M:%S UTC"),
                },
            )
            send_alert_email(subject, body)

    except Exception as exc:
        logger.error("Error checking critical security events: %s", exc)


def health_check(es: Elasticsearch) -> None:
    """Log Elasticsearch cluster health."""
    try:
        health = es.cluster.health()
        status = health.get("status", "unknown")
        if status == "red":
            logger.error("Elasticsearch cluster health is RED!")
        elif status == "yellow":
            logger.warning("Elasticsearch cluster health is YELLOW.")
        else:
            logger.info("Elasticsearch cluster health: %s", status)
    except Exception as exc:
        logger.error("Cannot reach Elasticsearch: %s", exc)


# ── Main loop ──────────────────────────────────────────────────────────────────
def run_checks() -> None:
    es = get_es_client()
    health_check(es)
    check_failed_logins(es)
    check_critical_security_events(es)


def main() -> None:
    logger.info("SOC Alerting Service starting …")
    logger.info("Elasticsearch: %s", ES_HOST)
    logger.info("SMTP host: %s:%d", SMTP_HOST, SMTP_PORT)
    logger.info("Alert recipients: %s", ALERT_RECIPIENTS)
    logger.info("Thresholds — CPU: %s%%, Memory: %s%%, Disk: %s%%, Failed logins: %s",
                CPU_THRESHOLD, MEMORY_THRESHOLD, DISK_THRESHOLD, FAILED_LOGIN_THRESHOLD)

    # Wait for Elasticsearch to be ready
    for attempt in range(1, 31):
        try:
            es = get_es_client()
            es.cluster.health(wait_for_status="yellow", timeout="5s")
            logger.info("Elasticsearch is ready.")
            break
        except Exception as exc:
            logger.info("Waiting for Elasticsearch (attempt %d/30): %s", attempt, exc)
            time.sleep(10)
    else:
        logger.error("Elasticsearch not available after 5 minutes – exiting.")
        raise SystemExit(1)

    # Schedule checks
    schedule.every(1).minutes.do(run_checks)

    logger.info("Alerting service is running. Checks every 60 seconds.")
    run_checks()  # Run immediately on startup

    while True:
        schedule.run_pending()
        time.sleep(5)


if __name__ == "__main__":
    main()
