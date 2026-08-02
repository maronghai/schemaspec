
CREATE TABLE "compound_check" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "balance" DECIMAL(16, 2) NOT NULL CHECK (balance >= 0 AND balance <= 99999),
  "score" INTEGER NOT NULL CHECK (score > 0 AND score <= 100)
);
