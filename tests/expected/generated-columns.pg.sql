
CREATE DATABASE "generated_columns" ENCODING 'UTF8';

CREATE TABLE "products" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(255) NOT NULL,
  "price" integer NOT NULL,
  "qty" integer NOT NULL,
  "total" integer NOT NULL GENERATED ALWAYS AS (price qty) STORED,
  "tax" integer NOT NULL GENERATED ALWAYS AS (price 0.1) STORED
);
