
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(32) NOT NULL,
  "status" TEXT NOT NULL CHECK ("status" IN ('active', 'inactive'))
);
-- @sym id n
-- @sym name s32

CREATE TABLE "order" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "order_no" varchar(64) NOT NULL,
  "user_id" INTEGER NOT NULL,
  "amount" NUMERIC(16, 2) NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);
-- @sym id n
-- @sym order_no s64
-- @sym user_id n
-- @sym amount m
CREATE INDEX "idx_user_id" ON "order" ("user_id");

CREATE TABLE "user_role" (
  "user_id" INTEGER NOT NULL PRIMARY KEY,
  "role_id" INTEGER NOT NULL PRIMARY KEY,
  "assigned" TEXT NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);
-- @sym user_id n
-- @sym role_id n
-- @sym assigned t
CREATE INDEX "idx_user_id" ON "user_role" ("user_id");
