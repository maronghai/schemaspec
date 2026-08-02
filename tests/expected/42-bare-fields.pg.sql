
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "bare_fields" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  "order_id" integer NOT NULL,
  "name" varchar(255) NOT NULL
);
