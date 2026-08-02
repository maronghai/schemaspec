
CREATE TABLE "settings" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "enabled" INTEGER NOT NULL,
  "config" TEXT NOT NULL,
  "metadata" TEXT NOT NULL,
  "name" varchar(32) NOT NULL
);
-- @sym id n
-- @sym enabled b
-- @sym config j
-- @sym metadata J
-- @sym name s32
