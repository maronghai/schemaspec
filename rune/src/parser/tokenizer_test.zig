const std = @import("std");
const tokenizer = @import("tokenizer.zig");
const LineType = tokenizer.LineType;
const Tokenizer = tokenizer.Tokenizer;

test "classifyLine: $ is Schema" {
    try std.testing.expectEqual(LineType.Schema, Tokenizer.classifyLine("$ mydb"));
}

test "classifyLine: % is Template" {
    try std.testing.expectEqual(LineType.Template, Tokenizer.classifyLine("% base"));
}

test "classifyLine: # is Table" {
    try std.testing.expectEqual(LineType.Table, Tokenizer.classifyLine("# user"));
}

test "classifyLine: & is View" {
    try std.testing.expectEqual(LineType.View, Tokenizer.classifyLine("& active_users = SELECT id FROM users"));
}

test "classifyLine: > is FK" {
    try std.testing.expectEqual(LineType.FK, Tokenizer.classifyLine("> user_id users.id"));
}

test "classifyLine: ! is CompositePK" {
    try std.testing.expectEqual(LineType.CompositePK, Tokenizer.classifyLine("!"));
}

test "classifyLine: @ is Index" {
    try std.testing.expectEqual(LineType.Index, Tokenizer.classifyLine("@ idx_name (name)"));
}

test "classifyLine: ^ is Engine" {
    try std.testing.expectEqual(LineType.Engine, Tokenizer.classifyLine("^ InnoDB"));
}

test "classifyLine: ... is Slot" {
    try std.testing.expectEqual(LineType.Slot, Tokenizer.classifyLine("..."));
}

test "classifyLine: plain text is Field" {
    try std.testing.expectEqual(LineType.Field, Tokenizer.classifyLine("name s32 *"));
}

test "tokenizeLine: simple field" {
    const alloc = std.testing.allocator;
    const toks = try Tokenizer.tokenizeLine(alloc, "name s32 *");
    defer alloc.free(toks);
    try std.testing.expectEqual(@as(usize, 3), toks.len);
    try std.testing.expectEqualStrings("name", toks[0]);
    try std.testing.expectEqualStrings("s32", toks[1]);
    try std.testing.expectEqualStrings("*", toks[2]);
}

test "tokenizeLine: fused type modifier" {
    const alloc = std.testing.allocator;
    const toks = try Tokenizer.tokenizeLine(alloc, "id n++");
    defer alloc.free(toks);
    try std.testing.expectEqual(@as(usize, 2), toks.len);
    try std.testing.expectEqualStrings("id", toks[0]);
    try std.testing.expectEqualStrings("n++", toks[1]);
}

test "tokenizeLine: table header" {
    const alloc = std.testing.allocator;
    const toks = try Tokenizer.tokenizeLine(alloc, "# base user");
    defer alloc.free(toks);
    try std.testing.expectEqual(@as(usize, 3), toks.len);
    try std.testing.expectEqualStrings("#", toks[0]);
    try std.testing.expectEqualStrings("base", toks[1]);
    try std.testing.expectEqualStrings("user", toks[2]);
}

test "tokenizeLine: enum type" {
    const alloc = std.testing.allocator;
    const toks = try Tokenizer.tokenizeLine(alloc, "status e(A,B,C)");
    defer alloc.free(toks);
    try std.testing.expectEqual(@as(usize, 5), toks.len);
    try std.testing.expectEqualStrings("status", toks[0]);
    try std.testing.expectEqualStrings("e", toks[1]);
    try std.testing.expectEqualStrings("(", toks[2]);
    try std.testing.expectEqualStrings("A,B,C", toks[3]);
    try std.testing.expectEqualStrings(")", toks[4]);
}

test "tokenizeLine: comment stops at --" {
    const alloc = std.testing.allocator;
    const toks = try Tokenizer.tokenizeLine(alloc, "name s32 -- varchar type");
    defer alloc.free(toks);
    try std.testing.expectEqual(@as(usize, 2), toks.len);
    try std.testing.expectEqualStrings("name", toks[0]);
    try std.testing.expectEqualStrings("s32", toks[1]);
}

test "tokenizeLine: inline FK" {
    const alloc = std.testing.allocator;
    const toks = try Tokenizer.tokenizeLine(alloc, "user_id n > users.id");
    defer alloc.free(toks);
    try std.testing.expectEqual(@as(usize, 4), toks.len);
    try std.testing.expectEqualStrings("user_id", toks[0]);
    try std.testing.expectEqualStrings("n", toks[1]);
    try std.testing.expectEqualStrings(">", toks[2]);
    try std.testing.expectEqualStrings("users.id", toks[3]);
}

test "tokenizeLine: default value" {
    const alloc = std.testing.allocator;
    const toks = try Tokenizer.tokenizeLine(alloc, "status s =active");
    defer alloc.free(toks);
    try std.testing.expectEqual(@as(usize, 3), toks.len);
    try std.testing.expectEqualStrings("status", toks[0]);
    try std.testing.expectEqualStrings("s", toks[1]);
    try std.testing.expectEqualStrings("=active", toks[2]);
}

test "tokenizeAll: empty lines" {
    const alloc = std.testing.allocator;
    const lines = [_][]const u8{ "", "  ", "" };
    const tok = Tokenizer.init(&lines);
    const result = try tok.tokenizeAll(alloc);
    defer alloc.free(result);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(LineType.Empty, result[0].line_type);
    try std.testing.expectEqual(LineType.Empty, result[1].line_type);
    try std.testing.expectEqual(LineType.Empty, result[2].line_type);
}

test "tokenizeAll: mixed content" {
    const alloc = std.testing.allocator;
    const lines = [_][]const u8{ "$ mydb", "", "# user", "name s32 *" };
    const tok = Tokenizer.init(&lines);
    const result = try tok.tokenizeAll(alloc);
    defer {
        for (result) |line| {
            if (line.tokens.len > 0) alloc.free(line.tokens);
        }
        alloc.free(result);
    }
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqual(LineType.Schema, result[0].line_type);
    try std.testing.expectEqual(LineType.Empty, result[1].line_type);
    try std.testing.expectEqual(LineType.Table, result[2].line_type);
    try std.testing.expectEqual(LineType.Field, result[3].line_type);
}

test "tokenizeAll: spec comment" {
    const alloc = std.testing.allocator;
    const lines = [_][]const u8{"; this is a spec comment"};
    const tok = Tokenizer.init(&lines);
    const result = try tok.tokenizeAll(alloc);
    defer alloc.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(LineType.SpecComment, result[0].line_type);
}

test "tokenizeAll: SQL comment" {
    const alloc = std.testing.allocator;
    const lines = [_][]const u8{"-- CREATE TABLE foo ("};
    const tok = Tokenizer.init(&lines);
    const result = try tok.tokenizeAll(alloc);
    defer alloc.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqual(LineType.SQLComment, result[0].line_type);
}
