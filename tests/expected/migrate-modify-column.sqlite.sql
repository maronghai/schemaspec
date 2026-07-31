-- Migration: schema diff

BEGIN;

ALTER TABLE "user"
-- WARNING: MODIFY COLUMN not supported in SQLite; requires table recreation
;
COMMIT;
