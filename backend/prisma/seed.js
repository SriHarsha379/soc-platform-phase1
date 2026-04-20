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
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
