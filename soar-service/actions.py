"""
SOAR action handlers.

Each handler receives a rendered params dict and returns a result dict with
a 'status' key: success | simulated | skipped | error.

Simulated means the action would have run but a required external resource
(iptables, SMTP, Telegram) is not configured. All failures are non-fatal so
the engine can continue with the next action.
"""

from __future__ import annotations

import logging
import os
import smtplib
import subprocess
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any

import httpx

logger = logging.getLogger("soar.actions")

# ── Email config ───────────────────────────────────────────────────────────────
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASS = os.getenv("SMTP_PASSWORD", "")
SMTP_FROM = os.getenv("SMTP_FROM", "soc-alerts@yourdomain.com")
ALERT_RECIPIENTS = [r.strip() for r in os.getenv("ALERT_RECIPIENTS", "").split(",") if r.strip()]

# ── Telegram config ────────────────────────────────────────────────────────────
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "")


def block_ip(params: dict[str, Any]) -> dict:
    """Block an IP via iptables.

    Degrades gracefully when iptables is unavailable (e.g. unprivileged
    container or development environment): returns status='simulated' with the
    command that *would* have been executed, so the audit log is always useful.
    """
    ip = params.get("ip", "")
    comment = params.get("comment", "SOC auto-block")
    duration = int(params.get("duration_seconds", 3600))

    if not ip or ip in ("unknown", "None", "null", ""):
        return {"status": "skipped", "reason": "No valid IP to block"}

    cmd = [
        "iptables", "-I", "INPUT", "1",
        "-s", ip,
        "-j", "DROP",
        "-m", "comment",
        "--comment", comment,
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            logger.info("Blocked IP %s for %d s", ip, duration)
            return {
                "status": "success",
                "ip": ip,
                "duration_seconds": duration,
                "command": " ".join(cmd),
            }
        # iptables ran but failed (e.g. permissions)
        note = result.stderr.strip() or "iptables returned non-zero"
        logger.warning("iptables non-zero for %s: %s", ip, note)
        return {
            "status": "simulated",
            "ip": ip,
            "duration_seconds": duration,
            "command": " ".join(cmd),
            "note": note,
        }
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        logger.info("iptables unavailable, simulating block of %s: %s", ip, exc)
        return {
            "status": "simulated",
            "ip": ip,
            "duration_seconds": duration,
            "command": " ".join(cmd),
            "note": str(exc),
        }


def send_email(params: dict[str, Any]) -> dict:
    """Send an email alert via SMTP."""
    subject = params.get("subject", "[SOC SOAR] Alert")
    body = params.get("body", "")
    recipients = params.get("recipients") or ALERT_RECIPIENTS

    if not SMTP_USER or not SMTP_PASS:
        logger.info("SMTP not configured – simulating email: %s", subject)
        return {
            "status": "simulated",
            "subject": subject,
            "note": "SMTP credentials not configured",
        }

    if not recipients:
        return {"status": "skipped", "reason": "No email recipients configured"}

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = SMTP_FROM
    msg["To"] = ", ".join(recipients)
    msg.attach(MIMEText(body, "plain"))

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.sendmail(SMTP_FROM, recipients, msg.as_string())
        logger.info("Email sent to %s: %s", recipients, subject)
        return {"status": "success", "subject": subject, "recipients": recipients}
    except smtplib.SMTPException as exc:
        logger.error("Email failed: %s", exc)
        return {"status": "error", "error": str(exc)}


def send_telegram(params: dict[str, Any]) -> dict:
    """Send a Telegram message via Bot API."""
    message = params.get("message", "[SOC SOAR] Alert")

    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        logger.info("Telegram not configured – simulating message")
        return {
            "status": "simulated",
            "message": message,
            "note": "TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not configured",
        }

    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    try:
        resp = httpx.post(
            url,
            json={"chat_id": TELEGRAM_CHAT_ID, "text": message, "parse_mode": ""},
            timeout=10,
        )
        if resp.is_success:
            return {"status": "success", "message": message}
        return {"status": "error", "error": resp.text}
    except httpx.RequestError as exc:
        return {"status": "error", "error": str(exc)}
