
CREATE TABLE "customer" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "email" varchar(128) NOT NULL,
  UNIQUE ("email")
);
-- @sym id n
-- @sym email s128

CREATE TABLE "product" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" TEXT NOT NULL,
  "price" NUMERIC(16, 2) NOT NULL
);
-- @sym id n
-- @sym price m

CREATE TABLE "order_item" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "customer_id" INTEGER NOT NULL,
  "product_id" INTEGER NOT NULL,
  "quantity" INTEGER NOT NULL
);
-- @sym id n
-- @sym customer_id n
-- @sym product_id n
-- @sym quantity n
