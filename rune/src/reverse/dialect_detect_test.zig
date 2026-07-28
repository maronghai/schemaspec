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
    try testing.expectEqual(codegen.Dialect.mysql, detect.detectSqlDialect(sql));
}

test "detectSqlDialect: PostgreSQL patterns" {
    const sql =
        \\CREATE TABLE "user" (
        \\  "id" integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY
        \\);
        \\COMMENT ON TABLE "user" IS 'User accounts';
    ;
    try testing.expectEqual(codegen.Dialect.pg, detect.detectSqlDialect(sql));
}

test "detectSqlDialect: SQLite patterns" {
    const sql =
        \\CREATE TABLE "user" (
        \\  "id" INTEGER PRIMARY KEY AUTOINCREMENT
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.sqlite, detect.detectSqlDialect(sql));
}

test "detectSqlDialect: SQLite STRICT" {
    const sql =
        \\CREATE TABLE "config" (
        \\  "key" TEXT NOT NULL,
        \\  "value" TEXT
        \\) STRICT;
    ;
    try testing.expectEqual(codegen.Dialect.sqlite, detect.detectSqlDialect(sql));
}

test "detectSqlDialect: PostgreSQL CREATE EXTENSION" {
    const sql =
        \\CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
        \\CREATE TABLE "items" (
        \\  "id" integer NOT NULL
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.pg, detect.detectSqlDialect(sql));
}

test "detectSqlDialect: MySQL UNSIGNED and FULLTEXT" {
    const sql =
        \\CREATE TABLE `products` (
        \\  `id` int UNSIGNED NOT NULL AUTO_INCREMENT,
        \\  FULLTEXT INDEX `idx_search` (`name`)
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detect.detectSqlDialect(sql));
}

test "detectSqlDialect: ambiguous defaults to MySQL" {
    const sql =
        \\CREATE TABLE items (
        \\  id int NOT NULL
        \\);
    ;
    try testing.expectEqual(codegen.Dialect.mysql, detect.detectSqlDialect(sql));
}
