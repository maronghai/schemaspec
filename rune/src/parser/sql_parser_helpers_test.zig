const std = @import("std");
const testing = std.testing;
const sp = @import("sql_parser.zig");
const helpers = @import("sql_parser_helpers.zig");

fn makeParser(src: []const u8) !sp.SqlParser {
    return try sp.SqlParser.init(testing.allocator, src, .mysql);
}

test "parseWord: simple word" {
    var parser = try makeParser("hello");
    defer parser.deinit();
    const word = helpers.parseWord(&parser);
    try testing.expectEqualStrings("hello", word);
}

test "parseWord: word with digits" {
    var parser = try makeParser("test123");
    defer parser.deinit();
    const word = helpers.parseWord(&parser);
    try testing.expectEqualStrings("test123", word);
}

test "parseWord: word with underscore" {
    var parser = try makeParser("my_table");
    defer parser.deinit();
    const word = helpers.parseWord(&parser);
    try testing.expectEqualStrings("my_table", word);
}

test "parseWord: empty input" {
    var parser = try makeParser("");
    defer parser.deinit();
    const word = helpers.parseWord(&parser);
    try testing.expectEqualStrings("", word);
}

test "parseWord: stops at space" {
    var parser = try makeParser("hello world");
    defer parser.deinit();
    const word = helpers.parseWord(&parser);
    try testing.expectEqualStrings("hello", word);
}

test "parseWord: stops at comma" {
    var parser = try makeParser("col1,col2");
    defer parser.deinit();
    const word = helpers.parseWord(&parser);
    try testing.expectEqualStrings("col1", word);
}

test "skipWord: advances position" {
    var parser = try makeParser("hello world");
    defer parser.deinit();
    helpers.skipWord(&parser);
    try testing.expectEqual(@as(usize, 5), parser.pos);
}

test "peek: returns current char" {
    var parser = try makeParser("abc");
    defer parser.deinit();
    try testing.expectEqual(@as(u8, 'a'), helpers.peek(&parser));
}

test "peek: returns 0 at end" {
    var parser = try makeParser("");
    defer parser.deinit();
    try testing.expectEqual(@as(u8, 0), helpers.peek(&parser));
}

test "advance: moves position forward" {
    var parser = try makeParser("abc");
    defer parser.deinit();
    helpers.advance(&parser);
    try testing.expectEqual(@as(usize, 1), parser.pos);
}

test "skipSpaces: skips spaces and tabs" {
    var parser = try makeParser("   \thello");
    defer parser.deinit();
    helpers.skipSpaces(&parser);
    try testing.expectEqual(@as(usize, 4), parser.pos);
}

test "skipSpacesAndNewlines: skips all whitespace" {
    var parser = try makeParser("  \n  \r\n  hello");
    defer parser.deinit();
    helpers.skipSpacesAndNewlines(&parser);
    try testing.expectEqual(@as(usize, 9), parser.pos);
}

test "matchKeyword: matches exact keyword" {
    var parser = try makeParser("CREATE TABLE");
    defer parser.deinit();
    try testing.expect(helpers.matchKeyword(&parser, "CREATE"));
}

test "matchKeyword: does not match partial" {
    var parser = try makeParser("CREAT");
    defer parser.deinit();
    try testing.expect(!helpers.matchKeyword(&parser, "CREATE"));
}

test "matchKeyword: restores position on mismatch" {
    var parser = try makeParser("hello");
    defer parser.deinit();
    _ = helpers.matchKeyword(&parser, "world");
    try testing.expectEqual(@as(usize, 0), parser.pos);
}

test "lookaheadIs: checks without consuming" {
    var parser = try makeParser("CREATE TABLE");
    defer parser.deinit();
    try testing.expect(helpers.lookaheadIs(&parser, "CREATE"));
    // Position should be unchanged
    try testing.expectEqual(@as(usize, 0), parser.pos);
}

test "peekWord: returns word without consuming" {
    var parser = try makeParser("hello world");
    defer parser.deinit();
    const word = helpers.peekWord(&parser);
    try testing.expectEqualStrings("hello", word);
    // Position should be unchanged
    try testing.expectEqual(@as(usize, 0), parser.pos);
}

test "parseStringLiteral: simple string" {
    var parser = try makeParser("'hello'");
    defer parser.deinit();
    const result = try helpers.parseStringLiteral(&parser);
    try testing.expectEqualStrings("hello", result);
}

test "parseStringLiteral: string with escaped quotes" {
    var parser = try makeParser("'it''s a test'");
    defer parser.deinit();
    const result = try helpers.parseStringLiteral(&parser);
    try testing.expectEqualStrings("it''s a test", result);
}

test "parseStringLiteral: empty string" {
    var parser = try makeParser("''");
    defer parser.deinit();
    const result = try helpers.parseStringLiteral(&parser);
    try testing.expectEqualStrings("", result);
}

test "parseExpression: simple expression" {
    var parser = try makeParser("1 + 2");
    defer parser.deinit();
    const result = helpers.parseExpression(&parser);
    try testing.expectEqualStrings("1 + 2", result);
}

test "parseExpression: stops at comma" {
    var parser = try makeParser("a, b");
    defer parser.deinit();
    const result = helpers.parseExpression(&parser);
    try testing.expectEqualStrings("a", result);
}

test "parseExpression: handles balanced parens" {
    var parser = try makeParser("f(x), y");
    defer parser.deinit();
    const result = helpers.parseExpression(&parser);
    try testing.expectEqualStrings("f(x)", result);
}

test "parseExpression: stops at closing paren" {
    var parser = try makeParser("a, b)");
    defer parser.deinit();
    const result = helpers.parseExpression(&parser);
    try testing.expectEqualStrings("a", result);
}

test "parseDefaultValue: integer" {
    var parser = try makeParser("42");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("42", result);
}

test "parseDefaultValue: negative integer" {
    var parser = try makeParser("-1");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("-1", result);
}

test "parseDefaultValue: decimal" {
    var parser = try makeParser("3.14");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("3.14", result);
}

test "parseDefaultValue: string literal" {
    var parser = try makeParser("'hello'");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("hello", result);
}

test "parseDefaultValue: function call" {
    var parser = try makeParser("NOW()");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("NOW()", result);
}

test "parseDefaultValue: CURRENT_TIMESTAMP" {
    var parser = try makeParser("CURRENT_TIMESTAMP");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("CURRENT_TIMESTAMP", result);
}

test "parseDefaultValue: NULL" {
    var parser = try makeParser("NULL");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("NULL", result);
}

test "parseDefaultValue: TRUE" {
    var parser = try makeParser("TRUE");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("TRUE", result);
}

test "parseDefaultValue: parenthesized expression" {
    var parser = try makeParser("(1 + 2)");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("(1 + 2)", result);
}

test "parseDefaultValue: MySQL binary literal" {
    var parser = try makeParser("b'0101'");
    defer parser.deinit();
    const result = try helpers.parseDefaultValue(&parser);
    try testing.expectEqualStrings("b'0101'", result);
}

test "skipWhitespaceAndComments: skips line comments" {
    var parser = try makeParser("-- comment\nhello");
    defer parser.deinit();
    helpers.skipWhitespaceAndComments(&parser);
    try testing.expectEqual(@as(usize, 11), parser.pos);
}

test "skipWhitespaceAndComments: skips block comments" {
    var parser = try makeParser("/* block */ hello");
    defer parser.deinit();
    helpers.skipWhitespaceAndComments(&parser);
    // After skipping "/* block */" (positions 0-10) and space (11), position = 12
    try testing.expectEqual(@as(usize, 12), parser.pos);
}

test "skipToSemicolon: stops at semicolon" {
    var parser = try makeParser("hello; world");
    defer parser.deinit();
    helpers.skipToSemicolon(&parser);
    try testing.expectEqual(@as(usize, 6), parser.pos);
}

test "skipToSemicolon: skips quoted strings" {
    var parser = try makeParser("'hello; world'; rest");
    defer parser.deinit();
    helpers.skipToSemicolon(&parser);
    // Should stop at the second semicolon
    try testing.expectEqual(@as(usize, 15), parser.pos);
}

test "skipToSemicolon: skips comments" {
    var parser = try makeParser("-- comment; --\nrest");
    defer parser.deinit();
    helpers.skipToSemicolon(&parser);
}

test "skipToGoOrSemicolon: stops at semicolon" {
    var parser = try makeParser("hello; world");
    defer parser.deinit();
    helpers.skipToGoOrSemicolon(&parser);
    try testing.expectEqual(@as(usize, 6), parser.pos);
}

test "skipToGoOrSemicolon: stops at GO" {
    var parser = try makeParser("hello\nGO\nworld");
    defer parser.deinit();
    // SqlParser.init normalizes GO to semicolons, so effective src = "hello\n;world"
    // skipToGoOrSemicolon finds the semicolon at position 6, returns at position 7
    helpers.skipToGoOrSemicolon(&parser);
    try testing.expectEqual(@as(usize, 7), parser.pos);
}

test "readLineComment: finds comment" {
    var parser = try makeParser("  -- this is a comment\n");
    defer parser.deinit();
    const comment = helpers.readLineComment(&parser);
    try testing.expect(comment != null);
    try testing.expectEqualStrings("this is a comment", comment.?);
}

test "readLineComment: no comment returns null" {
    var parser = try makeParser("hello world");
    defer parser.deinit();
    const comment = helpers.readLineComment(&parser);
    try testing.expect(comment == null);
}

test "lineColAt: first line" {
    var parser = try makeParser("hello");
    defer parser.deinit();
    const lc = parser.lineColAt(0);
    try testing.expectEqual(@as(usize, 1), lc.line);
    try testing.expectEqual(@as(usize, 1), lc.col);
}

test "lineColAt: second line" {
    var parser = try makeParser("hello\nworld");
    defer parser.deinit();
    const lc = parser.lineColAt(6);
    try testing.expectEqual(@as(usize, 2), lc.line);
    try testing.expectEqual(@as(usize, 1), lc.col);
}

test "lineColAt: middle of line" {
    var parser = try makeParser("hello\nworld");
    defer parser.deinit();
    const lc = parser.lineColAt(8);
    try testing.expectEqual(@as(usize, 2), lc.line);
    try testing.expectEqual(@as(usize, 3), lc.col);
}
