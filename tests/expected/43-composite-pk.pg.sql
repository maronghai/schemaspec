
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "composite_pk" (
  "user_id" integer NOT NULL PRIMARY KEY,
  "role_id" integer NOT NULL PRIMARY KEY,
  "granted" timestamp NOT NULL
);
