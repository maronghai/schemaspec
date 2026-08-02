
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(32) NOT NULL
);
-- @sym id n
-- @sym name s32

CREATE TABLE "order" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "user_id" INTEGER NOT NULL,
  "amount" NUMERIC(16, 2) NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE
);
-- @sym id n
-- @sym user_id n
-- @sym amount m

CREATE TABLE "log" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "order_id" INTEGER NOT NULL,
  FOREIGN KEY ("order_id") REFERENCES "order"("id") ON DELETE SET NULL
);
-- @sym id n
-- @sym order_id n
