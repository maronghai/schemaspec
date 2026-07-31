
CREATE TABLE [products] (
  [id] INT PRIMARY KEY,
  [name] NVARCHAR(255),
  [price] INT,
  [qty] INT,
  [total] INT AS (price * qty),
  [tax] INT AS (price * 0.1) PERSISTED
);
