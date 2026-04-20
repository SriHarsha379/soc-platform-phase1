const express = require('express');
const prisma = require('../lib/prisma');
const requireAuth = require('../middleware/auth');

const router = express.Router();

router.get('/', requireAuth(['admin', 'analyst']), async (req, res) => {
  const { severity, status, take = '50', skip = '0' } = req.query;

  const where = {};
  if (severity) where.severity = severity;
  if (status) where.status = status;

  const alerts = await prisma.alert.findMany({
    where,
    orderBy: { createdAt: 'desc' },
    take: Math.min(Number(take) || 50, 200),
    skip: Number(skip) || 0,
  });

  return res.json(alerts);
});

module.exports = router;
