const std = @import("std");
const sp = @import("sql_parser.zig");
const common = @import("sql_parser_common.zig");
const SqlTable = common.SqlTable;
const SqlForeignKey = common.SqlForeignKey;
const create_parser = @import("sql_parser_create.zig");

// ─── ALTER TABLE Parsing ────────────────────────────────────────

pub fn parseAlterTable(self: *sp.SqlParser, tables: []SqlTable) !void {
    // ALTER TABLE ... ADD [COLUMN] c TYPE ..., ADD CONSTRAINT ... FOREIGN KEY ...
    self.skipSpacesAndNewlines();
    if (self.matchKeyword("TABLE")) {
        self.skipSpaces();
        const tbl_name = try self.parseIdentifier();
        self.skipSpaces();
        if (self.matchKeyword("ADD")) {
            self.skipSpaces();
            _ = self.matchKeyword("COLUMN"); // optional keyword
            self.skipSpaces();
            // Optional: CONSTRAINT constraint_name
            if (self.matchKeyword("CONSTRAINT")) {
                self.skipSpaces();
                _ = try self.parseIdentifier(); // constraint name
                self.skipSpaces();
            }
            if (self.matchKeyword("FOREIGN")) {
                // ALTER TABLE t ADD [CONSTRAINT fk] FOREIGN KEY (cols) REFERENCES ref (cols) [actions]
                self.skipSpaces();
                const fk = try self.parseForeignKey();
                // Find the table and append the FK, replacing the slice
                for (tables) |*tbl| {
                    if (std.mem.eql(u8, tbl.name, tbl_name)) {
                        const new_len = tbl.foreign_keys.len + 1;
                        var new_fks = try self.alloc.alloc(SqlForeignKey, new_len);
                        for (tbl.foreign_keys, 0..) |old_fk, i| new_fks[i] = old_fk;
                        self.alloc.free(tbl.foreign_keys);
                        new_fks[new_len - 1] = fk;
                        tbl.foreign_keys = new_fks;
                        break;
                    }
                }
            } else if (self.peek() != ';') {
                // ALTER TABLE t ADD col type [modifiers] — a real column
                // definition; parse it like CREATE TABLE columns so
                // reverse engineering keeps the field.
                const saved_pos = self.pos;
                if (parseAddedColumn(self)) |col| {
                    for (tables) |*tbl| {
                        if (std.mem.eql(u8, tbl.name, tbl_name)) {
                            const new_len = tbl.columns.len + 1;
                            var new_cols = try self.alloc.alloc(common.SqlColumn, new_len);
                            for (tbl.columns, 0..) |old_c, i| new_cols[i] = old_c;
                            self.alloc.free(tbl.columns);
                            new_cols[new_len - 1] = col;
                            tbl.columns = new_cols;
                            break;
                        }
                    }
                } else |_| {
                    self.pos = saved_pos;
                    self.skipToSemicolon();
                }
            }
        } else {
            // ALTER TABLE ... (non-ADD) — skip
            self.skipToSemicolon();
        }
    } else {
        self.skipToSemicolon();
    }
}

/// Parse one added column definition (`extra VARCHAR(10) NOT NULL DEFAULT 'x'`)
/// using the same column parser as CREATE TABLE. Returns error when the text
/// does not start with an identifier (e.g. `ADD INDEX`/`ADD PRIMARY KEY`),
/// leaving position untouched for the caller's fallback.
fn parseAddedColumn(self: *sp.SqlParser) !common.SqlColumn {
    self.skipSpacesAndNewlines();
    const first = self.peekWord();
    if (first.len == 0) return error.NotAColumn;
    return create_parser.parseColumn(self);
}
