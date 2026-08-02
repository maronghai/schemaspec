
CREATE TABLE [user] (
  [id] INT NOT NULL PRIMARY KEY,
  [gender] NVARCHAR(255) NOT NULL CHECK ([gender] IN ('M', 'F', 'X')),
  [status] NVARCHAR(255) NOT NULL DEFAULT 'pending' CHECK ([status] IN ('pending', 'active', 'closed')),
  [role] NVARCHAR(255) NOT NULL CHECK ([role] IN ('admin', 'user', 'guest'))
);
