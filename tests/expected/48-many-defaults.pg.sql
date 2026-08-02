
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "defaults_many" (
  "col_int" integer NOT NULL DEFAULT 42,
  "col_str" varchar(255) NOT NULL DEFAULT 'hello',
  "col_zero" integer NOT NULL DEFAULT 0,
  "col_one" integer NOT NULL DEFAULT 1,
  "col_empty" varchar(255) NOT NULL DEFAULT 0,
  "col_big" bigint NOT NULL DEFAULT 999999999,
  "col_m" numeric(16, 2) NOT NULL DEFAULT 0
);
