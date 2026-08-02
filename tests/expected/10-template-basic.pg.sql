
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "version" bigint NOT NULL,
  "create_at" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);
