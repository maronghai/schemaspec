
CREATE TABLE "order" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "user_id" INTEGER NOT NULL CHECK (user_id = user.id),
  "total" DATE NOT NULL,
  "status" VARCHAR(255) NOT NULL CHECK (status IN ('draft', 'pending', 'done')),
  INDEX "idx_user_id" ("user_id"),
  INDEX "idx_status" ("status")
);
COMMENT ON TABLE "order" IS '订单表';
CREATE INDEX "idx_order_user_id" ON "order" ("user_id");
CREATE INDEX "idx_order_status" ON "order" ("status");

CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(255) NOT NULL
);
COMMENT ON TABLE "user" IS '用户表';
