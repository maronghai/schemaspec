
CREATE TABLE [suffixes] (
  [user_id] INT NOT NULL,
  [order_id] INT NOT NULL,
  [created_at] DATETIME2 NOT NULL,
  [updated_at] DATETIME2 NOT NULL,
  [paid_on] DATE NOT NULL,
  [deleted_on] DATE NOT NULL,
  [name] NVARCHAR(255) NOT NULL,
  [content] NVARCHAR(255) NOT NULL
);
