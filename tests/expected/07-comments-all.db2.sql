
-- This is a SQL comment (passed through)
CREATE TABLE "comments" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(32) NOT NULL /* 用户名 */,
  "email" VARCHAR(128) NOT NULL /* 邮箱地址 */,
  "bio" CLOB NOT NULL /* 个人简介 */
);
COMMENT ON COLUMN "comments"."name" IS '用户名';
COMMENT ON COLUMN "comments"."email" IS '邮箱地址';
COMMENT ON COLUMN "comments"."bio" IS '个人简介';
