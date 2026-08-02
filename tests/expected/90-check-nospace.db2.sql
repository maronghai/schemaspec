
CREATE TABLE "constrained" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "age" INTEGER NOT NULL CHECK (age BETWEEN 0 AND 150),
  "amount" DECIMAL(16, 2) NOT NULL CHECK (amount > 0),
  "ratio" DECIMAL(20, 6) NOT NULL CHECK (ratio >= 0 AND ratio <= 100),
  "type" VARCHAR(16) NOT NULL CHECK (type IN ('a', 'b', 'c'))
);
