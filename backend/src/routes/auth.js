const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const prisma = require('../lib/prisma');
const requireAuth = require('../middleware/auth');
const { authenticatedRouteLimiter, loginLimiter } = require('../middleware/rateLimit');

const router = express.Router();

router.post('/login', loginLimiter, async (req, res) => {
  const { email, password, tenantSlug } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password are required' });
  }

  // Resolve tenant – if a slug is provided, look it up; otherwise fall back to
  // finding the user by email alone (works when email is globally unique).
  let tenant = null;
  if (tenantSlug) {
    tenant = await prisma.tenant.findUnique({ where: { slug: tenantSlug } });
    if (!tenant) {
      return res.status(401).json({ error: 'Tenant not found' });
    }
  }

  const user = tenant
    ? await prisma.user.findUnique({
        where: { email_tenantId: { email, tenantId: tenant.id } },
        include: { tenant: { select: { id: true, name: true, slug: true } } },
      })
    : await prisma.user.findFirst({
        where: { email },
        include: { tenant: { select: { id: true, name: true, slug: true } } },
      });

  if (!user) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const validPassword = await bcrypt.compare(password, user.password);
  if (!validPassword) {
    return res.status(401).json({ error: 'Invalid credentials' });
  }

  const token = jwt.sign(
    {
      sub: user.id,
      email: user.email,
      role: user.role,
      tenantId: user.tenantId,
      tenantSlug: user.tenant?.slug,
    },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '8h' }
  );

  return res.json({
    token,
    user: {
      id: user.id,
      email: user.email,
      role: user.role,
      tenantId: user.tenantId,
      tenantName: user.tenant?.name,
      tenantSlug: user.tenant?.slug,
    },
  });
});

router.get('/me', authenticatedRouteLimiter, requireAuth(), async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: Number(req.user.sub) },
    select: {
      id: true,
      email: true,
      role: true,
      createdAt: true,
      tenant: { select: { id: true, name: true, slug: true } },
    },
  });

  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }

  return res.json({
    ...user,
    tenantId: user.tenant?.id,
    tenantName: user.tenant?.name,
    tenantSlug: user.tenant?.slug,
  });
});

module.exports = router;
