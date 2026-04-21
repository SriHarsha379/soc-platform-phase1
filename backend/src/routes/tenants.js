const express = require('express');
const bcrypt = require('bcryptjs');
const prisma = require('../lib/prisma');
const requireAuth = require('../middleware/auth');
const { authenticatedRouteLimiter } = require('../middleware/rateLimit');

const router = express.Router();

// ── Helper ────────────────────────────────────────────────────────────────────

/**
 * Ensure the caller is either a super_admin (any tenant) or an admin of the
 * specific tenant identified by :id. Returns the tenant or sends an error response.
 */
async function resolveTenantAccess(req, res) {
  const tenantId = Number(req.params.id);
  if (!tenantId) {
    res.status(400).json({ error: 'Invalid tenant id' });
    return null;
  }

  const tenant = await prisma.tenant.findUnique({ where: { id: tenantId } });
  if (!tenant) {
    res.status(404).json({ error: 'Tenant not found' });
    return null;
  }

  const isSuperAdmin = req.user.role === 'super_admin';
  const isAdminOfTenant = req.user.role === 'admin' && req.user.tenantId === tenantId;

  if (!isSuperAdmin && !isAdminOfTenant) {
    res.status(403).json({ error: 'Access denied' });
    return null;
  }

  return tenant;
}

// ── Tenant CRUD (super_admin only) ────────────────────────────────────────────

// GET /api/tenants – list all tenants
router.get(
  '/',
  authenticatedRouteLimiter,
  requireAuth(['super_admin']),
  async (req, res) => {
    const tenants = await prisma.tenant.findMany({
      orderBy: { createdAt: 'asc' },
      include: {
        _count: { select: { users: true, alerts: true, incidents: true } },
      },
    });
    return res.json(tenants);
  }
);

// POST /api/tenants – create a new tenant
router.post(
  '/',
  authenticatedRouteLimiter,
  requireAuth(['super_admin']),
  async (req, res) => {
    const { name, slug, adminEmail, adminPassword } = req.body;

    if (!name || !slug) {
      return res.status(400).json({ error: 'name and slug are required' });
    }
    // slug: lowercase letters, numbers, hyphens only
    if (!/^[a-z0-9-]+$/.test(slug)) {
      return res.status(400).json({
        error: 'slug must contain only lowercase letters, numbers, and hyphens',
      });
    }

    const existing = await prisma.tenant.findUnique({ where: { slug } });
    if (existing) {
      return res.status(409).json({ error: 'A tenant with that slug already exists' });
    }

    // Create the tenant and optionally its first admin user in one transaction
    const tenant = await prisma.$transaction(async (tx) => {
      const t = await tx.tenant.create({ data: { name, slug } });

      if (adminEmail && adminPassword) {
        const hashedPassword = await bcrypt.hash(adminPassword, 10);
        await tx.user.create({
          data: {
            email: adminEmail,
            password: hashedPassword,
            role: 'admin',
            tenantId: t.id,
          },
        });
      }

      return t;
    });

    return res.status(201).json(tenant);
  }
);

// GET /api/tenants/:id – get a single tenant
router.get(
  '/:id',
  authenticatedRouteLimiter,
  requireAuth(['admin', 'super_admin']),
  async (req, res) => {
    const tenant = await resolveTenantAccess(req, res);
    if (!tenant) return;

    const full = await prisma.tenant.findUnique({
      where: { id: tenant.id },
      include: {
        _count: { select: { users: true, alerts: true, incidents: true } },
      },
    });

    return res.json(full);
  }
);

// ── Per-tenant user management ────────────────────────────────────────────────

// GET /api/tenants/:id/users
router.get(
  '/:id/users',
  authenticatedRouteLimiter,
  requireAuth(['admin', 'super_admin']),
  async (req, res) => {
    const tenant = await resolveTenantAccess(req, res);
    if (!tenant) return;

    const users = await prisma.user.findMany({
      where: { tenantId: tenant.id },
      select: { id: true, email: true, role: true, createdAt: true },
      orderBy: { createdAt: 'asc' },
    });

    return res.json(users);
  }
);

// POST /api/tenants/:id/users – create a user inside a tenant
router.post(
  '/:id/users',
  authenticatedRouteLimiter,
  requireAuth(['admin', 'super_admin']),
  async (req, res) => {
    const tenant = await resolveTenantAccess(req, res);
    if (!tenant) return;

    const { email, password, role = 'analyst' } = req.body;

    if (!email || !password) {
      return res.status(400).json({ error: 'email and password are required' });
    }

    const allowedRoles = ['analyst', 'admin'];
    if (!allowedRoles.includes(role)) {
      return res.status(400).json({ error: `role must be one of: ${allowedRoles.join(', ')}` });
    }

    const existing = await prisma.user.findUnique({
      where: { email_tenantId: { email, tenantId: tenant.id } },
    });
    if (existing) {
      return res.status(409).json({ error: 'A user with that email already exists in this tenant' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: { email, password: hashedPassword, role, tenantId: tenant.id },
      select: { id: true, email: true, role: true, tenantId: true, createdAt: true },
    });

    return res.status(201).json(user);
  }
);

// DELETE /api/tenants/:id/users/:userId – remove a user from a tenant
router.delete(
  '/:id/users/:userId',
  authenticatedRouteLimiter,
  requireAuth(['admin', 'super_admin']),
  async (req, res) => {
    const tenant = await resolveTenantAccess(req, res);
    if (!tenant) return;

    const userId = Number(req.params.userId);
    const user = await prisma.user.findUnique({ where: { id: userId } });

    if (!user || user.tenantId !== tenant.id) {
      return res.status(404).json({ error: 'User not found in this tenant' });
    }
    // Prevent self-deletion
    if (user.id === req.user.sub) {
      return res.status(400).json({ error: 'You cannot delete your own account' });
    }

    await prisma.user.delete({ where: { id: userId } });
    return res.status(204).end();
  }
);

module.exports = router;
