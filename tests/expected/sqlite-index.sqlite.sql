
CREATE TABLE "logs" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "level" TEXT NOT NULL,
  "message" TEXT NOT NULL,
  "ts" TEXT NOT NULL,
  UNIQUE ("ts")
);
-- @sym id n
-- @sym ts t
CREATE INDEX "idx_level" ON "logs" ("level");
