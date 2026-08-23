const std = @import("std");
const common = @import("sql_parser_common.zig");
const ast_mod = @import("../types/ast.zig");
const diag = @import("../diagnostic.zig");
const sql_parser_create = @import("sql_parser_create.zig");
const sql_parser_fk = @import("sql_parser_fk.zig");
const sql_parser_index = @import("sql_parser_index.zig");
const sql_parser_check = @import("sql_parser_check.zig");
const sql_parser_alter = @import("sql_parser_alter.zig");
const sql_parser_comment = @import("sql_parser_comment.zig");
const sql_parser_helpers = @import("sql_parser_helpers.zig");

// Re-export common types for backward compatibility
pub const Dialect = common.Dialect;
pub const IndexKind = common.IndexKind;
pub const FkActionType = common.FkActionType;
pub const FkActionTrigger = common.FkActionTrigger;
pub const FkAction = common.FkAction;
pub const SqlColumn = common.SqlColumn;
pub const SqlIndex = common.SqlIndex;
pub const SqlForeignKey = common.SqlForeignKey;
pub const SqlCheck = common.SqlCheck;
pub const SqlTable = common.SqlTable;
pub const SqlSchema = common.SqlSchema;
pub const SqlDiagnostic = diag.Diagnostic;
pub const SqlParseResult = common.SqlParseResult;

// ─── SQL DDL Parser ──────────────────────────────────────────────

pub const SqlParser = struct {
    alloc: std.mem.Allocator,
    src: []const u8,
    pos: usize,
    diagnostics: diag.DiagnosticCollector,
    dialect: Dialect,
    /// Pre-computed line start offsets for O(log n) line/col lookup.
    line_offsets: []const usize,
    /// Whether input uses GO as batch separator (MSSQL).
    uses_go_separator: bool,
    /// Whether the parser owns the src slice (true when GO normalization allocated a new copy).
    owns_src: bool,

    pub fn init(alloc: std.mem.Allocator, src: []const u8, dialect: Dialect) !SqlParser {
        // Build line offset table: line_offsets[i] = byte offset where line (i+1) starts
        var offsets = try std.ArrayList(usize).initCapacity(alloc, 64);
        try offsets.append(alloc, 0); // line 1 starts at offset 0
        for (src, 0..) |ch, i| {
            if (ch == '\n' and i + 1 < src.len) {
                try offsets.append(alloc, i + 1);
            }
        }
        // Detect GO batch separator (MSSQL style: GO on its own line)
        const uses_go = std.mem.indexOf(u8, src, "GO\n") != null or
            std.mem.indexOf(u8, src, "GO\r\n") != null;
        // If GO separator detected, normalize: replace GO followed by newline with semicolons
        const effective_src = if (uses_go) blk: {
            var normalized = try std.ArrayList(u8).initCapacity(alloc, src.len + 16);
            var i: usize = 0;
            while (i < src.len) {
                if (i + 1 < src.len and (src[i] == 'G' or src[i] == 'g') and (src[i + 1] == 'O' or src[i + 1] == 'o')) {
                    // Check if GO is followed by newline (standalone GO)
                    if (i + 2 < src.len and (src[i + 2] == '\n' or src[i + 2] == '\r')) {
                        try normalized.append(alloc, ';');
                        i += 2; // skip GO
                        // Skip the newline after GO
                        if (i < src.len and src[i] == '\r') i += 1;
                        if (i < src.len and src[i] == '\n') i += 1;
                        continue;
                    }
                }
                try normalized.append(alloc, src[i]);
                i += 1;
            }
            break :blk try normalized.toOwnedSlice(alloc);
        } else src;
        return .{
            .alloc = alloc,
            .src = effective_src,
            .pos = 0,
            .diagnostics = try diag.DiagnosticCollector.init(alloc),
            .dialect = dialect,
            .line_offsets = try offsets.toOwnedSlice(alloc),
            .uses_go_separator = uses_go,
            .owns_src = uses_go,
        };
    }

    pub fn deinit(self: *SqlParser) void {
        self.alloc.free(self.line_offsets);
        self.diagnostics.deinit();
        if (self.owns_src) {
            self.alloc.free(self.src);
        }
    }

    pub fn lineColAt(self: *SqlParser, pos: usize) struct { line: usize, col: usize } {
        // Binary search for the line containing `pos`
        var lo: usize = 0;
        var hi: usize = self.line_offsets.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.line_offsets[mid] <= pos) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        // lo is now the 1-based line number (line_offsets[lo-1] <= pos < line_offsets[lo] or end)
        const line = lo; // 1-based
        const col = pos - self.line_offsets[lo - 1] + 1; // 1-based column
        return .{ .line = line, .col = col };
    }

    pub fn getSourceLine(self: *SqlParser, line_no: usize) ?[]const u8 {
        if (line_no < 1 or line_no > self.line_offsets.len) return null;
        const start = self.line_offsets[line_no - 1];
        var end = start;
        while (end < self.src.len and self.src[end] != '\n') end += 1;
        // Strip trailing \r
        var trimmed_end = end;
        while (trimmed_end > start and self.src[trimmed_end - 1] == '\r') trimmed_end -= 1;
        return self.src[start..trimmed_end];
    }

    pub fn reportError(self: *SqlParser, comptime fmt: []const u8, args: anytype) void {
        const pos = if (self.pos < self.src.len) self.pos else self.src.len;
        const lc = self.lineColAt(pos);
        const msg = std.fmt.allocPrint(self.alloc, fmt, args) catch return;
        const src_line = self.getSourceLine(lc.line);
        self.diagnostics.record(.{
            .severity = .@"error",
            .line_no = lc.line,
            .col = lc.col,
            .message = msg,
            .source_line = src_line,
        });
    }

    pub fn reportErrorAt(self: *SqlParser, at_pos: usize, comptime fmt: []const u8, args: anytype) void {
        const lc = self.lineColAt(at_pos);
        const msg = std.fmt.allocPrint(self.alloc, fmt, args) catch return;
        const src_line = self.getSourceLine(lc.line);
        self.diagnostics.record(.{
            .severity = .@"error",
            .line_no = lc.line,
            .col = lc.col,
            .message = msg,
            .source_line = src_line,
        });
    }

    pub fn reportWarning(self: *SqlParser, comptime fmt: []const u8, args: anytype) void {
        const pos = if (self.pos < self.src.len) self.pos else self.src.len;
        const lc = self.lineColAt(pos);
        const msg = std.fmt.allocPrint(self.alloc, fmt, args) catch return;
        const src_line = self.getSourceLine(lc.line);
        self.diagnostics.record(.{
            .severity = .warning,
            .line_no = lc.line,
            .col = lc.col,
            .message = msg,
            .source_line = src_line,
        });
    }

    pub fn parse(self: *SqlParser) !SqlParseResult {
        var schema_name: ?[]const u8 = null;
        var schema_charset: ?[]const u8 = null;
        var tables = try std.ArrayList(SqlTable).initCapacity(self.alloc, 8);
        var saw_create = false;

        while (self.pos < self.src.len) {
            self.skipSpacesAndNewlines();
            if (self.pos >= self.src.len) break;

            // Capture -- comments before skipping them (for SQLite column/table comments)
            self.captureTrailingComments(tables.items);

            // Now skip -- comments
            self.skipWhitespaceAndComments();
            if (self.pos >= self.src.len) break;

            if (self.matchKeyword("CREATE")) {
                saw_create = true;
                self.skipSpacesAndNewlines();
                if (self.matchKeyword("DATABASE")) {
                    const result = try self.parseCreateDatabase();
                    if (result.name) |n| schema_name = n;
                    if (result.charset) |c| schema_charset = c;
                } else if (self.matchKeyword("TABLE")) {
                    const table = try self.parseCreateTable();
                    try tables.append(self.alloc, table);
                } else if (self.matchKeyword("INDEX") or self.matchKeyword("UNIQUE")) {
                    try self.parseCreateStandaloneIndex(&tables);
                } else if (self.matchKeyword("EXTENSION") or self.matchKeyword("SCHEMA") or self.matchKeyword("TYPE") or self.matchKeyword("FUNCTION") or self.matchKeyword("TRIGGER") or self.matchKeyword("VIEW") or self.matchKeyword("SEQUENCE")) {
                    // PG: CREATE EXTENSION/SCHEMA/TYPE/FUNCTION/TRIGGER/VIEW/SEQUENCE — skip
                    self.skipToSemicolon();
                } else {
                    self.reportError("expected DATABASE, TABLE, or INDEX after CREATE, skipping statement", .{});
                    self.skipToSemicolon();
                }
            } else if (self.matchKeyword("ALTER")) {
                try self.parseAlterTable(tables.items);
            } else if (self.matchKeyword("COMMENT")) {
                try self.parseCommentOn(tables.items);
            } else {
                // Not a recognized statement — silently skip (DML, transactions, EXEC, etc.)
                self.skipToSemicolon();
            }
        }

        if (!saw_create) {
            self.reportError("no CREATE statement found in input", .{});
        }

        const table_slice = try tables.toOwnedSlice(self.alloc);
        if (table_slice.len == 0 and saw_create) {
            self.reportWarning("parsed schema but found no tables", .{});
        }

        return .{
            .schema = .{
                .name = schema_name,
                .charset = schema_charset,
                .tables = table_slice,
            },
            .diagnostics = try self.diagnostics.toOwnedSlice(self.alloc),
        };
    }

    /// Check if current position is a GO batch separator and advance past it.
    /// Peeks without advancing if not a GO separator.
    fn matchGoSeparator(self: *SqlParser) bool {
        const saved = self.pos;
        if (self.pos + 1 < self.src.len) {
            const c0 = self.src[self.pos];
            const c1 = self.src[self.pos + 1];
            if ((c0 == 'G' or c0 == 'g') and (c1 == 'O' or c1 == 'o')) {
                // Must be followed by newline, EOF, whitespace, comment, or (
                if (self.pos + 2 >= self.src.len) {
                    self.pos += 2;
                    return true;
                }
                const c2 = self.src[self.pos + 2];
                if (c2 == '\n' or c2 == '\r' or c2 == ' ' or c2 == '\t' or c2 == '-' or c2 == '/' or c2 == '(') {
                    self.pos += 2;
                    return true;
                }
            }
        }
        self.pos = saved;
        return false;
    }

    // ─── CREATE [UNIQUE] INDEX (standalone, PG syntax) ────────────

    fn parseCreateStandaloneIndex(self: *SqlParser, tables: *std.ArrayList(SqlTable)) !void {
        // matchKeyword consumed either INDEX or UNIQUE.
        // If UNIQUE was consumed, INDEX follows. If INDEX was consumed, no UNIQUE.
        self.skipSpaces();
        var is_unique = false;
        if (std.mem.eql(u8, self.peekWord(), "INDEX")) {
            // UNIQUE was consumed above, INDEX is next → consume it
            is_unique = true;
            self.skipWord();
            self.skipSpaces();
        }
        _ = self.matchKeyword("IF");
        _ = self.matchKeyword("NOT");
        _ = self.matchKeyword("EXISTS");
        self.skipSpaces();
        const idx_name = try self.parseIdentifier();
        self.skipSpaces();
        _ = self.matchKeyword("ON");
        self.skipSpaces();
        const tbl_ident = try self.parseIdentifier();
        const tbl_name = blk: {
            if (std.mem.lastIndexOfScalar(u8, tbl_ident, '.')) |dot_pos|
                break :blk tbl_ident[dot_pos + 1 ..];
            break :blk tbl_ident;
        };
        self.skipSpaces();
        if (self.peek() == '(') {
            const fl = try self.parseParenFieldList();
            const kind: IndexKind = if (is_unique) .unique else .regular;
            const idx = SqlIndex{
                .kind = kind,
                .name = idx_name,
                .fields = fl.fields,
                .descending = fl.descending,
            };
            for (tables.items) |*tbl| {
                if (std.mem.eql(u8, tbl.name, tbl_name)) {
                    const old = tbl.indexes;
                    const new_indexes = try self.alloc.alloc(SqlIndex, old.len + 1);
                    for (old, 0..) |o, i| new_indexes[i] = o;
                    new_indexes[old.len] = idx;
                    self.alloc.free(old);
                    tbl.indexes = new_indexes;
                    break;
                }
            }
        }
        self.skipToSemicolon();
    }

    // ─── Delegated sub-module methods ──────────────────────────────

    pub fn parseAlterTable(self: *SqlParser, tables: []SqlTable) !void {
        return sql_parser_alter.parseAlterTable(self, tables);
    }

    pub fn parseCommentOn(self: *SqlParser, tables: []SqlTable) !void {
        return sql_parser_comment.parseCommentOn(self, tables);
    }

    // ─── CREATE DATABASE / TABLE / Column ──────────────────────────

    pub fn parseCreateDatabase(self: *SqlParser) !common.CreateDbResult {
        return sql_parser_create.parseCreateDatabase(self);
    }

    pub fn parseCreateTable(self: *SqlParser) !SqlTable {
        return sql_parser_create.parseCreateTable(self);
    }

    pub fn parseColumn(self: *SqlParser) !SqlColumn {
        return sql_parser_create.parseColumn(self);
    }

    pub fn parseColumnType(self: *SqlParser) ![]const u8 {
        return sql_parser_create.parseColumnType(self);
    }

    // ─── FOREIGN KEY ──────────────────────────────────────────────

    pub fn parseForeignKey(self: *SqlParser) !SqlForeignKey {
        return sql_parser_fk.parseForeignKey(self);
    }

    pub fn parseInlineReferences(self: *SqlParser) !SqlForeignKey {
        return sql_parser_fk.parseInlineReferences(self);
    }

    // ─── INDEX declarations ───────────────────────────────────────

    pub fn parsePrimaryKey(self: *SqlParser) !SqlIndex {
        return sql_parser_index.parsePrimaryKey(self);
    }

    pub fn parseUniqueIndex(self: *SqlParser) !SqlIndex {
        return sql_parser_index.parseUniqueIndex(self);
    }

    pub fn parseFulltextIndex(self: *SqlParser) !SqlIndex {
        return sql_parser_index.parseFulltextIndex(self);
    }

    pub fn parseIndex(self: *SqlParser) !SqlIndex {
        return sql_parser_index.parseIndex(self);
    }

    // ─── CHECK constraint ─────────────────────────────────────────

    pub fn parseCheck(self: *SqlParser) !SqlCheck {
        return sql_parser_check.parseCheck(self);
    }

    pub fn parseCheckExpr(self: *SqlParser) ![]const u8 {
        return sql_parser_check.parseCheckExpr(self);
    }

    // ─── Helpers (delegated to sql_parser_helpers.zig) ─────────────

    pub fn parseIdentifier(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseIdentifier(self);
    }

    pub fn parseDottedIdentifier(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseDottedIdentifier(self);
    }

    pub fn parseBacktickIdent(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseBacktickIdent(self);
    }

    pub fn parseDoubleQuoteIdent(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseDoubleQuoteIdent(self);
    }

    pub fn parseUnquotedWord(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseUnquotedWord(self);
    }

    pub fn parseStringLiteral(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseStringLiteral(self);
    }

    pub fn parseDefaultValue(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseDefaultValue(self);
    }

    pub const FieldList = sql_parser_helpers.FieldList;

    pub fn parseParenFieldList(self: *SqlParser) !FieldList {
        return sql_parser_helpers.parseParenFieldList(self);
    }

    pub fn parseParenExpr(self: *SqlParser) ![]const u8 {
        return sql_parser_helpers.parseParenExpr(self);
    }

    pub fn parseWord(self: *SqlParser) []const u8 {
        return sql_parser_helpers.parseWord(self);
    }

    pub fn skipWord(self: *SqlParser) void {
        sql_parser_helpers.skipWord(self);
    }

    pub fn matchKeyword(self: *SqlParser, kw: []const u8) bool {
        return sql_parser_helpers.matchKeyword(self, kw);
    }

    pub fn expectKeyword(self: *SqlParser, kw: []const u8) void {
        sql_parser_helpers.expectKeyword(self, kw);
    }

    pub fn expect(self: *SqlParser, ch: u8) void {
        sql_parser_helpers.expect(self, ch);
    }

    pub fn lookaheadIs(self: *SqlParser, kw: []const u8) bool {
        return sql_parser_helpers.lookaheadIs(self, kw);
    }

    pub fn peekWord(self: *SqlParser) []const u8 {
        return sql_parser_helpers.peekWord(self);
    }

    pub fn peek(self: *SqlParser) u8 {
        return sql_parser_helpers.peek(self);
    }

    pub fn advance(self: *SqlParser) void {
        sql_parser_helpers.advance(self);
    }

    pub fn skipSpaces(self: *SqlParser) void {
        sql_parser_helpers.skipSpaces(self);
    }

    pub fn skipSpacesAndNewlines(self: *SqlParser) void {
        sql_parser_helpers.skipSpacesAndNewlines(self);
    }

    pub fn skipWhitespaceAndComments(self: *SqlParser) void {
        sql_parser_helpers.skipWhitespaceAndComments(self);
    }

    pub fn skipToSemicolon(self: *SqlParser) void {
        sql_parser_helpers.skipToSemicolon(self);
    }

    pub fn skipToGoOrSemicolon(self: *SqlParser) void {
        sql_parser_helpers.skipToGoOrSemicolon(self);
    }

    pub fn expectStatementEnd(self: *SqlParser) void {
        sql_parser_helpers.expectStatementEnd(self);
    }

    pub fn readLineComment(self: *SqlParser) ?[]const u8 {
        return sql_parser_helpers.readLineComment(self);
    }

    pub fn captureTrailingComments(self: *SqlParser, tables: []SqlTable) void {
        sql_parser_helpers.captureTrailingComments(self, tables);
    }

    /// Skip Oracle/Db2 identity options after GENERATED ... AS IDENTITY.
    /// Options: START WITH, INCREMENT BY, MINVALUE, MAXVALUE, NOCYCLE, CACHE, NOORDER, etc.
    pub fn skipIdentityOptions(self: *SqlParser) void {
        while (self.pos < self.src.len) {
            self.skipSpacesAndNewlines();
            // Stop at column结束 markers
            const ch = self.peek();
            if (ch == ',' or ch == ')' or ch == ';' or ch == 0) break;

            // Stop at column modifier keywords (these are NOT identity options)
            if (self.lookaheadIs("PRIMARY") or self.lookaheadIs("NOT") or
                self.lookaheadIs("NULL") or self.lookaheadIs("DEFAULT") or
                self.lookaheadIs("COMMENT") or self.lookaheadIs("UNIQUE") or
                self.lookaheadIs("CHECK") or self.lookaheadIs("REFERENCES") or
                self.lookaheadIs("ON") or self.lookaheadIs("GENERATED") or
                self.lookaheadIs("AS") or self.lookaheadIs("AUTO_INCREMENT") or
                self.lookaheadIs("UNSIGNED"))
            {
                break;
            }

            // Try to match identity option keywords
            if (self.matchKeyword("START") or self.matchKeyword("INCREMENT") or
                self.matchKeyword("MINVALUE") or self.matchKeyword("MAXVALUE") or
                self.matchKeyword("NOCYCLE") or self.matchKeyword("CYCLE") or
                self.matchKeyword("CACHE") or self.matchKeyword("NOCACHE") or
                self.matchKeyword("NOORDER") or self.matchKeyword("ORDER") or
                self.matchKeyword("NOMAXVALUE") or self.matchKeyword("NOMINVALUE") or
                self.matchKeyword("GLOBAL") or self.matchKeyword("LOCAL"))
            {
                self.skipSpaces();
                // Some options take a value (e.g., START WITH 1, INCREMENT BY 1, CACHE 10)
                // Skip the value if present
                if (self.peek() == '-' or self.peek() == '+' or
                    (self.peek() >= '0' and self.peek() <= '9'))
                {
                    // Skip numeric value
                    while (self.pos < self.src.len) {
                        const c = self.peek();
                        if (c >= '0' and c <= '9' or c == '.' or c == '-' or c == '+') {
                            self.advance();
                        } else break;
                    }
                } else if (self.peek() == '(') {
                    // Skip parenthesized value (e.g., CACHE 100)
                    self.advance();
                    var depth: usize = 1;
                    while (self.pos < self.src.len and depth > 0) {
                        const c = self.peek();
                        if (c == '(') depth += 1 else if (c == ')') depth -= 1;
                        if (depth > 0) self.advance();
                    }
                    if (self.peek() == ')') self.advance();
                } else if (self.peek() == 'N' or self.peek() == 'n') {
                    // Skip NULL or NOCYCLE-like keywords
                    while (self.pos < self.src.len) {
                        const c = self.peek();
                        if (c >= 'A' and c <= 'Z' or c >= 'a' and c <= 'z' or c >= '0' and c <= '9' or c == '_') {
                            self.advance();
                        } else break;
                    }
                }
            } else {
                // Unknown keyword - stop to let the caller handle it
                break;
            }
        }
    }
};
