
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "compound_check" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "balance" numeric(16, 2) NOT NULL CHECK (balance >= 0 AND balance <= 99999),
  "score" integer NOT NULL CHECK (score > 0 AND score <= 100)
);
