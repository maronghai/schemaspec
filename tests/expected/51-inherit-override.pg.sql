
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "phone" varchar(16) NOT NULL,
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "email" varchar(128) NOT NULL,
  "name" varchar(64) NOT NULL,
  "version" bigint NOT NULL
);
