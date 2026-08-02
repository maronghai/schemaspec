
CREATE TABLE "users" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "role" VARCHAR(255) NOT NULL CHECK ("role" IN ('admin', 'user', 'guest')),
  "status" VARCHAR(255) NOT NULL CHECK ("status" IN ('A', 'B', 'C'))
);
