
-- This is a SQL comment (passed through)
CREATE TABLE [comments] (
  [id] INT NOT NULL PRIMARY KEY,
  [name] NVARCHAR(32) NOT NULL /* 用户名 */,
  [email] NVARCHAR(128) NOT NULL /* 邮箱地址 */,
  [bio] NVARCHAR(MAX) NOT NULL /* 个人简介 */
);
