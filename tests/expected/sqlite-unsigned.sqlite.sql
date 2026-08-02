
CREATE TABLE "counters" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "small_u" INTEGER NOT NULL,
  "big_u" INTEGER NOT NULL,
  "plain_n" INTEGER NOT NULL,
  "small_un" INTEGER NOT NULL
);
-- @sym id n
-- @sym small_u +n
-- @sym big_u +N
-- @sym plain_n n
-- @sym small_un +i
