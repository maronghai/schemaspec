
CREATE TABLE [user] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL
);

CREATE TABLE [order] (
  [id] INT NOT NULL PRIMARY KEY,
  [user_id] INT NOT NULL,
  [amount] NUMERIC(16, 2) NOT NULL,
  FOREIGN KEY ([user_id]) REFERENCES [user]([id])
);
