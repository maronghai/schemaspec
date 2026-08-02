
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "version" bigint NOT NULL,
  "status" integer NOT NULL DEFAULT 0
);

CREATE TABLE "product" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(128) NOT NULL,
  "price" numeric(16, 2) NOT NULL,
  "version" bigint NOT NULL,
  "status" integer NOT NULL DEFAULT 0
);
