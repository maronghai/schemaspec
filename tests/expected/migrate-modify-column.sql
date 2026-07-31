-- Migration: schema diff

BEGIN;

ALTER TABLE `user`
MODIFY COLUMN `name` varchar(64) NOT NULL;
COMMIT;
