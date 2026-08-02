
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "defaults" (
  "col1" integer NOT NULL DEFAULT 0,
  "col2" varchar(255) NOT NULL DEFAULT 'hello',
  "col3" numeric(16, 2) NOT NULL DEFAULT 0,
  "col4" varchar(255) NOT NULL DEFAULT 0,
  "col5" timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);
