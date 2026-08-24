-- Migration: schema diff

BEGIN;

ALTER TABLE `users`
COMMENT='User accounts table';
COMMIT;
