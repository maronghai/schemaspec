
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "users" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "role" TEXT NOT NULL CHECK ("role" IN ('admin', 'user', 'guest')),
  "status" TEXT NOT NULL CHECK ("status" IN ('A', 'B', 'C'))
);
