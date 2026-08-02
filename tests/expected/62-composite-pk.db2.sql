
CREATE TABLE "order_item" (
  "order_id" INTEGER NOT NULL,
  "product_id" INTEGER NOT NULL,
  "quantity" INTEGER NOT NULL,
  PRIMARY KEY ("order_id", "product_id")
);
