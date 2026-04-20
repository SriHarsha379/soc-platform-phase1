const bcrypt = require('bcryptjs');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  // ── Default tenant ───────────────────────────────────────────────────────
  let defaultTenant = await prisma.tenant.findUnique({ where: { slug: 'default' } });
  if (!defaultTenant) {
    defaultTenant = await prisma.tenant.create({
      data: { id: 1, name: 'Default Tenant', slug: 'default' },
    });
    console.log('Created default tenant (id=1)');
  }

  // ── Demo tenant (acme) ───────────────────────────────────────────────────
  let acmeTenant = await prisma.tenant.findUnique({ where: { slug: 'acme' } });
  if (!acmeTenant) {
    acmeTenant = await prisma.tenant.create({
      data: { name: 'Acme Corp', slug: 'acme' },
    });
    console.log('Created demo tenant: acme');
  }

  // ── Users ────────────────────────────────────────────────────────────────
  const users = [
    // Default tenant users
    { email: 'superadmin@soc.local', password: 'SuperAdmin@123', role: 'super_admin', tenantId: 1 },
    { email: 'admin@soc.local', password: 'Admin@123', role: 'admin', tenantId: 1 },
    { email: 'analyst@soc.local', password: 'Analyst@123', role: 'analyst', tenantId: 1 },
    // Acme tenant users
    { email: 'admin@acme.local', password: 'AcmeAdmin@123', role: 'admin', tenantId: acmeTenant.id },
    { email: 'analyst@acme.local', password: 'AcmeAnalyst@123', role: 'analyst', tenantId: acmeTenant.id },
  ];

  for (const user of users) {
    const hashedPassword = await bcrypt.hash(user.password, 10);
    await prisma.user.upsert({
      where: { email_tenantId: { email: user.email, tenantId: user.tenantId } },
      update: { role: user.role, password: hashedPassword },
      create: {
        email: user.email,
        role: user.role,
        password: hashedPassword,
        tenantId: user.tenantId,
      },
    });
  }

  // ── Alerts ───────────────────────────────────────────────────────────────
  const alertCount = await prisma.alert.count({ where: { tenantId: 1 } });
  if (alertCount === 0) {
    await prisma.alert.createMany({
      data: [
        {
          title: 'High CPU usage detected',
          description: 'CPU usage exceeded 90% in the last 5 minutes',
          severity: 'high',
          status: 'open',
          source: 'zabbix',
          tenantId: 1,
        },
        {
          title: 'Multiple failed SSH logins',
          description: 'Detected repeated failed SSH login attempts',
          severity: 'critical',
          status: 'investigating',
          source: 'wazuh',
          tenantId: 1,
        },
      ],
    });
  }

  const acmeAlertCount = await prisma.alert.count({ where: { tenantId: acmeTenant.id } });
  if (acmeAlertCount === 0) {
    await prisma.alert.createMany({
      data: [
        {
          title: '[Acme] Suspicious login from unknown IP',
          description: 'Login detected from an IP not in the allowlist',
          severity: 'medium',
          status: 'open',
          source: 'wazuh',
          tenantId: acmeTenant.id,
        },
      ],
    });
  }

  // ── LogMeta ──────────────────────────────────────────────────────────────
  const logMetaCount = await prisma.logMeta.count({ where: { tenantId: 1 } });
  if (logMetaCount === 0) {
    await prisma.logMeta.createMany({
      data: [
        {
          logType: 'auth',
          source: 'wazuh',
          severity: 'warning',
          referenceId: 'sample-auth-001',
          timestamp: new Date(),
          tenantId: 1,
        },
        {
          logType: 'system',
          source: 'zabbix',
          severity: 'info',
          referenceId: 'sample-system-001',
          timestamp: new Date(),
          tenantId: 1,
        },
      ],
    });
  }

  console.log('Seed complete: default users and sample alerts/log metadata created.');

  // ── Incidents ────────────────────────────────────────────────────────────
  const incidentCount = await prisma.incident.count({ where: { tenantId: 1 } });
  if (incidentCount === 0) {
    const now = new Date();
    await prisma.incident.createMany({
      data: [
        {
          title: 'Brute-force attack detected from 203.0.113.42',
          description: '12 failed SSH authentication attempts from 203.0.113.42 within 10 minutes.',
          severity: 'high',
          ruleType: 'brute_force',
          status: 'open',
          sourceIp: '203.0.113.42',
          affectedHost: 'web-01',
          eventCount: 12,
          tenantId: 1,
          firstSeen: new Date(now.getTime() - 15 * 60 * 1000),
          lastSeen: new Date(now.getTime() - 5 * 60 * 1000),
        },
        {
          title: 'Brute-force attack detected from 198.51.100.7',
          description: '23 failed login attempts from 198.51.100.7 within 10 minutes.',
          severity: 'critical',
          ruleType: 'brute_force',
          status: 'investigating',
          sourceIp: '198.51.100.7',
          affectedHost: 'db-01',
          eventCount: 23,
          tenantId: 1,
          firstSeen: new Date(now.getTime() - 30 * 60 * 1000),
          lastSeen: new Date(now.getTime() - 2 * 60 * 1000),
        },
        {
          title: 'Traffic spike: 620 events in 5 minutes',
          description: 'Unusual event volume: 620 events in the last 5 minutes (threshold: 500).',
          severity: 'medium',
          ruleType: 'traffic_spike',
          status: 'open',
          eventCount: 620,
          tenantId: 1,
          firstSeen: new Date(now.getTime() - 6 * 60 * 1000),
          lastSeen: new Date(now.getTime() - 1 * 60 * 1000),
        },
        {
          title: 'Brute-force attack detected from 10.0.0.55',
          description: '7 failed authentication attempts from 10.0.0.55 within 10 minutes.',
          severity: 'medium',
          ruleType: 'brute_force',
          status: 'resolved',
          sourceIp: '10.0.0.55',
          affectedHost: 'app-01',
          eventCount: 7,
          tenantId: 1,
          firstSeen: new Date(now.getTime() - 120 * 60 * 1000),
          lastSeen: new Date(now.getTime() - 100 * 60 * 1000),
        },
      ],
    });
  }

  const acmeIncidentCount = await prisma.incident.count({ where: { tenantId: acmeTenant.id } });
  if (acmeIncidentCount === 0) {
    const now = new Date();
    await prisma.incident.createMany({
      data: [
        {
          title: '[Acme] Port scan detected from 10.20.30.40',
          description: 'Rapid connection attempts to multiple ports from 10.20.30.40.',
          severity: 'high',
          ruleType: 'brute_force',
          status: 'open',
          sourceIp: '10.20.30.40',
          affectedHost: 'acme-fw-01',
          eventCount: 8,
          tenantId: acmeTenant.id,
          firstSeen: new Date(now.getTime() - 20 * 60 * 1000),
          lastSeen: new Date(now.getTime() - 10 * 60 * 1000),
        },
      ],
    });
  }

  console.log('Seed complete: sample incidents created.');
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
