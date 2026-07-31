-- Migration: schema diff

BEGIN;

ALTER TABLE "order"
ADD FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;
