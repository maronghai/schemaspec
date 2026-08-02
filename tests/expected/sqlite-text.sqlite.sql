
CREATE TABLE "documents" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "title" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "bio" TEXT NOT NULL,
  "short" varchar(64) NOT NULL
);
-- @sym id n
-- @sym body S
-- @sym bio S
-- @sym short s64
