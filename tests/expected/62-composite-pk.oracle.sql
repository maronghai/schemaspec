
CREATE TABLE "order_item" (
  "order_id" NUMBER(10) NOT NULL,
  "product_id" NUMBER(10) NOT NULL,
  "quantity" NUMBER(10) NOT NULL,
  PRIMARY KEY ("order_id", "product_id")
);
