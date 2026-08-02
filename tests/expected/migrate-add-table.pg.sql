-- Migration: schema diff

BEGIN;

CREATE TABLE "post" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "title" varchar(128) NOT NULL,
  "user_id" integer NOT NULL,
  FOREIGN KEY ("user_id") REFERENCES "user"("id")
);
CREATE INDEX "idx_post_user_id" ON "post" ("user_id");


COMMIT;
