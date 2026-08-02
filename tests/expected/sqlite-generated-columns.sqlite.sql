
CREATE TABLE "products" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "price" INTEGER NOT NULL,
  "qty" INTEGER NOT NULL,
  "total" INTEGER NOT NULL GENERATED ALWAYS AS (price qty) VIRTUAL,
  "tax" INTEGER NOT NULL GENERATED ALWAYS AS (price 0.1) STORED
);
-- @sym id n
-- @sym price n
-- @sym qty n
-- @sym total n
-- @sym tax n
