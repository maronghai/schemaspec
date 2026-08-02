
CREATE TABLE "status_check" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "status" VARCHAR(16) NOT NULL CHECK (status IN ('active', 'inactive', 'pending')),
  "priority" INTEGER NOT NULL CHECK (priority IN (1, 2, 3, 4, 5))
);
