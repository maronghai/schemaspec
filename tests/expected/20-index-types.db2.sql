
CREATE TABLE "indexed" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(32) NOT NULL,
  "email" VARCHAR(128) NOT NULL,
  "content" CLOB NOT NULL,
  UNIQUE "uk_email" ("email"),
  INDEX "idx_name" ("name"),
  INDEX "ft_content" ("content")
);
