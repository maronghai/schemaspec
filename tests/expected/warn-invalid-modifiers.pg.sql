
CREATE DATABASE "test_warn" ENCODING 'UTF8';

CREATE TABLE "warn_table" (
  "name" varchar(32) GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "tag" varchar(255),
  "count" integer GENERATED ALWAYS AS IDENTITY,
  "id" integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "balance" numeric(16, 2)
);
