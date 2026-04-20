const bcrypt = require('bcryptjs');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

async function main() {
  const users = [
    { email: 'admin@soc.local', password: 'Admin@123', role: 'admin' },
    { email: 'analyst@soc.local', password: 'Analyst@123', role: 'analyst' },
  ];

  for (const user of users) {
    const hashedPassword = await bcrypt.hash(user.password, 10);
    await prisma.user.upsert({
      where: { email: user.email },
      update: { role: user.role, password: hashedPassword },
      create: { email: user.email, role: user.role, password: hashedPassword },
    });
  }

  const alertCount = await prisma.alert.count();
  if (alertCount === 0) {
    await prisma.alert.createMany({
      data: [
        {
          title: 'High CPU usage detected',
          description: 'CPU usage exceeded 90% in the last 5 minutes',
          severity: 'high',
          status: 'open',
          source: 'zabbix',
        },
        {
          title: 'Multiple failed SSH logins',
          description: 'Detected repeated failed SSH login attempts',
          severity: 'critical',
          status: 'investigating',
          source: 'wazuh',
        },
      ],
    });
  }

  const logMetaCount = await prisma.logMeta.count();
  if (logMetaCount === 0) {
    await prisma.logMeta.createMany({
      data: [
        {
          logType: 'auth',
          source: 'wazuh',
          severity: 'warning',
          referenceId: 'sample-auth-001',
          timestamp: new Date(),
        },
        {
          logType: 'system',
          source: 'zabbix',
          severity: 'info',
          referenceId: 'sample-system-001',
          timestamp: new Date(),
        },
      ],
    });
  }

  console.log('Seed complete: default users and sample alerts/log metadata created.');

  const incidentCount = await prisma.incident.count();
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
          firstSeen: new Date(now.getTime() - 120 * 60 * 1000),
          lastSeen: new Date(now.getTime() - 100 * 60 * 1000),
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
