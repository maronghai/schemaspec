
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(32) NOT NULL
);
-- @sym id n
-- @sym name s32

CREATE VIEW "active_users" AS
SELECT id, name FROM user WHERE active = 1;
