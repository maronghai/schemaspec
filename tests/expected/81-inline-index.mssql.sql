
CREATE TABLE [user] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL,
  [email] NVARCHAR(128) NOT NULL,
  [phone] NVARCHAR(16) NOT NULL,
  INDEX [idx_name] ([name]),
  UNIQUE INDEX [uk_email] ([email])
);
CREATE INDEX [idx_user_name] ON [user] ([name]);
