
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "constrained" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "age" integer NOT NULL CHECK (age BETWEEN 0 AND 150),
  "amount" numeric(16, 2) NOT NULL CHECK (amount > 0),
  "ratio" numeric(20, 6) NOT NULL CHECK (ratio >= 0 AND ratio <= 100),
  "type" varchar(16) NOT NULL CHECK (type IN ('a', 'b', 'c'))
);
