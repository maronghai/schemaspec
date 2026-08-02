
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "all_types" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(255) NOT NULL,
  "full" text NOT NULL,
  "price" numeric(16, 2) NOT NULL,
  "big_p" numeric(20, 6) NOT NULL,
  "flag" boolean NOT NULL,
  "data" bytea NOT NULL,
  "meta" json NOT NULL,
  "created" timestamp NOT NULL,
  "born" date NOT NULL,
  "code" varchar(64) NOT NULL,
  "ver" bigint NOT NULL,
  "amt" numeric(10, 2) NOT NULL,
  "cnt" integer NOT NULL
);
