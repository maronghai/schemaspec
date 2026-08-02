-- Migration: schema diff

BEGIN;

ALTER TABLE "user"
ADD COLUMN "email" varchar(64) NOT NULL;
COMMIT;
