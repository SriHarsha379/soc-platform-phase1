/**
 * Correlation Service
 *
 * Reads normalised log events from Elasticsearch and applies correlation rules
 * to produce Incident records stored in the database.
 *
 * Rules implemented:
 *   1. brute_force      – ≥N failed auth events from the same source IP in a time window
 *   2. traffic_spike    – total event count exceeds threshold within a short window
 */

const esClient = require('../lib/elasticsearch');
const prisma = require('../lib/prisma');

// ── Defaults (overridable via environment variables) ─────────────────────────

const BRUTE_FORCE_THRESHOLD = Number(process.env.CORRELATION_BRUTE_FORCE_THRESHOLD) || 5;
const BRUTE_FORCE_WINDOW_MIN = Number(process.env.CORRELATION_BRUTE_FORCE_WINDOW_MIN) || 10;
const TRAFFIC_SPIKE_THRESHOLD = Number(process.env.CORRELATION_TRAFFIC_SPIKE_THRESHOLD) || 500;
const TRAFFIC_SPIKE_WINDOW_MIN = Number(process.env.CORRELATION_TRAFFIC_SPIKE_WINDOW_MIN) || 5;
const ES_INDEX = process.env.ELASTIC_INDEX || 'wazuh-alerts-*';

// ── Log normalisation ─────────────────────────────────────────────────────────

/**
 * Map a raw Elasticsearch hit (_source) to a common internal log format.
 * Keeps only the fields the correlation engine needs.
 */
function normalizeLog(source) {
  return {
    timestamp: source['@timestamp'] || source.timestamp || new Date().toISOString(),
    sourceIp: source.data?.srcip || source.data?.src_ip || source.agent?.ip || null,
    agentName: source.agent?.name || source.manager?.name || 'unknown',
    ruleId: source.rule?.id || null,
    ruleLevel: Number(source.rule?.level) || 0,
    ruleDescription: source.rule?.description || '',
    groups: source.rule?.groups || [],
    fullLog: source.full_log || '',
  };
}

// ── Elasticsearch helpers ─────────────────────────────────────────────────────

async function fetchRecentLogs(windowMinutes, extraFilters = []) {
  const from = new Date(Date.now() - windowMinutes * 60 * 1000).toISOString();

  try {
    const response = await esClient.search({
      index: ES_INDEX,
      size: 1000,
      query: {
        bool: {
          must: [{ range: { '@timestamp': { gte: from } } }],
          filter: extraFilters,
        },
      },
      sort: [{ '@timestamp': { order: 'asc' } }],
    });

    return (response.hits?.hits || []).map((hit) => normalizeLog(hit._source));
  } catch {
    // Elasticsearch unavailable – return empty set so rules produce no incidents
    return [];
  }
}

// ── Correlation rules ─────────────────────────────────────────────────────────

/**
 * Rule 1: Brute-force / multiple failed logins from the same IP.
 *
 * Looks for auth-failure events and groups them by source IP.
 * If an IP exceeds the threshold within the window it creates (or updates) an
 * open incident.
 */
async function ruleBruteForce() {
  const logs = await fetchRecentLogs(BRUTE_FORCE_WINDOW_MIN, [
    {
      terms: {
        'rule.groups': [
          'authentication_failed',
          'authentication_failures',
          'sshd',
          'pam',
          'windows_security',
        ],
      },
    },
  ]);

  // Group by source IP
  const byIp = {};
  for (const log of logs) {
    const ip = log.sourceIp || 'unknown';
    if (!byIp[ip]) byIp[ip] = [];
    byIp[ip].push(log);
  }

  const created = [];

  for (const [ip, events] of Object.entries(byIp)) {
    if (events.length < BRUTE_FORCE_THRESHOLD) continue;

    const firstSeen = new Date(events[0].timestamp);
    const lastSeen = new Date(events[events.length - 1].timestamp);
    const severity = events.length >= 20 ? 'critical' : events.length >= 10 ? 'high' : 'medium';

    // Upsert: if there is already an open incident for this IP and rule type,
    // update the event count and lastSeen rather than duplicating.
    const existing = await prisma.incident.findFirst({
      where: {
        ruleType: 'brute_force',
        sourceIp: ip,
        status: { in: ['open', 'investigating'] },
      },
      orderBy: { createdAt: 'desc' },
    });

    if (existing) {
      const updated = await prisma.incident.update({
        where: { id: existing.id },
        data: {
          eventCount: events.length,
          lastSeen,
          severity,
          updatedAt: new Date(),
        },
      });
      created.push(updated);
    } else {
      const incident = await prisma.incident.create({
        data: {
          title: `Brute-force attack detected from ${ip}`,
          description: `${events.length} failed authentication attempts detected from ${ip} within the last ${BRUTE_FORCE_WINDOW_MIN} minutes.`,
          severity,
          ruleType: 'brute_force',
          sourceIp: ip,
          affectedHost: events[0].agentName,
          eventCount: events.length,
          firstSeen,
          lastSeen,
        },
      });
      created.push(incident);
    }
  }

  return created;
}

/**
 * Rule 2: Traffic spike – unusual volume of events in a short window.
 *
 * Counts all events in the window. If the total exceeds the threshold, a
 * single traffic-spike incident is created (or the existing open one updated).
 */
async function ruleTrafficSpike() {
  const logs = await fetchRecentLogs(TRAFFIC_SPIKE_WINDOW_MIN);

  if (logs.length < TRAFFIC_SPIKE_THRESHOLD) return [];

  const severity =
    logs.length >= TRAFFIC_SPIKE_THRESHOLD * 3
      ? 'critical'
      : logs.length >= TRAFFIC_SPIKE_THRESHOLD * 2
        ? 'high'
        : 'medium';
  const firstSeen = new Date(logs[0].timestamp);
  const lastSeen = new Date(logs[logs.length - 1].timestamp);

  const existing = await prisma.incident.findFirst({
    where: {
      ruleType: 'traffic_spike',
      status: { in: ['open', 'investigating'] },
    },
    orderBy: { createdAt: 'desc' },
  });

  if (existing) {
    const updated = await prisma.incident.update({
      where: { id: existing.id },
      data: { eventCount: logs.length, lastSeen, severity, updatedAt: new Date() },
    });
    return [updated];
  }

  const incident = await prisma.incident.create({
    data: {
      title: `Traffic spike: ${logs.length} events in ${TRAFFIC_SPIKE_WINDOW_MIN} minutes`,
      description: `Unusual event volume detected: ${logs.length} events processed in the last ${TRAFFIC_SPIKE_WINDOW_MIN} minutes (threshold: ${TRAFFIC_SPIKE_THRESHOLD}).`,
      severity,
      ruleType: 'traffic_spike',
      eventCount: logs.length,
      firstSeen,
      lastSeen,
    },
  });

  return [incident];
}

// ── Public API ────────────────────────────────────────────────────────────────

/**
 * Run all correlation rules and return the list of created/updated incidents.
 */
async function runCorrelation() {
  const [bruteForceIncidents, spikeIncidents] = await Promise.all([
    ruleBruteForce(),
    ruleTrafficSpike(),
  ]);

  return [...bruteForceIncidents, ...spikeIncidents];
}

module.exports = { runCorrelation, normalizeLog };
