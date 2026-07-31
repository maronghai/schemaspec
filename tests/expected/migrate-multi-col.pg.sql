-- Migration: schema diff

BEGIN;

ALTER TABLE "t"
ALTER COLUMN "name" TYPE varchar(64) NOT NULL,
ALTER COLUMN "cnt" TYPE bigint,
ADD COLUMN "email" varchar(128);
COMMIT;
