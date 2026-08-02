
CREATE TABLE [composite_pk] (
  [user_id] INT NOT NULL PRIMARY KEY,
  [role_id] INT NOT NULL PRIMARY KEY,
  [granted] DATETIME2 NOT NULL
);
