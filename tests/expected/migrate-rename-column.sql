-- Migration: schema diff

BEGIN;

ALTER TABLE `user`
CHANGE COLUMN `name``full_name` varchar(32) NOT NULL;
COMMIT;
