
CREATE TABLE [user] (
  [id] INT PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL,
  [email] NVARCHAR(128) NOT NULL
);

CREATE TABLE [order] (
  [id] INT PRIMARY KEY,
  [order_no] NVARCHAR(64) NOT NULL,
  [user_id] INT,
  [amount] NUMERIC(16, 2) NOT NULL,
  INDEX [idx_user_id] ([user_id]),
  FOREIGN KEY ([user_id]) REFERENCES [user]([id])
);
