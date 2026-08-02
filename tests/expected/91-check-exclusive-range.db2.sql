
CREATE TABLE "user" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "age_upper" INTEGER NOT NULL DEFAULT 0 CHECK (age_upper >= 0 AND age_upper < 150),
  "age_lower" INTEGER NOT NULL DEFAULT 0 CHECK (age_lower > 0 AND age_lower <= 150),
  "age_both" INTEGER NOT NULL DEFAULT 0 CHECK (age_both > 0 AND age_both < 150)
);
