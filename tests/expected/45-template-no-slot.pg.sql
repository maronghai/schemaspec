
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "version" bigint NOT NULL,
  "status" integer NOT NULL DEFAULT 0,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL
);
