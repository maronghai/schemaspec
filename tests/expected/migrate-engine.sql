-- Migration: schema diff

BEGIN;

ALTER TABLE `users`
ENGINE=MyISAM;
COMMIT;
