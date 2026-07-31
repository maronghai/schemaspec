
CREATE TABLE [constrained] (
  [id] INT PRIMARY KEY,
  [age] INT CHECK (age BETWEEN 0 AND 150),
  [score] NUMERIC(16, 2) CHECK (score BETWEEN 0 AND 100),
  [amount] NUMERIC(16, 2) CHECK (amount > 0),
  [qty] INT CHECK (qty >= 1),
  [type] NVARCHAR(16) CHECK (type IN ('a', 'b', 'c')),
  [range2] INT CHECK (range2 >= 0 AND range2 <= 100)
);
