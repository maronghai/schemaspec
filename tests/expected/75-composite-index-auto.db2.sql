
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(32) NOT NULL,
  "email" VARCHAR(128) NOT NULL,
  "status" INTEGER NOT NULL DEFAULT 0,
  "create_at" TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX "idx_name_email" ("name", "email"),
  UNIQUE "uk_email_status" ("email", "status")
);
