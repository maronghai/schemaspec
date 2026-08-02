
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(32) NOT NULL,
  "email" VARCHAR(128) NOT NULL,
  "phone" VARCHAR(16) NOT NULL,
  INDEX "idx_name" ("name"),
  UNIQUE INDEX "uk_email" ("email")
);
CREATE INDEX "idx_user_name" ON "user" ("name");
