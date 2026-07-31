
CREATE TABLE [all_types] (
  [id] INT PRIMARY KEY,
  [name] NVARCHAR(255),
  [full] NVARCHAR(MAX),
  [price] NUMERIC(16, 2),
  [big_p] NUMERIC(20, 6),
  [flag] BIT,
  [data] VARBINARY(MAX),
  [meta] NVARCHAR(MAX),
  [created] DATETIME2,
  [born] DATE,
  [code] NVARCHAR(64),
  [ver] BIGINT,
  [amt] NUMERIC(10, 2),
  [cnt] INT
);
