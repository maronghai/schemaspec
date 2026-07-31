-- Migration: schema diff

BEGIN;

ALTER TABLE "user"
ALTER COLUMN "name" TYPE varchar(64) NOT NULL;
COMMIT;
