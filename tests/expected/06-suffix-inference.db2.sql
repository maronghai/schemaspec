
CREATE TABLE "suffixes" (
  "user_id" INTEGER NOT NULL,
  "order_id" INTEGER NOT NULL,
  "created_at" TIMESTAMP NOT NULL,
  "updated_at" TIMESTAMP NOT NULL,
  "paid_on" DATE NOT NULL,
  "deleted_on" DATE NOT NULL,
  "name" VARCHAR(255) NOT NULL,
  "content" VARCHAR(255) NOT NULL
);
