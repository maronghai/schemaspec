
CREATE DATABASE "test_custom_types" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "uuid" varchar(36) NOT NULL,
  "email" varchar(128) NOT NULL,
  "name" varchar(64) NOT NULL,
  "ip" inet NOT NULL
);
