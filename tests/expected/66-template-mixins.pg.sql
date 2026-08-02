
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "version" bigint NOT NULL,
  "deleted_at" timestamp NOT NULL,
  "deleted_by" integer NOT NULL,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "phone" varchar(16) NOT NULL
);
