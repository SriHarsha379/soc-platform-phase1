/**
 * AI Service Client
 *
 * Thin wrapper around the soc-ai FastAPI service.
 * All failures are non-blocking — if the service is unavailable the call
 * returns null so the rest of the pipeline continues normally.
 */

const AI_SERVICE_URL = process.env.AI_SERVICE_URL || 'http://localhost:8000';

/**
 * Send a log-event observation to the AI service for scoring.
 *
 * @param {string} eventType   - login_attempt | cpu_usage | network_traffic
 * @param {number} value       - The observed metric value
 * @param {number} [windowMin] - Observation window in minutes
 * @param {string} [sourceIp]  - Source IP (informational)
 * @returns {Promise<{risk_score:number, is_anomaly:boolean, severity:string, reason:string}|null>}
 */
async function analyzeEvent(eventType, value, windowMin = 5, sourceIp = null) {
  try {
    const response = await fetch(`${AI_SERVICE_URL}/analyze`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        event_type: eventType,
        value,
        window_minutes: windowMin,
        source_ip: sourceIp,
      }),
      signal: AbortSignal.timeout(5000), // 5 s timeout
    });

    if (!response.ok) return null;
    return await response.json();
  } catch {
    // AI service unavailable – degrade gracefully
    return null;
  }
}

/**
 * Check whether the AI service is reachable.
 * @returns {Promise<boolean>}
 */
async function checkHealth() {
  try {
    const response = await fetch(`${AI_SERVICE_URL}/health`, {
      signal: AbortSignal.timeout(3000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

module.exports = { analyzeEvent, checkHealth };
