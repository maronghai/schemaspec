
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "status" integer NOT NULL DEFAULT 0,
  "create_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE ("email", "status")
);
CREATE INDEX "idx_name_email" ON "user" ("name", "email");
