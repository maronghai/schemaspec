
CREATE TABLE "constrained" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "age" INTEGER NOT NULL CHECK (age BETWEEN 0 AND 150),
  "score" DECIMAL(16, 2) NOT NULL CHECK (score BETWEEN 0 AND 100),
  "amount" DECIMAL(16, 2) NOT NULL CHECK (amount > 0),
  "qty" INTEGER NOT NULL CHECK (qty >= 1),
  "type" VARCHAR(16) NOT NULL CHECK (type IN ('a', 'b', 'c')),
  "range2" INTEGER NOT NULL CHECK (range2 >= 0 AND range2 <= 100)
);
