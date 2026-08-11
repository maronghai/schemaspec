const std = @import("std");

// ─── SS Formatter ─────────────────────────────────────────────
// Auto-formats .ss files with consistent style:
//   - Strip trailing whitespace
//   - 2-space indentation for fields inside tables/templates
//   - Single blank line between blocks
//   - No trailing blank lines
//   - @if/@endif at root level (not indented)
//   - + doc directives indented at field level
//   - SQL keywords uppercased inside @if/@endif conditional blocks

/// Pre-allocation padding to avoid repeated reallocations for small inputs.
const INITIAL_PADDING = 64;

// ─── SQL Keyword Uppercasing ──────────────────────────────────
// SQL keywords that should be uppercased for consistent style.
// Applied to content inside @if/@endif conditional blocks.
// Note: type keywords (int, text, varchar, etc.) are excluded because
// they are also Rune type symbols used in field definitions.
const SQL_KEYWORDS = [_][]const u8{
    // DDL
    "CREATE", "TABLE", "INDEX", "VIEW", "DROP", "ALTER",
    // DML
    "SELECT", "INSERT", "UPDATE", "DELETE", "FROM", "WHERE",
    // Logical
    "AND", "OR", "NOT", "IN", "ON", "AS", "IS",
    // Constraints
    "PRIMARY", "KEY", "UNIQUE", "CHECK", "CONSTRAINT",
    "REFERENCES", "FOREIGN",
    // Modifiers
    "NULL", "DEFAULT", "AUTO_INCREMENT", "UNSIGNED",
    // Control
    "IF", "EXISTS", "SET", "CASCADE", "RESTRICT",
    // Metadata
    "COMMENT", "ENGINE", "CHARSET", "COLLATE",
    // Alter
    "ADD", "COLUMN", "MODIFY", "RENAME", "TO",
    // Pagination
    "RETURNING", "VALUES", "INTO", "OVER", "PARTITION",
    "ROW", "ROWS", "ONLY", "FIRST", "LAST",
    // Transactions
    "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION",
    // Privileges
    "GRANT", "REVOKE", "ALL", "PRIVILEGES",
    // Literals
    "TRUE", "FALSE",
};

/// Check if a byte is a valid identifier character (letter, digit, or underscore).
fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_';
}

/// Check if a word matches any SQL keyword (case-insensitive).
fn isSqlKeyword(word: []const u8) bool {
    for (SQL_KEYWORDS) |kw| {
        if (word.len == kw.len and std.ascii.eqlIgnoreCase(word, kw)) {
            return true;
        }
    }
    return false;
}

/// Write SQL keywords uppercased directly to the output buffer.
/// Preserves non-keyword identifiers and string literals.
fn writeUppercasedSqlKeywords(result: *std.ArrayList(u8), alloc: std.mem.Allocator, line: []const u8) !void {
    var i: usize = 0;
    while (i < line.len) {
        const c = line[i];
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_') {
            // Start of a potential identifier/keyword
            const start = i;
            while (i < line.len and isIdentChar(line[i])) i += 1;
            const word = line[start..i];
            if (isSqlKeyword(word)) {
                // Uppercase the keyword
                for (word) |wc| {
                    try result.append(alloc, std.ascii.toUpper(wc));
                }
            } else {
                try result.appendSlice(alloc, word);
            }
        } else if (c == '\'') {
            // String literal — preserve as-is
            try result.append(alloc, c);
            i += 1;
            while (i < line.len and line[i] != '\'') {
                try result.append(alloc, line[i]);
                i += 1;
            }
            if (i < line.len) {
                try result.append(alloc, line[i]);
                i += 1;
            }
        } else if (c == '`' or c == '"') {
            // Quoted identifier — preserve as-is
            try result.append(alloc, c);
            i += 1;
            while (i < line.len and line[i] != c) {
                try result.append(alloc, line[i]);
                i += 1;
            }
            if (i < line.len) {
                try result.append(alloc, line[i]);
                i += 1;
            }
        } else {
            try result.append(alloc, c);
            i += 1;
        }
    }
}

pub fn format(alloc: std.mem.Allocator, input: []const u8) ![]const u8 {
    var result = try std.ArrayList(u8).initCapacity(alloc, input.len + INITIAL_PADDING);
    var lines = std.mem.splitScalar(u8, input, '\n');
    var in_block = false; // inside a table or template
    var in_if_block = false; // inside @if/@endif conditional block
    var prev_blank = false;
    var first_line = true;

    while (lines.next()) |raw_line| {
        // Strip trailing whitespace
        const line = std.mem.trim(u8, raw_line, " \t\r");

        if (line.len == 0) {
            // Blank line: collapse consecutive blanks, skip at start
            if (!first_line and !prev_blank) {
                prev_blank = true;
                // Don't emit yet — wait for next non-blank to decide
            }
            continue;
        }

        // Non-blank line
        first_line = false;

        // Emit deferred blank line
        if (prev_blank) {
            try result.append(alloc, '\n');
            prev_blank = false;
        }

        const first_char = line[0];

        // Detect block boundaries and special constructs
        if (first_char == '#' or first_char == '~') {
            // Table or template header — end any previous block, start new block
            in_block = true;
            in_if_block = false;
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else if (first_char == '$' or first_char == '!') {
            // Schema declaration or end marker — end block
            in_block = false;
            in_if_block = false;
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else if ((line.len >= 3 and std.mem.startsWith(u8, line, "@if") and (line.len == 3 or line[3] == '(')) or std.mem.eql(u8, line, "@endif")) {
            // @if(...) / @endif — conditional block control flow, always at root level
            if (std.mem.startsWith(u8, line, "@if")) {
                in_if_block = true;
            } else {
                in_if_block = false;
            }
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else if (first_char == ';' or first_char == '@' or first_char == '(' or first_char == ')') {
            // Comment, index, or inline index — inside block, indented
            if (in_block) {
                try result.appendSlice(alloc, "  ");
            }
            if (in_if_block) {
                try writeUppercasedSqlKeywords(&result, alloc, line);
            } else {
                try result.appendSlice(alloc, line);
            }
            try result.append(alloc, '\n');
        } else if (first_char == '+' and line.len >= 2) {
            // Doc directive (+ ...) — indented at field level inside blocks
            if (in_block) {
                try result.appendSlice(alloc, "  ");
            }
            try result.appendSlice(alloc, line);
            try result.append(alloc, '\n');
        } else {
            // Field definition — indented inside block
            if (in_block) {
                try result.appendSlice(alloc, "  ");
            }
            if (in_if_block) {
                try writeUppercasedSqlKeywords(&result, alloc, line);
            } else {
                try result.appendSlice(alloc, line);
            }
            try result.append(alloc, '\n');
        }
    }

    // Trim trailing blank lines
    while (result.items.len > 0 and result.items[result.items.len - 1] == '\n') {
        result.items.len -= 1;
    }
    try result.append(alloc, '\n');

    return try result.toOwnedSlice(alloc);
}

// ─── Tests ──────────────────────────────────────────────────

test "basic table formatting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\nname s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n  name s\n", result);
}

test "strips trailing whitespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n  id n pk   \n  name s  \n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n  name s\n", result);
}

test "collapses consecutive blank lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n  id n pk\n\n\n  name s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n  name s\n", result);
}

test "no blank line at start" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "\n\n# users\n  id n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n", result);
}

test "trim trailing blank lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n  id n pk\n\n\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n", result);
}

test "@if block not indented" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n\n@if(dialect=pg)\nbio T\n@endif\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n@if(dialect=pg)\n  bio T\n@endif\n", result);
}

test "@endif not indented" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n@if(dialect=pg)\n  bio T\n@endif\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n@if(dialect=pg)\n  bio T\n@endif\n", result);
}

test "doc directive indented inside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n+ User table\nid n pk\nname s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  + User table\n  id n pk\n  name s\n", result);
}

test "doc directive not indented outside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "+ Schema documentation\n$ mydb\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("+ Schema documentation\n$ mydb\n", result);
}

test "template parent syntax formatted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "~ base\nid n pk\ncreated_at d\n\n# users +base\nname s\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("~ base\n  id n pk\n  created_at d\n\n# users +base\n  name s\n", result);
}

test "schema declaration ends block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "$ mydb\n# users\nid n pk\n# posts\nid n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("$ mydb\n# users\n  id n pk\n# posts\n  id n pk\n", result);
}

test "comments not indented outside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "; This is a comment\n$ mydb\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("; This is a comment\n$ mydb\n", result);
}

test "comments indented inside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\n; Comment inside table\nid n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  ; Comment inside table\n  id n pk\n", result);
}

test "index indented inside block" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n@email_idx (email)\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n  @email_idx (email)\n", result);
}

test "multiple tables with blank line separation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n\n# posts\nid n pk\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n# posts\n  id n pk\n", result);
}

// ─── SQL Keyword Formatting Tests ──────────────────────────────

test "isSqlKeyword: positive matches" {
    try std.testing.expect(isSqlKeyword("CREATE"));
    try std.testing.expect(isSqlKeyword("create"));
    try std.testing.expect(isSqlKeyword("Create"));
    try std.testing.expect(isSqlKeyword("TABLE"));
    try std.testing.expect(isSqlKeyword("SELECT"));
    try std.testing.expect(isSqlKeyword("PRIMARY"));
    try std.testing.expect(isSqlKeyword("NOT"));
    try std.testing.expect(isSqlKeyword("NULL"));
    try std.testing.expect(isSqlKeyword("DEFAULT"));
    try std.testing.expect(isSqlKeyword("AUTO_INCREMENT"));
}

test "isSqlKeyword: negative matches" {
    try std.testing.expect(!isSqlKeyword("users"));
    try std.testing.expect(!isSqlKeyword("id"));
    try std.testing.expect(!isSqlKeyword("name"));
    try std.testing.expect(!isSqlKeyword(""));
    try std.testing.expect(!isSqlKeyword("pk"));
    try std.testing.expect(!isSqlKeyword("s"));
    try std.testing.expect(!isSqlKeyword("n"));
}

test "isSqlKeyword: boundary cases" {
    // Not a keyword: too short or partial match
    try std.testing.expect(!isSqlKeyword("C"));
    try std.testing.expect(!isSqlKeyword("CREAT"));
    try std.testing.expect(!isSqlKeyword("CREATEX"));
}

test "uppercaseSqlKeywords: basic keywords" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var result = try std.ArrayList(u8).initCapacity(alloc, 64);

    try writeUppercasedSqlKeywords(&result, alloc, "create table users");
    try std.testing.expectEqualStrings("CREATE TABLE users", result.items);
}

test "uppercaseSqlKeywords: preserves identifiers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var result = try std.ArrayList(u8).initCapacity(alloc, 64);

    try writeUppercasedSqlKeywords(&result, alloc, "select id, name from users where id = 1");
    try std.testing.expectEqualStrings("SELECT id, name FROM users WHERE id = 1", result.items);
}

test "uppercaseSqlKeywords: preserves string literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var result = try std.ArrayList(u8).initCapacity(alloc, 64);

    try writeUppercasedSqlKeywords(&result, alloc, "comment 'create table test'");
    try std.testing.expectEqualStrings("COMMENT 'create table test'", result.items);
}

test "uppercaseSqlKeywords: mixed keywords and identifiers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var result = try std.ArrayList(u8).initCapacity(alloc, 64);

    try writeUppercasedSqlKeywords(&result, alloc, "primary key (id), not null");
    try std.testing.expectEqualStrings("PRIMARY KEY (id), NOT NULL", result.items);
}

test "uppercaseSqlKeywords: empty string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var result = try std.ArrayList(u8).initCapacity(alloc, 64);

    try writeUppercasedSqlKeywords(&result, alloc, "");
    try std.testing.expectEqualStrings("", result.items);
}

test "uppercaseSqlKeywords: SQL data types (excluded to preserve Rune types)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var result = try std.ArrayList(u8).initCapacity(alloc, 64);

    // Type keywords like int, varchar, text are NOT uppercased because they
    // are also Rune type symbols. Only DDL/DML/constraint keywords are uppercased.
    try writeUppercasedSqlKeywords(&result, alloc, "create table t (id int, name varchar(255))");
    try std.testing.expectEqualStrings("CREATE TABLE t (id int, name varchar(255))", result.items);
}

test "uppercaseSqlKeywords: DDL statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var result = try std.ArrayList(u8).initCapacity(alloc, 64);

    // Type keywords (int) are not uppercased; DDL keywords (DROP, TABLE, IF, EXISTS) are
    try writeUppercasedSqlKeywords(&result, alloc, "drop table if exists users");
    try std.testing.expectEqualStrings("DROP TABLE IF EXISTS users", result.items);
}

test "@if block: SQL keywords uppercased" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n\n@if(dialect=pg)\nbio text\ncreate index idx_bio on users(bio)\n@endif\n";
    const result = try format(alloc, input);
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n@if(dialect=pg)\n  bio text\n  CREATE INDEX idx_bio ON users(bio)\n@endif\n", result);
}

test "@if block: mixed Rune and SQL" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const input = "# users\nid n pk\n\n@if(dialect=pg)\nserial_id n\ncreate table log (id int primary key)\n@endif\n";
    const result = try format(alloc, input);
    // 'serial_id' is not a SQL keyword, 'n' is not a SQL keyword
    // 'create', 'table', 'primary', 'key' are SQL keywords; 'int' is not (Rune type)
    try std.testing.expectEqualStrings("# users\n  id n pk\n\n@if(dialect=pg)\n  serial_id n\n  CREATE TABLE log (id int PRIMARY KEY)\n@endif\n", result);
}
