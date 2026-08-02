
CREATE TABLE "flags" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "is_admin" INTEGER NOT NULL,
  "active" INTEGER NOT NULL,
  "enabled" INTEGER NOT NULL
);
-- @sym id n
-- @sym is_admin b
-- @sym active b
-- @sym enabled b
