
CREATE TABLE "events" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "title" TEXT NOT NULL,
  "created_at" TEXT NOT NULL,
  "updated_at" TEXT NOT NULL,
  "payload" TEXT NOT NULL
);
-- @sym id n
-- @sym created_at t
-- @sym updated_at t
-- @sym payload j
