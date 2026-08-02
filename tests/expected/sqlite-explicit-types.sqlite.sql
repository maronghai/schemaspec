
CREATE TABLE "explicit" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "cnt" INTEGER NOT NULL,
  "amt" NUMERIC(10, 2) NOT NULL,
  "code" varchar(64) NOT NULL,
  "ver" INTEGER NOT NULL,
  "bigamt" NUMERIC(20, 6) NOT NULL
);
-- @sym id n
-- @sym amt 10,2
-- @sym code s64
-- @sym ver N
-- @sym bigamt 20,6
