
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL
);

CREATE TABLE "order" (
  "id" integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer,
  "amount" numeric(16, 2)
);

CREATE OR REPLACE VIEW "user_summary" AS
SELECT u.id, u.name, COUNT(o.id) AS order_count FROM user u LEFT JOIN order o ON u.id = o.user_id GROUP BY u.id;

CREATE OR REPLACE VIEW "expensive_orders" AS
SELECT * FROM order WHERE amount > 1000;
