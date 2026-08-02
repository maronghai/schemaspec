
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "constrained" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "age" integer NOT NULL CHECK (age BETWEEN 0 AND 150),
  "score" numeric(16, 2) NOT NULL CHECK (score BETWEEN 0 AND 100),
  "amount" numeric(16, 2) NOT NULL CHECK (amount > 0),
  "qty" integer NOT NULL CHECK (qty >= 1),
  "type" varchar(16) NOT NULL CHECK (type IN ('a', 'b', 'c')),
  "range2" integer NOT NULL CHECK (range2 >= 0 AND range2 <= 100)
);
