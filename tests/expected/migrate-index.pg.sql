-- Migration: schema diff

BEGIN;

ALTER TABLE "user"
ADD UNIQUE ("email"),
;

CREATE INDEX "idx_name" ON "user" ("name");

ALTER TABLE "user"
;
COMMIT;
