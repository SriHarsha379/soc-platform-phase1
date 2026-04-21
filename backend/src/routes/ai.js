const express = require('express');
const requireAuth = require('../middleware/auth');
const { authenticatedRouteLimiter } = require('../middleware/rateLimit');
const { analyzeEvent, checkHealth } = require('../lib/aiClient');

const router = express.Router();

// GET /api/ai/health  – check whether the AI service is reachable
router.get('/health', authenticatedRouteLimiter, requireAuth(['admin', 'analyst']), async (req, res) => {
  const reachable = await checkHealth();
  return res.json({
    aiService: reachable ? 'ok' : 'unavailable',
    url: process.env.AI_SERVICE_URL || 'http://localhost:8000',
  });
});

// POST /api/ai/analyze  – proxy a single log event to the AI service
router.post(
  '/analyze',
  authenticatedRouteLimiter,
  requireAuth(['admin', 'analyst']),
  async (req, res) => {
    const { event_type, value, window_minutes, source_ip } = req.body;

    if (!event_type || value === undefined) {
      return res.status(400).json({ error: 'event_type and value are required' });
    }

    const numValue = Number(value);
    if (!Number.isFinite(numValue) || numValue < 0) {
      return res.status(400).json({ error: 'value must be a non-negative number' });
    }

    const result = await analyzeEvent(
      String(event_type),
      numValue,
      Number(window_minutes) || 5,
      source_ip || null
    );

    if (!result) {
      return res.status(502).json({ error: 'AI service is unavailable' });
    }

    return res.json(result);
  }
);

module.exports = router;
