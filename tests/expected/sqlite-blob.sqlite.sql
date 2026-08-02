
CREATE TABLE "attachments" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "content" BLOB NOT NULL,
  "avatar" BLOB NOT NULL
);
-- @sym id n
-- @sym content B
-- @sym avatar B
