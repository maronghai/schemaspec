
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "unsigned_test" (
  "plain_n" integer NOT NULL,
  "plain_N" bigint NOT NULL,
  "plus_n" integer NOT NULL,
  "plus_N" bigint NOT NULL,
  "plus_n_pk" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "plus_N_nn" bigint NOT NULL
);
