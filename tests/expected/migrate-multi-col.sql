-- Migration: schema diff

BEGIN;

ALTER TABLE `t`
MODIFY COLUMN `name` varchar(64) NOT NULL,
MODIFY COLUMN `cnt` bigint NOT NULL,
ADD COLUMN `email` varchar(128) NOT NULL;
COMMIT;
