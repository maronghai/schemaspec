
CREATE TABLE [indexed] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL,
  [email] NVARCHAR(128) NOT NULL,
  [content] NVARCHAR(MAX) NOT NULL,
  UNIQUE [uk_email] ([email]),
  INDEX [idx_name] ([name]),
  FULLTEXT INDEX [ft_content] ([content])
);
