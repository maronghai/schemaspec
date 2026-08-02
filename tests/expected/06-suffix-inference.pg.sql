
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "suffixes" (
  "user_id" integer NOT NULL,
  "order_id" integer NOT NULL,
  "created_at" timestamp NOT NULL,
  "updated_at" timestamp NOT NULL,
  "paid_on" date NOT NULL,
  "deleted_on" date NOT NULL,
  "name" varchar(255) NOT NULL,
  "content" varchar(255) NOT NULL
);
