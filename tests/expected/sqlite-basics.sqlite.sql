
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "balance" NUMERIC(16, 2) NOT NULL DEFAULT 0,
  "status" INTEGER NOT NULL DEFAULT 0,
  "create_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE ("email")
);
-- 用户表
-- @sym id n
-- @sym name s32
-- @sym email s128
-- @sym balance m
-- @sym create_at t

CREATE TABLE "order" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "order_no" varchar(64) NOT NULL,
  "user_id" INTEGER NOT NULL,
  "amount" NUMERIC(16, 2) NOT NULL,
  "status" INTEGER NOT NULL DEFAULT 0,
  "create_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);
-- 订单表
-- order.user_id: 下单用户
-- @sym id n
-- @sym order_no s64
-- @sym user_id n
-- @sym amount m
-- @sym create_at t
