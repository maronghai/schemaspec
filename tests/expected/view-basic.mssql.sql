
CREATE TABLE [user] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL
);

CREATE VIEW [active_users] AS
SELECT id, name FROM user WHERE active = 1;
