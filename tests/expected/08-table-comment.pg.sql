
CREATE DATABASE "demo" ENCODING 'UTF8';

CREATE TABLE "my_table" (
  "id" integer NOT NULL GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  "name" varchar(255) NOT NULL
);
COMMENT ON TABLE "my_table" IS '这是一个测试表';
