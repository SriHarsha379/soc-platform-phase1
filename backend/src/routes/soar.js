const express = require('express');
const requireAuth = require('../middleware/auth');
const { authenticatedRouteLimiter } = require('../middleware/rateLimit');
const { checkHealth, getPlaybooks, getExecutions } = require('../lib/soarClient');

const router = express.Router();

// GET /api/soar/health
router.get('/health', authenticatedRouteLimiter, requireAuth(['admin', 'analyst']), async (req, res) => {
  const reachable = await checkHealth();
  return res.json({
    soarService: reachable ? 'ok' : 'unavailable',
    url: process.env.SOAR_SERVICE_URL || 'http://localhost:8001',
  });
});

// GET /api/soar/playbooks
router.get('/playbooks', authenticatedRouteLimiter, requireAuth(['admin', 'analyst']), async (req, res) => {
  const playbooks = await getPlaybooks();
  if (!playbooks) {
    return res.status(502).json({ error: 'SOAR service is unavailable' });
  }
  return res.json(playbooks);
});

// GET /api/soar/executions
router.get('/executions', authenticatedRouteLimiter, requireAuth(['admin', 'analyst']), async (req, res) => {
  const limit = Math.min(Number(req.query.limit) || 100, 500);
  const executions = await getExecutions(limit);
  if (!executions) {
    return res.status(502).json({ error: 'SOAR service is unavailable' });
  }
  return res.json(executions);
});

module.exports = router;
