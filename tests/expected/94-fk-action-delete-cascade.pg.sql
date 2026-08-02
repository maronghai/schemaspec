
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL
);

CREATE TABLE "order" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  "amount" numeric(16, 2) NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE
);
