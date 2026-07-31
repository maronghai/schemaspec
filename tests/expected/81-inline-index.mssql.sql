
CREATE TABLE [user] (
  [id] INT PRIMARY KEY,
  [name] NVARCHAR(32),
  [email] NVARCHAR(128) NOT NULL,
  [phone] NVARCHAR(16),
  INDEX [idx_name] ([name]),
  UNIQUE INDEX [uk_email] ([email])
);
CREATE INDEX [idx_user_name] ON [user] ([name]);
