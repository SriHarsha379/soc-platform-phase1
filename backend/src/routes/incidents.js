const express = require('express');
const prisma = require('../lib/prisma');
const requireAuth = require('../middleware/auth');
const { authenticatedRouteLimiter } = require('../middleware/rateLimit');
const { runCorrelation } = require('../services/correlationService');

const router = express.Router();

// GET /api/incidents
// Query params: severity, status, ruleType, from (ISO), to (ISO), take, skip
router.get('/', authenticatedRouteLimiter, requireAuth(['admin', 'analyst']), async (req, res) => {
  const {
    severity,
    status,
    ruleType,
    from,
    to,
    take = '50',
    skip = '0',
  } = req.query;

  const where = { tenantId: req.user.tenantId };

  if (severity) where.severity = severity;
  if (status) where.status = status;
  if (ruleType) where.ruleType = ruleType;

  if (from || to) {
    where.firstSeen = {};
    if (from) where.firstSeen.gte = new Date(from);
    if (to) where.firstSeen.lte = new Date(to);
  }

  const [incidents, total] = await prisma.$transaction([
    prisma.incident.findMany({
      where,
      orderBy: { lastSeen: 'desc' },
      take: Math.min(Number(take) || 50, 200),
      skip: Number(skip) || 0,
    }),
    prisma.incident.count({ where }),
  ]);

  return res.json({ total, incidents });
});

// POST /api/incidents/correlate  (admin only – triggers a correlation run)
router.post(
  '/correlate',
  authenticatedRouteLimiter,
  requireAuth(['admin']),
  async (req, res) => {
    const results = await runCorrelation(req.user.tenantId);
    return res.json({
      triggered: results.length,
      incidents: results,
    });
  }
);

// PATCH /api/incidents/:id  (update status – admin or analyst)
router.patch(
  '/:id',
  authenticatedRouteLimiter,
  requireAuth(['admin', 'analyst']),
  async (req, res) => {
    const id = Number(req.params.id);
    const { status } = req.body;

    const allowed = ['open', 'investigating', 'resolved'];
    if (!status || !allowed.includes(status)) {
      return res.status(400).json({ error: `status must be one of: ${allowed.join(', ')}` });
    }

    // Enforce tenant isolation: only update incidents belonging to the caller's tenant
    const incident = await prisma.incident.findUnique({ where: { id } });
    if (!incident) {
      return res.status(404).json({ error: 'Incident not found' });
    }
    if (incident.tenantId !== req.user.tenantId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    const updated = await prisma.incident.update({
      where: { id },
      data: { status },
    });

    return res.json(updated);
  }
);

module.exports = router;
