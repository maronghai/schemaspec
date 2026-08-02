-- Migration: schema diff

BEGIN;

ALTER TABLE "t"
ALTER COLUMN "name" TYPE varchar(64) NOT NULL,
ALTER COLUMN "cnt" TYPE bigint NOT NULL,
ADD COLUMN "email" varchar(128) NOT NULL;
COMMIT;
