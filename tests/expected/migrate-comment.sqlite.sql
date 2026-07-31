-- Migration: schema diff

BEGIN;

ALTER TABLE "users"
-- NOTE: Comment change not supported via ALTER TABLE in SQLite
;
COMMIT;
