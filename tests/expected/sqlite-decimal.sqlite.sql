
CREATE TABLE "products" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "price" NUMERIC(16, 2) NOT NULL,
  "big_p" NUMERIC(20, 6) NOT NULL,
  "amt" NUMERIC(10, 2) NOT NULL
);
-- @sym id n
-- @sym price m
-- @sym big_p M
-- @sym amt 10,2
