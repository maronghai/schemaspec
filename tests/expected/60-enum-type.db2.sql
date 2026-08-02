
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "gender" VARCHAR(255) NOT NULL CHECK ("gender" IN ('M', 'F', 'X')),
  "status" VARCHAR(255) NOT NULL DEFAULT 'pending' CHECK ("status" IN ('pending', 'active', 'closed')),
  "role" VARCHAR(255) NOT NULL CHECK ("role" IN ('admin', 'user', 'guest'))
);
