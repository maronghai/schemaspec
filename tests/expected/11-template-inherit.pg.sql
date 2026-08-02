
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "create_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "update_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "version" bigint NOT NULL,
  "status" integer NOT NULL DEFAULT 0
);
