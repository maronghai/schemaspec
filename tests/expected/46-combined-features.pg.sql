
CREATE DATABASE "ecommerce" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "password" varchar(256) NOT NULL,
  "avatar" text NOT NULL,
  "is_admin" boolean NOT NULL DEFAULT 0,
  "balance" numeric(16, 2) NOT NULL DEFAULT 0,
  "settings" json NOT NULL,
  "version" bigint NOT NULL,
  "status" integer NOT NULL DEFAULT 0,
  "delete_at" timestamp NOT NULL,
  "create_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "update_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE ("email")
);
COMMENT ON TABLE "user" IS '用户表';
COMMENT ON COLUMN "user"."name" IS '用户登录名';
COMMENT ON COLUMN "user"."email" IS '唯一邮箱';
COMMENT ON COLUMN "user"."password" IS 'bcrypt hash';
COMMENT ON COLUMN "user"."avatar" IS '头像 URL';
COMMENT ON COLUMN "user"."is_admin" IS '管理员标记';
COMMENT ON COLUMN "user"."balance" IS '账户余额（分）';
COMMENT ON COLUMN "user"."settings" IS 'JSON 用户偏好';
CREATE INDEX "idx_name" ON "user" ("name");

CREATE TABLE "product" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(128) NOT NULL,
  "description" text NOT NULL,
  "price" numeric(16, 2) NOT NULL,
  "stock" integer NOT NULL DEFAULT 0,
  "category_id" integer NOT NULL,
  "version" bigint NOT NULL,
  "status" integer NOT NULL DEFAULT 0,
  "delete_at" timestamp NOT NULL,
  "create_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "update_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);
COMMENT ON TABLE "product" IS '商品表';
COMMENT ON COLUMN "product"."name" IS '商品名称';
COMMENT ON COLUMN "product"."description" IS '商品详情';
COMMENT ON COLUMN "product"."price" IS '单价（分）';
COMMENT ON COLUMN "product"."stock" IS '库存数量';
COMMENT ON COLUMN "product"."category_id" IS '分类 ID';
CREATE INDEX "idx_category_id" ON "product" ("category_id");
CREATE INDEX "idx_price" ON "product" ("price");

CREATE TABLE "order" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "order_no" varchar(64) NOT NULL,
  "user_id" integer NOT NULL,
  "amount" numeric(16, 2) NOT NULL,
  "discount" numeric(20, 6) NOT NULL DEFAULT 0,
  "note" varchar(512) NOT NULL,
  "paid_on" date NOT NULL,
  "version" bigint NOT NULL,
  "status" integer NOT NULL DEFAULT 0,
  "delete_at" timestamp NOT NULL,
  "create_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "update_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE ("order_no"),
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);
COMMENT ON TABLE "order" IS '订单表';
COMMENT ON COLUMN "order"."order_no" IS '唯一订单号';
COMMENT ON COLUMN "order"."user_id" IS '下单用户';
COMMENT ON COLUMN "order"."amount" IS '订单总额（分）';
COMMENT ON COLUMN "order"."discount" IS '折扣金额（分）';
COMMENT ON COLUMN "order"."note" IS '买家留言';
COMMENT ON COLUMN "order"."paid_on" IS '支付日期';
CREATE INDEX "idx_user_id" ON "order" ("user_id");
CREATE INDEX "idx_paid_on" ON "order" ("paid_on");
