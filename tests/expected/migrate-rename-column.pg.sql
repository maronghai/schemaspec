-- Migration: schema diff

BEGIN;

ALTER TABLE "user"
RENAME COLUMN "name" TO "full_name";
COMMIT;
