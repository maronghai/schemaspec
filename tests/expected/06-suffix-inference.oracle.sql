
CREATE TABLE "suffixes" (
  "user_id" NUMBER(10) NOT NULL,
  "order_id" NUMBER(10) NOT NULL,
  "created_at" TIMESTAMP NOT NULL,
  "updated_at" TIMESTAMP NOT NULL,
  "paid_on" DATE NOT NULL,
  "deleted_on" DATE NOT NULL,
  "name" VARCHAR2(255) NOT NULL,
  "content" VARCHAR2(255) NOT NULL
);
