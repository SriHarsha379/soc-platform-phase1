/**
 * SOAR Service Client
 *
 * Thin wrapper around the soc-soar FastAPI service.
 * All failures are non-blocking — if the service is unavailable the call
 * returns null so the rest of the pipeline continues normally.
 */

const SOAR_SERVICE_URL = process.env.SOAR_SERVICE_URL || 'http://localhost:8001';

/**
 * Trigger playbook evaluation for a given incident.
 *
 * @param {object} incident - Prisma Incident record
 * @returns {Promise<{triggered:number, executions:Array}|null>}
 */
async function triggerPlaybooks(incident) {
  try {
    const response = await fetch(`${SOAR_SERVICE_URL}/trigger`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        ...incident,
        // Ensure Date objects are serialised as ISO strings
        firstSeen: incident.firstSeen instanceof Date
          ? incident.firstSeen.toISOString()
          : incident.firstSeen,
        lastSeen: incident.lastSeen instanceof Date
          ? incident.lastSeen.toISOString()
          : incident.lastSeen,
      }),
      // Actions can be slow (iptables, SMTP) – allow up to 15 s
      signal: AbortSignal.timeout(15000),
    });

    if (!response.ok) return null;
    return await response.json();
  } catch {
    // SOAR service unavailable – degrade gracefully
    return null;
  }
}

/**
 * Fetch all SOAR playbook definitions.
 * @returns {Promise<Array|null>}
 */
async function getPlaybooks() {
  try {
    const response = await fetch(`${SOAR_SERVICE_URL}/playbooks`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

/**
 * Fetch SOAR execution audit log.
 * @param {number} [limit=100]
 * @returns {Promise<Array|null>}
 */
async function getExecutions(limit = 100) {
  try {
    const response = await fetch(`${SOAR_SERVICE_URL}/executions?limit=${limit}`, {
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return null;
    return await response.json();
  } catch {
    return null;
  }
}

/**
 * Check whether the SOAR service is reachable.
 * @returns {Promise<boolean>}
 */
async function checkHealth() {
  try {
    const response = await fetch(`${SOAR_SERVICE_URL}/health`, {
      signal: AbortSignal.timeout(3000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

module.exports = { triggerPlaybooks, getPlaybooks, getExecutions, checkHealth };
