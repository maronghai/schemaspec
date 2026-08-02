
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "status_check" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "status" varchar(16) NOT NULL CHECK (status IN ('active', 'inactive', 'pending')),
  "priority" integer NOT NULL CHECK (priority IN (1, 2, 3, 4, 5))
);
