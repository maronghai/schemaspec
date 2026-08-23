const std = @import("std");
const sp = @import("sql_parser.zig");
const common = @import("sql_parser_common.zig");
const Dialect = common.Dialect;
const SqlColumn = common.SqlColumn;
const SqlTable = common.SqlTable;
const SqlIndex = common.SqlIndex;
const SqlForeignKey = common.SqlForeignKey;
const SqlCheck = common.SqlCheck;

// ─── CREATE DATABASE / TABLE / Column Parsing ────────────────

pub fn parseCreateDatabase(self: *sp.SqlParser) !common.CreateDbResult {
    self.skipSpaces();
    if (self.matchKeyword("IF")) {
        _ = self.matchKeyword("NOT");
        _ = self.matchKeyword("EXISTS");
    }
    const name = try self.parseIdentifier();
    var charset: ?[]const u8 = null;

    self.skipSpaces();
    while (self.peek() != ';' and self.pos < self.src.len) {
        if (self.matchKeyword("CHARACTER")) {
            self.skipSpaces();
            if (self.matchKeyword("SET")) {
                self.skipSpaces();
                charset = try self.parseUnquotedWord();
            }
        } else if (self.matchKeyword("CHARSET")) {
            self.skipSpaces();
            charset = try self.parseUnquotedWord();
        } else if (self.matchKeyword("ENCODING")) {
            self.skipSpaces();
            if (self.peek() == '\'') {
                charset = try self.parseStringLiteral();
            } else {
                charset = try self.parseUnquotedWord();
            }
        } else if (self.matchKeyword("LC_COLLATE") or self.matchKeyword("LC_CTYPE") or self.matchKeyword("TEMPLATE") or self.matchKeyword("CONNECTION") or self.matchKeyword("IS_TEMPLATE")) {
            self.skipSpaces();
            if (self.peek() == '\'') {
                _ = self.parseStringLiteral() catch {};
            } else {
                self.skipWord();
            }
        } else {
            self.advance();
        }
    }
    self.expect(';');
    return .{ .name = name, .charset = charset };
}

pub fn parseCreateTable(self: *sp.SqlParser) !SqlTable {
    self.skipSpaces();
    if (self.matchKeyword("IF")) {
        _ = self.matchKeyword("NOT");
        _ = self.matchKeyword("EXISTS");
    }
    self.skipSpaces();
    const name = try self.parseDottedIdentifier();
    self.skipSpaces();
    self.expect('(');

    var columns = try std.ArrayList(SqlColumn).initCapacity(self.alloc, 16);
    var indexes = try std.ArrayList(SqlIndex).initCapacity(self.alloc, 4);
    var foreign_keys = try std.ArrayList(SqlForeignKey).initCapacity(self.alloc, 4);
    var checks = try std.ArrayList(SqlCheck).initCapacity(self.alloc, 4);

    while (self.pos < self.src.len) {
        self.skipSpacesAndNewlines();
        if (self.peek() == ')') break;

        const save = self.pos;
        self.skipWhitespaceAndComments();
        if (self.peek() == ')') break;
        self.pos = save;

        self.skipSpacesAndNewlines();
        if (self.peek() == ')') break;
        if (self.peek() == ',') {
            self.advance();
            continue;
        }

        if (self.lookaheadIs("CONSTRAINT")) {
            self.skipSpacesAndNewlines();
            self.skipWord(); // consume "CONSTRAINT"
            self.skipSpaces();
            _ = try self.parseIdentifier();
            self.skipSpaces();
            if (self.lookaheadIs("PRIMARY")) {
                const idx = try self.parsePrimaryKey();
                try indexes.append(self.alloc, idx);
            } else if (self.lookaheadIs("UNIQUE")) {
                const idx = try self.parseUniqueIndex();
                try indexes.append(self.alloc, idx);
            } else if (self.lookaheadIs("CHECK")) {
                const ck = try self.parseCheck();
                try checks.append(self.alloc, ck);
            } else if (self.lookaheadIs("FOREIGN")) {
                const fk = try self.parseForeignKey();
                try foreign_keys.append(self.alloc, fk);
            }
        } else if (self.lookaheadIs("FOREIGN")) {
            const fk = try self.parseForeignKey();
            try foreign_keys.append(self.alloc, fk);
        } else if (self.lookaheadIs("PRIMARY")) {
            const idx = try self.parsePrimaryKey();
            try indexes.append(self.alloc, idx);
        } else if (self.lookaheadIs("UNIQUE")) {
            const idx = try self.parseUniqueIndex();
            try indexes.append(self.alloc, idx);
        } else if (self.lookaheadIs("FULLTEXT")) {
            if (self.dialect == .pg or self.dialect == .sqlite) {
                self.reportWarning("FULLTEXT index not supported inline in this dialect, skipping", .{});
                self.skipToSemicolon();
            } else {
                const idx = try self.parseFulltextIndex();
                try indexes.append(self.alloc, idx);
            }
        } else if (self.lookaheadIs("INDEX") or self.lookaheadIs("KEY")) {
            if (self.dialect == .pg) {
                self.reportWarning("inline INDEX/KEY not supported in PostgreSQL, skipping", .{});
                self.skipToSemicolon();
            } else if (self.dialect == .sqlite) {
                self.reportWarning("inline INDEX not supported in SQLite, skipping", .{});
                self.skipToSemicolon();
            } else {
                const idx = try self.parseIndex();
                try indexes.append(self.alloc, idx);
            }
        } else if (self.lookaheadIs("CHECK")) {
            const ck = try self.parseCheck();
            try checks.append(self.alloc, ck);
        } else {
            const col = try parseColumn(self);
            try columns.append(self.alloc, col);
        }

        self.skipSpacesAndNewlines();
        if (self.peek() == ',') self.advance();
    }

    self.expect(')');

    const table_columns = try columns.toOwnedSlice(self.alloc);

    {
        var resolved_checks = try std.ArrayList(SqlCheck).initCapacity(self.alloc, checks.items.len);
        for (checks.items) |*ck| {
            var resolved_field: []const u8 = "";
            for (table_columns) |col| {
                if (ck.expr.len >= col.name.len and std.mem.eql(u8, ck.expr[0..col.name.len], col.name)) {
                    resolved_field = col.name;
                    break;
                }
            }
            try resolved_checks.append(self.alloc, .{
                .field_name = resolved_field,
                .expr = ck.expr,
            });
        }
        checks.deinit(self.alloc);
        checks = resolved_checks;
    }

    var engine: ?[]const u8 = null;
    var charset: ?[]const u8 = null;
    var comment: ?[]const u8 = null;

    while (self.pos < self.src.len) {
        self.skipSpacesAndNewlines();
        if (self.pos >= self.src.len or self.peek() == ';') break;

        if (self.matchKeyword("ENGINE")) {
            self.skipSpaces();
            if (self.peek() == '=') self.advance();
            self.skipSpaces();
            engine = try self.parseUnquotedWord();
        } else if (self.matchKeyword("DEFAULT")) {
            self.skipSpaces();
            if (self.matchKeyword("CHARSET")) {
                self.skipSpaces();
                if (self.peek() == '=') self.advance();
                self.skipSpaces();
                charset = try self.parseUnquotedWord();
            }
        } else if (self.matchKeyword("CHARSET")) {
            self.skipSpaces();
            if (self.peek() == '=') self.advance();
            self.skipSpaces();
            charset = try self.parseUnquotedWord();
        } else if (self.matchKeyword("COMMENT")) {
            self.skipSpaces();
            if (self.peek() == '=') self.advance();
            self.skipSpaces();
            comment = try self.parseStringLiteral();
        } else {
            // Unrecognized table option — skip the keyword and any value
            self.skipWord();
            self.skipSpaces();
            if (self.peek() == '=') {
                self.advance();
                self.skipSpaces();
                if (self.peek() == '\'') {
                    _ = self.parseStringLiteral() catch {};
                } else {
                    self.skipWord();
                }
            } else if (self.peek() == '(') {
                // Skip parenthesized value (e.g., STORAGE (...), CHECK (...))
                var depth: usize = 1;
                self.advance();
                while (self.pos < self.src.len and depth > 0) {
                    const c = self.src[self.pos];
                    if (c == '(') depth += 1 else if (c == ')') depth -= 1;
                    if (depth > 0) self.pos += 1;
                }
                if (self.pos < self.src.len) self.pos += 1; // closing )
            }
        }
    }
    self.expect(';');

    return .{
        .name = name,
        .engine = engine,
        .charset = charset,
        .comment = comment,
        .columns = table_columns,
        .indexes = try indexes.toOwnedSlice(self.alloc),
        .foreign_keys = try foreign_keys.toOwnedSlice(self.alloc),
        .checks = try checks.toOwnedSlice(self.alloc),
    };
}

pub fn parseColumn(self: *sp.SqlParser) !SqlColumn {
    const name = try self.parseIdentifier();
    self.skipSpaces();

    var type_sql = try self.parseColumnType();

    var pg_serial_auto_inc = false;
    if (self.dialect == .pg) {
        const trimmed = std.mem.trim(u8, type_sql, " \t");
        if (std.mem.eql(u8, trimmed, "serial")) {
            type_sql = "integer";
            pg_serial_auto_inc = true;
        } else if (std.mem.eql(u8, trimmed, "bigserial")) {
            type_sql = "bigint";
            pg_serial_auto_inc = true;
        }
    }

    var nullable = true;
    var unsigned = false;
    var auto_increment = pg_serial_auto_inc;
    var primary_key = false;
    var on_update = false;
    var default_val: ?[]const u8 = null;
    var check_expr: ?[]const u8 = null;
    var comment: ?[]const u8 = null;
    var generated_expr: ?[]const u8 = null;
    var is_stored = false;
    var is_virtual = false;
    var inline_fk: ?*SqlForeignKey = null;

    self.skipSpaces();
    while (self.pos < self.src.len) {
        const ch = self.peek();
        if (ch == ',' or ch == ')' or ch == '\n' or ch == '\r') break;
        if (ch == ' ' or ch == '\t') {
            self.skipSpaces();
            continue;
        }

        // Handle inline /* block comments */ (Oracle/Db2 style column comments)
        if (ch == '/' and self.pos + 1 < self.src.len and self.src[self.pos + 1] == '*') {
            self.advance(); // skip /
            self.advance(); // skip *
            const comment_start = self.pos;
            while (self.pos + 1 < self.src.len) {
                if (self.src[self.pos] == '*' and self.src[self.pos + 1] == '/') {
                    const comment_text = std.mem.trim(u8, self.src[comment_start..self.pos], " \t");
                    if (comment_text.len > 0 and comment == null) {
                        comment = comment_text;
                    }
                    self.advance(); // skip *
                    self.advance(); // skip /
                    break;
                }
                self.advance();
            }
            self.skipSpaces();
            continue;
        }

        if (self.matchKeyword("NOT")) {
            self.skipSpaces();
            if (self.matchKeyword("NULL")) {
                nullable = false;
            }
        } else if (self.matchKeyword("NULL")) {
            nullable = true;
        } else if (self.matchKeyword("CHARACTER")) {
            self.skipSpaces();
            if (self.matchKeyword("SET")) {
                self.skipSpaces();
                self.skipWord();
                self.skipSpaces();
                if (self.matchKeyword("COLLATE")) {
                    self.skipSpaces();
                    self.skipWord();
                }
            }
        } else if (self.matchKeyword("COLLATE")) {
            self.skipSpaces();
            self.skipWord();
        } else if (self.matchKeyword("UNSIGNED")) {
            if (self.dialect == .mysql) unsigned = true;
        } else if (self.matchKeyword("AUTO_INCREMENT") or self.matchKeyword("AUTOINCREMENT")) {
            auto_increment = true;
        } else if (self.matchKeyword("GENERATED")) {
            self.skipSpaces();
            // Handle: GENERATED ALWAYS AS IDENTITY (Db2)
            //         GENERATED BY DEFAULT AS IDENTITY (Oracle)
            //         GENERATED BY DEFAULT ON NULL AS IDENTITY (Oracle)
            //         GENERATED ALWAYS AS IDENTITY START WITH 1 INCREMENT BY 1 (Oracle/Db2 with options)
            _ = self.matchKeyword("ALWAYS");
            _ = self.matchKeyword("BY");
            _ = self.matchKeyword("DEFAULT");
            // Oracle: skip "ON NULL" between DEFAULT and AS
            _ = self.matchKeyword("ON");
            _ = self.matchKeyword("NULL");
            self.skipSpaces();
            if (self.matchKeyword("AS")) {
                self.skipSpaces();
                if (self.matchKeyword("IDENTITY")) {
                    auto_increment = true;
                    // Skip Oracle/Db2 identity options: START WITH, INCREMENT BY, MINVALUE, MAXVALUE, etc.
                    self.skipIdentityOptions();
                } else if (self.peek() == '(') {
                    const expr_start = self.pos;
                    self.advance();
                    var depth: usize = 1;
                    while (self.pos < self.src.len and depth > 0) {
                        const c = self.peek();
                        if (c == '(') depth += 1 else if (c == ')') depth -= 1;
                        if (depth > 0) self.advance();
                    }
                    if (self.peek() == ')') self.advance();
                    const expr_end = self.pos;
                    generated_expr = self.src[expr_start..expr_end];
                    self.skipSpaces();
                    if (self.matchKeyword("STORED")) {
                        is_stored = true;
                    } else if (self.matchKeyword("VIRTUAL")) {
                        is_virtual = true;
                    }
                }
            }
        } else if (self.matchKeyword("PRIMARY")) {
            self.skipSpaces();
            if (self.matchKeyword("KEY")) {
                primary_key = true;
            }
        } else if (self.matchKeyword("UNIQUE")) {
            // Column-level UNIQUE — skip
        } else if (self.matchKeyword("DEFAULT")) {
            self.skipSpaces();
            default_val = try self.parseDefaultValue();
        } else if (self.matchKeyword("COMMENT")) {
            self.skipSpaces();
            comment = try self.parseStringLiteral();
        } else if (self.matchKeyword("ON")) {
            self.skipSpaces();
            if (self.matchKeyword("UPDATE")) {
                on_update = true;
                self.skipSpaces();
                self.skipWord();
            }
        } else if (self.matchKeyword("CHECK")) {
            self.skipSpaces();
            if (self.peek() == '(') {
                check_expr = try self.parseParenExpr();
            }
        } else if (self.matchKeyword("references") or self.matchKeyword("REFERENCES")) {
            // Inline column-level FK: capture table, optional column list, and
            // ON DELETE/UPDATE actions. Previously this branch only skipped the
            // tokens, silently dropping the FK from the reverse pipeline.
            if (self.parseInlineReferences()) |fk| {
                inline_fk = try self.alloc.create(SqlForeignKey);
                inline_fk.?.* = fk;
            } else |err| {
                if (err != error.ExpectedDeleteOrUpdate and err != error.ExpectedFkAction) return err;
                // Unparseable action list: keep the reference without actions.
            }
        } else if (self.matchKeyword("AS")) {
            // Short form: col_name type AS (expr) [STORED|VIRTUAL]
            self.skipSpaces();
            if (self.peek() == '(') {
                const expr_start = self.pos;
                self.advance();
                var depth: usize = 1;
                while (self.pos < self.src.len and depth > 0) {
                    const c = self.peek();
                    if (c == '(') depth += 1 else if (c == ')') depth -= 1;
                    if (depth > 0) self.advance();
                }
                if (self.peek() == ')') self.advance();
                const expr_end = self.pos;
                generated_expr = self.src[expr_start..expr_end];
                self.skipSpaces();
                if (self.matchKeyword("STORED")) {
                    is_stored = true;
                } else if (self.matchKeyword("VIRTUAL")) {
                    is_virtual = true;
                }
            }
        } else if (self.matchKeyword("IDENTITY")) {
            // MSSQL: IDENTITY(seed, increment) — auto_increment
            auto_increment = true;
            self.skipSpaces();
            if (self.peek() == '(') {
                self.advance(); // skip (
                while (self.peek() != ')' and self.pos < self.src.len) self.advance();
                if (self.peek() == ')') self.advance();
            }
        } else {
            break;
        }
        self.skipSpaces();
    }

    // Advance past trailing newline so the caller's loop sees the next token (e.g. ')' or ',')
    if (self.pos < self.src.len and self.src[self.pos] == '\n') self.pos += 1;

    return .{
        .name = name,
        .type_sql = type_sql,
        .nullable = nullable,
        .unsigned = unsigned,
        .auto_increment = auto_increment,
        .primary_key = primary_key,
        .on_update_current_timestamp = on_update,
        .default_val = default_val,
        .check_expr = check_expr,
        .comment = comment,
        .generated_expr = generated_expr,
        .is_stored = is_stored,
        .is_virtual = is_virtual,
        .inline_fk = inline_fk,
    };
}

pub fn parseColumnType(self: *sp.SqlParser) ![]const u8 {
    const start = self.pos;
    self.skipWord();
    if (self.pos < self.src.len and self.peek() == '(') {
        self.advance();
        var depth: usize = 1;
        while (self.pos < self.src.len and depth > 0) {
            const c = self.peek();
            if (c == '(') depth += 1 else if (c == ')') depth -= 1;
            if (depth > 0) self.advance();
        }
        if (self.peek() == ')') self.advance();
    }
    // Handle multi-word types: TIMESTAMP WITH TIME ZONE, DOUBLE PRECISION, etc.
    // Continue reading if the next word is a type continuation keyword.
    while (self.pos < self.src.len) {
        const saved_before_space = self.pos;
        self.skipSpaces();
        const word = self.peekWord();
        // Type continuation keywords (not column modifiers)
        if (std.mem.eql(u8, word, "WITH") or std.mem.eql(u8, word, "TIME") or
            std.mem.eql(u8, word, "ZONE") or std.mem.eql(u8, word, "LOCAL") or
            std.mem.eql(u8, word, "PRECISION") or std.mem.eql(u8, word, "VARYING") or
            std.mem.eql(u8, word, "FOR") or std.mem.eql(u8, word, "BIT") or
            std.mem.eql(u8, word, "DATA"))
        {
            self.pos = self.pos + word.len; // advance past the word
        } else {
            self.pos = saved_before_space; // not a continuation keyword, restore to before whitespace
            break;
        }
    }
    return self.src[start..self.pos];
}
