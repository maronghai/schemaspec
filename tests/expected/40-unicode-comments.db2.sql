
CREATE TABLE "unicode_test" (
  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  "name" VARCHAR(32) NOT NULL /* 用户登录名 */,
  "email" VARCHAR(128) NOT NULL /* 电子邮箱地址 */,
  "addr" CLOB NOT NULL /* 收货地址（省/市/区） */
);
COMMENT ON COLUMN "unicode_test"."name" IS '用户登录名';
COMMENT ON COLUMN "unicode_test"."email" IS '电子邮箱地址';
COMMENT ON COLUMN "unicode_test"."addr" IS '收货地址（省/市/区）';
