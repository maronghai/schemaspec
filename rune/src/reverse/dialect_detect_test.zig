const std = @import("std");
const detect = @import("dialect_detect.zig");
const codegen = @import("../codegen/codegen.zig");

const testing = std.testing;

test "detectSqlDialect: MySQL patterns" {
    const sql =
        \\CREATE TABLE `user` (
        \\  `id` int NOT NULL AUTO_INCREMENT,
        \\  PRIMARY KEY (`id`)
        \\) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: PostgreSQL patterns" {
    const sql =
        \\CREATE TABLE "user" (
        \\  "id" integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
        \\);
        \\COMMENT ON TABLE "user" IS 'User accounts';
    ;
    try testing.expectEqual(codegen.Dialect.pg, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: SQLite patterns" {
    const sql =
        \\CREATE TABLE "user" (
        \\  "id" INTEGER PRIMARY KEY AUTOINCREMENT
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.sqlite, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: SQLite STRICT" {
    const sql =
        \\CREATE TABLE "config" (
        \\  "key" TEXT NOT NULL,
        \\  "value" TEXT
        \\) STRICT;
    ;
    try testing.expectEqual(codegen.Dialect.sqlite, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: PostgreSQL CREATE EXTENSION" {
    const sql =
        \\CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        \\CREATE TABLE "items" (
        \\  "id" integer NOT NULL
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.pg, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: MySQL UNSIGNED and FULLTEXT" {
    const sql =
        \\CREATE TABLE `products` (
        \\  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
        \\  FULLTEXT INDEX `idx_search` (`name`)
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: ambiguous defaults to MySQL" {
    const sql =
        \\CREATE TABLE items (
        \\  id int NOT NULL
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: MSSQL patterns" {
    const sql =
        \\CREATE TABLE [dbo].[users] (
        \\  [id] INT IDENTITY(1,1) NOT NULL,
        \\  [name] NVARCHAR(100) NOT NULL,
        \\  PRIMARY KEY CLUSTERED ([id])
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mssql, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: MSSQL DATETIME2 and NTEXT" {
    const sql =
        \\CREATE TABLE [dbo].[logs] (
        \\  [id] INT IDENTITY(1,1) NOT NULL,
        \\  [message] NTEXT,
        \\  [created_at] DATETIME2 DEFAULT GETDATE()
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mssql, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: Oracle patterns" {
    const sql =
        \\CREATE TABLE users (
        \\  id NUMBER(10) NOT NULL,
        \\  name VARCHAR2(100) NOT NULL,
        \\  created_at DATE DEFAULT SYSDATE,
        \\  CONSTRAINT pk_users PRIMARY KEY (id)
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.oracle, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: Oracle NCLOB and sequences" {
    const sql =
        \\CREATE SEQUENCE users_seq START WITH 1 INCREMENT BY 1;
        \\CREATE TABLE users (
        \\  id NUMBER(10) NOT NULL,
        \\  bio NCLOB
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.oracle, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: Db2 patterns" {
    const sql =
        \\CREATE TABLE users (
        \\  id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        \\  name VARCHAR(100) NOT NULL,
        \\  score DECFLOAT DEFAULT 0
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.db2, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: Db2 generated columns" {
    const sql =
        \\CREATE TABLE orders (
        \\  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
        \\  total DECIMAL(10,2),
        \\  tax DECIMAL(10,2) GENERATED ALWAYS AS (total * 0.1) STORED
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.db2, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: Db2 FOR BIT DATA" {
    const sql =
        \\CREATE TABLE "users" (
        \\  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
        \\  "uuid_col" CHAR(16) FOR BIT DATA NOT NULL
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.db2, detect.detectSqlDialect(testing.allocator, sql));
}

test "detectSqlDialect: Db2 NOT NULL WITH DEFAULT" {
    const sql =
        \\CREATE TABLE "config" (
        \\  "id" INTEGER NOT NULL PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
        \\  "setting" VARCHAR(100) NOT NULL WITH DEFAULT 'foo'
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.db2, detect.detectSqlDialect(testing.allocator, sql));
}
