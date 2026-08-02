
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "unicode_test" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(32) NOT NULL,
  "email" varchar(128) NOT NULL,
  "addr" text NOT NULL
);
COMMENT ON COLUMN "unicode_test"."name" IS '用户登录名';
COMMENT ON COLUMN "unicode_test"."email" IS '电子邮箱地址';
COMMENT ON COLUMN "unicode_test"."addr" IS '收货地址（省/市/区）';
