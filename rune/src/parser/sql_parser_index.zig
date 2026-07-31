const std = @import("std");
const sp = @import("sql_parser.zig");
const common = @import("sql_parser_common.zig");
const IndexKind = common.IndexKind;
const SqlIndex = common.SqlIndex;

// ─── INDEX Declarations ───────────────────────────────────────

pub fn parsePrimaryKey(self: *sp.SqlParser) !SqlIndex {
    self.expectKeyword("PRIMARY");
    self.skipSpaces();
    self.expectKeyword("KEY");
    self.skipSpaces();
    const fl = try self.parseParenFieldList();
    return .{
        .kind = .primary_key,
        .name = "",
        .fields = fl.fields,
        .descending = fl.descending,
    };
}

pub fn parseUniqueIndex(self: *sp.SqlParser) !SqlIndex {
    self.expectKeyword("UNIQUE");
    self.skipSpaces();
    if (self.matchKeyword("INDEX") or self.matchKeyword("KEY")) {}
    self.skipSpaces();
    var name: []const u8 = "";
    if (self.peek() != '(') {
        name = try self.parseIdentifier();
    }
    self.skipSpaces();
    const fl = try self.parseParenFieldList();
    return .{
        .kind = .unique,
        .name = name,
        .fields = fl.fields,
        .descending = fl.descending,
    };
}

pub fn parseFulltextIndex(self: *sp.SqlParser) !SqlIndex {
    self.expectKeyword("FULLTEXT");
    self.skipSpaces();
    if (self.matchKeyword("INDEX") or self.matchKeyword("KEY")) {}
    self.skipSpaces();
    const name = try self.parseIdentifier();
    self.skipSpaces();
    const fl = try self.parseParenFieldList();
    return .{
        .kind = .fulltext,
        .name = name,
        .fields = fl.fields,
        .descending = fl.descending,
    };
}

pub fn parseIndex(self: *sp.SqlParser) !SqlIndex {
    if (self.matchKeyword("INDEX")) {} else if (self.matchKeyword("KEY")) {}
    self.skipSpaces();
    const name = try self.parseIdentifier();
    self.skipSpaces();
    const fl = try self.parseParenFieldList();
    return .{
        .kind = .regular,
        .name = name,
        .fields = fl.fields,
        .descending = fl.descending,
    };
}
