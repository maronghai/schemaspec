-- Migration: schema diff

BEGIN;

ALTER TABLE `t`
MODIFY COLUMN `name` varchar(64) NOT NULL,
MODIFY COLUMN `cnt` bigint,
ADD COLUMN `email` varchar(128);
COMMIT;
