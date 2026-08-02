
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "explicit" (
  "col_int" integer NOT NULL,
  "col_dec" numeric(10, 2) NOT NULL,
  "col_var" varchar(256) NOT NULL,
  "col_var0" varchar(255) NOT NULL
);
