
CREATE TABLE [products] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(255) NOT NULL,
  [price] INT NOT NULL,
  [qty] INT NOT NULL,
  [total] INT NOT NULL AS (price qty),
  [tax] INT NOT NULL AS (price 0.1) PERSISTED
);
