
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "item" (
  "name" varchar(64) NOT NULL,
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "status" integer NOT NULL DEFAULT 0,
  "version" bigint NOT NULL
);
