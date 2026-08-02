
CREATE TABLE "multi" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(32) NOT NULL,
  "email" VARCHAR(128) NOT NULL,
  "status" INTEGER NOT NULL,
  INDEX "idx_name_email" ("name", "email"),
  UNIQUE "uk_email_status" ("email", "status")
);
