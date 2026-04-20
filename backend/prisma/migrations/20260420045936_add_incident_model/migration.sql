-- CreateTable
CREATE TABLE "Incident" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "severity" TEXT NOT NULL,
    "ruleType" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "sourceIp" TEXT,
    "affectedHost" TEXT,
    "eventCount" INTEGER NOT NULL DEFAULT 1,
    "firstSeen" DATETIME NOT NULL,
    "lastSeen" DATETIME NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL
);
