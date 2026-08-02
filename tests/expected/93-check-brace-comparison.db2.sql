
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "amount" DECIMAL(16, 2) NOT NULL CHECK (amount > 0),
  "ratio" DECIMAL(20, 6) NOT NULL CHECK (ratio >= 0 AND ratio <= 100),
  "score" INTEGER NOT NULL CHECK (score >= 0)
);
