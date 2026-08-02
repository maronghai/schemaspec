
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "idx_test" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "content" text NOT NULL,
  UNIQUE ("email")
);
CREATE INDEX "idx_name" ON "idx_test" ("name");
