-- Migration: schema diff

BEGIN;

CREATE TABLE "post" (
  "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  "title" varchar(128) NOT NULL
);
-- @sym id n
-- @sym title s128


ALTER TABLE "user"
-- WARNING: MODIFY COLUMN not supported in SQLite; requires table recreation
;
COMMIT;
