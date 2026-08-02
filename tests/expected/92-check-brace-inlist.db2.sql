
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "status" INTEGER NOT NULL DEFAULT 0 CHECK (status IN (0, 1, 2)),
  "type" VARCHAR(16) NOT NULL CHECK (type IN ('a', 'b', 'c')),
  "level" INTEGER NOT NULL CHECK (level IN (1, 2, 3, 4, 5))
);
