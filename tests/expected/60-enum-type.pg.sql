
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "user" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "gender" TEXT NOT NULL CHECK ("gender" IN ('M', 'F', 'X')),
  "status" TEXT NOT NULL DEFAULT 'pending' CHECK ("status" IN ('pending', 'active', 'closed')),
  "role" TEXT NOT NULL CHECK ("role" IN ('admin', 'user', 'guest'))
);
