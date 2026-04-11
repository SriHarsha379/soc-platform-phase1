-- ============================================================
-- Zabbix Alert Actions SQL Configuration
-- Import via: psql -U zabbix -d zabbix -f alert_actions.sql
-- ============================================================

-- ── Email Media Type ──────────────────────────────────────────────────────────
INSERT INTO media_type (
  mediatypeid, type, name, smtp_server, smtp_helo, smtp_email,
  smtp_port, smtp_security, smtp_verify_peer, smtp_verify_host,
  smtp_authentication, username, passwd, status, maxsessions,
  maxattempts, attempt_interval, message_format, description
) VALUES (
  1, 0, 'Email (SMTP)',
  'smtp.gmail.com', 'localhost', 'soc-alerts@yourdomain.com',
  587, 1, 0, 0, 1,
  'your-email@gmail.com', 'your-smtp-app-password',
  0, 1, 3, '10s', 1,
  'SOC Platform Email Notifications'
) ON CONFLICT (mediatypeid) DO UPDATE
  SET smtp_server = EXCLUDED.smtp_server,
      smtp_email  = EXCLUDED.smtp_email;

-- ── Action: High CPU Alert ────────────────────────────────────────────────────
INSERT INTO actions (
  actionid, name, eventsource, evaltype, status, pause_suppressed
) VALUES (
  1, 'SOC - High CPU Alert', 0, 0, 0, 1
) ON CONFLICT (actionid) DO NOTHING;

INSERT INTO operations (
  operationid, actionid, operationtype, esc_period, esc_step_from, esc_step_to
) VALUES (
  1, 1, 0, 0, 1, 1
) ON CONFLICT (operationid) DO NOTHING;

-- ── Action: Host Unreachable Alert ───────────────────────────────────────────
INSERT INTO actions (
  actionid, name, eventsource, evaltype, status, pause_suppressed
) VALUES (
  2, 'SOC - Host Unreachable Alert', 0, 0, 0, 1
) ON CONFLICT (actionid) DO NOTHING;

-- ── Action: Disk Space Critical Alert ────────────────────────────────────────
INSERT INTO actions (
  actionid, name, eventsource, evaltype, status, pause_suppressed
) VALUES (
  3, 'SOC - Disk Space Critical', 0, 0, 0, 1
) ON CONFLICT (actionid) DO NOTHING;

-- ── Action: Memory Usage Critical Alert ──────────────────────────────────────
INSERT INTO actions (
  actionid, name, eventsource, evaltype, status, pause_suppressed
) VALUES (
  4, 'SOC - Memory Usage Critical', 0, 0, 0, 1
) ON CONFLICT (actionid) DO NOTHING;
