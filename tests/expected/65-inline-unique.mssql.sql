
CREATE TABLE [user] (
  [id] INT NOT NULL PRIMARY KEY,
  [email] NVARCHAR(128) NOT NULL,
  [name] NVARCHAR(32) NOT NULL,
  [code] NVARCHAR(16) NOT NULL,
  UNIQUE INDEX [uk_email] ([email]),
  UNIQUE INDEX [uk_code] ([code])
);
