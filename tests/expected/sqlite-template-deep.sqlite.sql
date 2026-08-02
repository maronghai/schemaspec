
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(32) NOT NULL,
  "created" TEXT NOT NULL
);
-- @sym id n
-- @sym name s32
-- @sym created t

CREATE TABLE "order" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "amount" NUMERIC(16, 2) NOT NULL,
  "created" TEXT NOT NULL
);
-- @sym id n
-- @sym amount m
-- @sym created t
