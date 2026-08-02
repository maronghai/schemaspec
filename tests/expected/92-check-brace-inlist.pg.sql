
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "status" integer NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
  "type" varchar(16) NOT NULL CHECK (type IN ('a', 'b', 'c')),
  "level" integer NOT NULL CHECK (level IN (1, 2, 3, 4, 5))
);
