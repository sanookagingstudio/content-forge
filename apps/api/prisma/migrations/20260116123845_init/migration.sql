-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_ContentJob" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "planId" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "inputsJson" TEXT NOT NULL,
    "outputsJson" TEXT NOT NULL,
    "advisoryJson" TEXT NOT NULL DEFAULT '{}',
    "costJson" TEXT NOT NULL,
    "logsJson" TEXT NOT NULL,
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    CONSTRAINT "ContentJob_planId_fkey" FOREIGN KEY ("planId") REFERENCES "ContentPlan" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
INSERT INTO "new_ContentJob" ("costJson", "createdAt", "id", "inputsJson", "logsJson", "outputsJson", "planId", "status", "updatedAt") SELECT "costJson", "createdAt", "id", "inputsJson", "logsJson", "outputsJson", "planId", "status", "updatedAt" FROM "ContentJob";
DROP TABLE "ContentJob";
ALTER TABLE "new_ContentJob" RENAME TO "ContentJob";
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;
