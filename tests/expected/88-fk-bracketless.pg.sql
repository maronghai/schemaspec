
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL
);

CREATE TABLE "t1" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);

CREATE TABLE "t2" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);

CREATE TABLE "t3" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);

CREATE TABLE "t4" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);

CREATE TABLE "t5" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);

CREATE TABLE "t6" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "user_id" integer NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);
