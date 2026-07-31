-- Migration: schema diff

BEGIN;

ALTER TABLE `user`
ADD UNIQUE INDEX `uk_email` (`email`),
ADD INDEX `idx_name` (`name`);
COMMIT;
