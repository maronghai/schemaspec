
CREATE TABLE "post" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "ts" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "content" TEXT NOT NULL
);
-- @sym id n
-- @sym ts t
-- @sym content S

CREATE TABLE "comment" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "ts" TEXT NOT NULL,
  "text" TEXT NOT NULL,
  "post_id" INTEGER NOT NULL
);
-- @sym id n
-- @sym ts t
-- @sym text S
-- @sym post_id n
