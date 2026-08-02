
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "order_item" (
  "order_id" integer NOT NULL,
  "product_id" integer NOT NULL,
  "quantity" integer NOT NULL,
  PRIMARY KEY ("order_id", "product_id")
);
