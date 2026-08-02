
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "amount" numeric(16, 2) NOT NULL CHECK (amount > 0),
  "ratio" numeric(20, 6) NOT NULL CHECK (ratio >= 0 AND ratio <= 100),
  "score" integer NOT NULL CHECK (score >= 0)
);
