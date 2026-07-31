
-- This is a SQL comment (passed through)
CREATE TABLE [comments] (
  [id] INT PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL /* 用户名 */,
  [email] NVARCHAR(128) NOT NULL /* 邮箱地址 */,
  [bio] NVARCHAR(MAX) /* 个人简介 */
);
