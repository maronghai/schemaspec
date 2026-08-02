
CREATE TABLE "users" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(32) NOT NULL,
  "role" VARCHAR(255) NOT NULL CHECK ("role" IN ('admin', 'user', 'guest'))
);
