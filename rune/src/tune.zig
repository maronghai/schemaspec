const std = @import("std");
const io_mod = @import("io.zig");

// ─── Tune: Auto-Template Extraction ──────────────────────────
// Finds fields that co-occur in many tables and extracts them
// into a template definition.

const MIN_TEMPLATE_FIELDS = 2;
const MIN_SHARED_TABLES = 2;

const TableBlock = struct {
    name: []const u8,
    header_line: []const u8,
    field_lines: []const []const u8,
    body_lines: []const []const u8,
};

const FieldEntry = struct {
    name: []const u8,
    line: []const u8,
};

const Template = struct {
    name: []const u8,
    fields: []const FieldEntry,
};

// ─── Public API ──────────────────────────────────────────────

pub fn handleTune(io: std.Io, alloc: std.mem.Allocator, source: []const u8, dry_run: bool) !void {
    const result = try tune(alloc, source);
    if (dry_run) {
        // Dry run: preview the result to stdout without modifying the file
        try io_mod.writeOutput(io, result, null, false);
    } else {
        // Normal mode: write the result to stdout (file write handled by caller)
        try io_mod.writeOutput(io, result, null, false);
    }
}

pub fn tune(alloc: std.mem.Allocator, source: []const u8) ![]const u8 {
    const parsed = try parseSource(alloc, source);

    // Nothing to extract from — return the original untouched.
    if (parsed.tables.len < 2) return source;

    // Build field entries per table (only field/index/FK/comment body lines).
    var all_fields = try std.ArrayList([]const FieldEntry).initCapacity(alloc, parsed.tables.len);
    for (parsed.tables) |tbl| {
        var fields = try std.ArrayList(FieldEntry).initCapacity(alloc, tbl.field_lines.len);
        for (tbl.field_lines) |line| {
            const fn_ = fieldName(line);
            if (fn_.len == 0) continue;
            // Engine headers and other non-field lines must never enter the
            // template or be compared as fields.
            if (!isFieldLine(line)) continue;
            try fields.append(alloc, .{ .name = fn_, .line = line });
        }
        try all_fields.append(alloc, try fields.toOwnedSlice(alloc));
    }

    // Find the most valuable field set (fields co-occurring in most tables).
    const best = (findBestFieldSet(alloc, all_fields.items) catch return source) orelse return source;

    // Generate output: preamble verbatim, then template, then tables.
    var output = try std.ArrayList(u8).initCapacity(alloc, source.len + 256);
    for (parsed.preamble_lines) |pl| {
        try output.appendSlice(alloc, pl);
        try output.append(alloc, '\n');
    }
    if (parsed.preamble_lines.len > 0) try output.append(alloc, '\n');

    try output.appendSlice(alloc, "% base\n");
    for (best.fields) |fe| {
        try output.appendSlice(alloc, fe.line);
        try output.append(alloc, '\n');
    }
    try output.append(alloc, '\n');

    for (parsed.tables, 0..) |tbl, ti| {
        const fields = all_fields.items[ti];
        var has_all = true;
        for (best.fields) |tfe| {
            var found = false;
            for (fields) |fe| {
                if (std.mem.eql(u8, fe.name, tfe.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                has_all = false;
                break;
            }
        }

        if (has_all) {
            try output.appendSlice(alloc, "#base ");
            for (tbl.name) |nc| {
                try output.append(alloc, nc);
            }
            try output.append(alloc, '\n');
            for (tbl.body_lines) |line| {
                const fn_ = fieldName(line);
                var in_tmpl = false;
                for (best.fields) |tfe| {
                    if (std.mem.eql(u8, fn_, tfe.name)) {
                        in_tmpl = true;
                        break;
                    }
                }
                if (!in_tmpl) {
                    try output.appendSlice(alloc, line);
                    try output.append(alloc, '\n');
                }
            }
        } else {
            try output.appendSlice(alloc, tbl.header_line);
            try output.append(alloc, '\n');
            for (tbl.body_lines) |line| {
                try output.appendSlice(alloc, line);
                try output.append(alloc, '\n');
            }
        }
        try output.append(alloc, '\n');
    }

    return try output.toOwnedSlice(alloc);
}

/// A line inside a table body counts as a field candidate only when it is an
/// actual declaration. Index/FK/comment/`!`-PK lines participate in extraction
/// (they move with their field into the template), but engine headers and
/// brace tokens do not.
fn isFieldLine(line: []const u8) bool {
    const t = std.mem.trimStart(u8, line, " \t");
    if (t.len == 0) return false;
    if (t[0] == '^') return false; // engine header — never a field
    if (t[0] == '{' or t[0] == '}') return false;
    return true;
}

// ─── Parsing ─────────────────────────────────────────────────

const ParsedSource = struct {
    preamble_lines: []const []const u8,
    tables: []TableBlock,
};

/// Parse source into (preamble, table blocks). Everything before the first
/// `#` table header is preamble ($ schema, @version, ~ typedefs, blank lines)
/// and is emitted verbatim before the extracted template.
fn parseSource(alloc: std.mem.Allocator, source: []const u8) !ParsedSource {
    var preamble = try std.ArrayList([]const u8).initCapacity(alloc, 16);
    var blocks = try std.ArrayList(TableBlock).initCapacity(alloc, 32);
    var lines = std.mem.splitScalar(u8, source, '\n');
    var current_body = try std.ArrayList([]const u8).initCapacity(alloc, 16);
    var current_name: []const u8 = "";
    var current_header: []const u8 = "";
    var has_table = false;

    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len > 0 and line[0] == '#') {
            if (has_table) {
                try blocks.append(alloc, .{
                    .name = current_name,
                    .header_line = current_header,
                    .field_lines = current_body.items,
                    .body_lines = current_body.items,
                });
                current_body = try std.ArrayList([]const u8).initCapacity(alloc, 16);
            }
            current_name = tableName(line);
            current_header = line;
            has_table = true;
        } else if (has_table) {
            // Table body: everything except structural braces. `@` index/FK
            // lines and comments belong to their preceding field and move
            // with it during extraction.
            const t = std.mem.trim(u8, line, " \t");
            if (!(t.len > 0 and t[0] == '}')) {
                try current_body.append(alloc, line);
            }
        } else {
            try preamble.append(alloc, line);
        }
    }
    if (has_table) {
        try blocks.append(alloc, .{
            .name = current_name,
            .header_line = current_header,
            .field_lines = current_body.items,
            .body_lines = current_body.items,
        });
    }
    return .{
        .preamble_lines = try preamble.toOwnedSlice(alloc),
        .tables = try blocks.toOwnedSlice(alloc),
    };
}

fn tableName(header: []const u8) []const u8 {
    var rest = if (header.len > 1 and header[1] == ' ') header[2..] else header[1..];
    // Brace syntax: "# users {" → "users"
    rest = std.mem.trim(u8, rest, " \t");
    if (rest.len > 0 and rest[rest.len - 1] == '{') {
        rest = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    }
    // Backtick-quoted names stay quoted so spaces survive re-parsing.
    if (rest.len > 0 and rest[0] == '`') {
        if (std.mem.indexOfScalarPos(u8, rest, 1, '`')) |close| {
            return rest[0 .. close + 1];
        }
    }
    // "# user" → "user"
    // "# base user" → "user" (first word is template, second is table)
    // "# user > base" → "user" (before >)
    if (std.mem.indexOf(u8, rest, " >")) |pos| {
        return std.mem.trim(u8, rest[0..pos], " ");
    }
    // Check if first word could be a template name (2+ words)
    var parts = std.mem.splitScalar(u8, rest, ' ');
    const first = parts.next() orelse return rest;
    const second = parts.next() orelse return first;
    // If there's a second word, check if it looks like a table name (not a comment)
    if (second.len > 0 and second[0] != ':') {
        return second; // "# base user" → "user"
    }
    return first; // "# user : comment" → "user"
}

fn fieldName(line: []const u8) []const u8 {
    var parts = std.mem.splitScalar(u8, std.mem.trim(u8, line, " \t"), ' ');
    var tok = parts.next() orelse return line;
    // Strip leading indentation artifacts.
    while (tok.len > 0 and (tok[0] == '\t')) tok = tok[1..];
    return tok;
}

// ─── Field Set Finding ───────────────────────────────────────

fn findBestFieldSet(alloc: std.mem.Allocator, all_fields: []const []const FieldEntry) !?Template {
    const table_count = all_fields.len;
    if (table_count < MIN_SHARED_TABLES) return null;

    // Step 1: Count how many tables each field appears in, keyed by full line
    // text — not just the field name. Two tables sharing a NAME but with
    // different definitions (`status n` vs `status s32`) would silently pick
    // one variant and rewrite the other's semantics; requiring identical text
    // keeps extraction semantics-preserving.
    var line_freq = std.StringHashMap(usize).init(alloc);
    defer line_freq.deinit();

    for (all_fields) |fields| {
        var seen_in_table = std.StringHashMap(void).init(alloc);
        defer seen_in_table.deinit();
        for (fields) |fe| {
            if (seen_in_table.contains(fe.line)) continue;
            try seen_in_table.put(fe.line, {});
            const gop = try line_freq.getOrPut(fe.line);
            if (!gop.found_existing) gop.value_ptr.* = 1 else gop.value_ptr.* += 1;
        }
    }

    // Step 2: Collect frequent identical lines, ordered by first appearance
    // (deterministic column order — hash iteration order would shuffle the
    // template's field list between runs on the same input).
    var frequent_lines = try std.ArrayList([]const u8).initCapacity(alloc, 32);
    {
        var emitted = std.StringHashMap(void).init(alloc);
        defer emitted.deinit();
        for (all_fields) |fields| {
            for (fields) |fe| {
                const freq = line_freq.get(fe.line) orelse 0;
                if (freq < MIN_SHARED_TABLES) continue;
                if (emitted.contains(fe.line)) continue;
                try emitted.put(fe.line, {});
                try frequent_lines.append(alloc, fe.line);
            }
        }
    }

    if (frequent_lines.items.len < MIN_TEMPLATE_FIELDS) return null;

    // Step 3: Grow candidates seed-first, keeping only lines that co-occur in
    // ALL of the seed's tables. Score = tables × fields.
    var best_lines: ?[]const []const u8 = null;
    var best_table_count: usize = 0;
    var best_field_count: usize = 0;

    for (frequent_lines.items) |seed| {
        var candidate = try std.ArrayList([]const u8).initCapacity(alloc, 16);
        try candidate.append(alloc, seed);

        var seed_tables = try std.ArrayList(usize).initCapacity(alloc, table_count);
        for (all_fields, 0..) |fields, ti| {
            for (fields) |fe| {
                if (std.mem.eql(u8, fe.line, seed)) {
                    try seed_tables.append(alloc, ti);
                    break;
                }
            }
        }

        for (frequent_lines.items) |candidate_line| {
            if (std.mem.eql(u8, candidate_line, seed)) continue;
            var in_all = true;
            for (seed_tables.items) |ti| {
                var found = false;
                for (all_fields[ti]) |fe| {
                    if (std.mem.eql(u8, fe.line, candidate_line)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    in_all = false;
                    break;
                }
            }
            if (in_all) {
                try candidate.append(alloc, candidate_line);
            }
        }

        const t_count = seed_tables.items.len;
        const f_count = candidate.items.len;
        if (f_count >= MIN_TEMPLATE_FIELDS and t_count >= MIN_SHARED_TABLES) {
            if (t_count * f_count > best_table_count * best_field_count or
                (t_count * f_count == best_table_count * best_field_count and f_count > best_field_count))
            {
                best_table_count = t_count;
                best_field_count = f_count;
                best_lines = try candidate.toOwnedSlice(alloc);
            }
        }
        candidate.deinit(alloc);
        seed_tables.deinit(alloc);
    }

    frequent_lines.deinit(alloc);

    if (best_lines) |lines_| {
        // Template field order follows first appearance in the source scan
        // above (frequent_lines order preserved by candidate construction).
        var template_fields = try std.ArrayList(FieldEntry).initCapacity(alloc, lines_.len);
        for (lines_) |ln| {
            outer: for (all_fields) |tfields| {
                for (tfields) |fe| {
                    if (std.mem.eql(u8, fe.line, ln)) {
                        try template_fields.append(alloc, fe);
                        break :outer;
                    }
                }
            }
        }
        return .{
            .name = "base",
            .fields = try template_fields.toOwnedSlice(alloc),
        };
    }

    return null;
}

// ─── Tests ──────────────────────────────────────────────────

test "tune extracts common fields into template" {
    const source =
        \\# user
        \\id p
        \\name s
        \\email s
        \\
        \\# post
        \\id p
        \\name s
        \\email s
        \\title s
        \\
    ;
    // tune uses page_allocator internally, so we use it for tests too
    const result = try tune(std.heap.page_allocator, source);
    // Should contain template definition
    try std.testing.expect(std.mem.indexOf(u8, result, "% base") != null);
    // Should contain #base references
    try std.testing.expect(std.mem.indexOf(u8, result, "#base user") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "#base post") != null);
}

test "tune returns original when too few tables" {
    const source =
        \\# user
        \\id p
        \\name s
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    // When no extraction happens, tune returns the original source pointer
    try std.testing.expectEqual(source.ptr, result.ptr);
}

test "tune returns original when no common fields" {
    const source =
        \\# user
        \\id p
        \\name s
        \\
        \\# post
        \\title s
        \\body S
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    // When no extraction happens, tune returns the original source pointer
    try std.testing.expectEqual(source.ptr, result.ptr);
}

test "fieldName extracts first token" {
    try std.testing.expectEqualStrings("id", fieldName("id p"));
    try std.testing.expectEqualStrings("name", fieldName("  name s"));
    try std.testing.expectEqualStrings("email", fieldName("email s128"));
}

test "tableName extracts table name from header" {
    try std.testing.expectEqualStrings("user", tableName("# user"));
    try std.testing.expectEqualStrings("user", tableName("# user : A user table"));
    try std.testing.expectEqualStrings("user", tableName("# base user"));
}

// ─── v0.329.0: brace syntax ─────────────────────────────────

test "tune brace syntax: closing brace is not a field" {
    const source =
        \\# user {
        \\id p
        \\name s
        \\}
        \\
        \\# post {
        \\id p
        \\name s
        \\title s
        \\}
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    // The template must contain only real fields, never a bare `}` line.
    try std.testing.expect(std.mem.indexOf(u8, result, "% base") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "\n}\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "}") == null);
}

test "tune brace syntax: table names lose the trailing brace" {
    try std.testing.expectEqualStrings("user", tableName("# user {"));
    try std.testing.expectEqualStrings("user", tableName("#user{"));
}

test "tune brace syntax: extraction matches brace-less behavior" {
    const source =
        \\# users {
        \\id n++ PK
        \\created_at t+
        \\}
        \\
        \\# posts {
        \\id n++ PK
        \\created_at t+
        \\title s
        \\}
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    try std.testing.expect(std.mem.indexOf(u8, result, "% base") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "id n++ PK") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "created_at t+") != null);
    // Table references carry the brace-stripped name.
    try std.testing.expect(std.mem.indexOf(u8, result, "#base users") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "#base posts") != null);
}

// ─── v0.336.0: preamble preservation + semantic safety ──────

test "tune preserves schema/version/typedef preamble" {
    const source =
        \\$ shopdb
        \\@version 1.0.0
        \\~ uuid s36
        \\
        \\# alpha
        \\row_uuid uuid
        \\id n++
        \\
        \\# beta
        \\row_uuid uuid
        \\id n++
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    try std.testing.expect(std.mem.startsWith(u8, result, "$ shopdb\n"));
    try std.testing.expect(std.mem.indexOf(u8, result, "@version 1.0.0") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "~ uuid s36") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "% base") != null);
}

test "tune does not extract when same-named fields differ in definition" {
    const source =
        \\# a
        \\status n
        \\id n++
        \\
        \\# b
        \\status s32
        \\id n++
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    // status differs (n vs s32) — extracting it would rewrite b's type.
    try std.testing.expectEqual(source.ptr, result.ptr);
}

test "tune drops indexes from member tables but moves them via identical lines" {
    const source =
        \\# a
        \\email s64
        \\id n++
        \\@ email
        \\
        \\# b
        \\email s64
        \\id n++
        \\@ email
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    // The @ email line is part of both bodies identically → it lands in the
    // template instead of being deleted.
    try std.testing.expect(std.mem.indexOf(u8, result, "@ email") != null);
}

test "tune engine headers are never template fields" {
    const source =
        \\# a
        \\id n++
        \\^MEMORY
        \\
        \\# b
        \\id n++
        \\^InnoDB
        \\
    ;
    const result = try tune(std.heap.page_allocator, source);
    try std.testing.expect(std.mem.indexOf(u8, result, "^MEMORY") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "^InnoDB") != null);
}

test "tune backtick table name survives reference emission" {
    try std.testing.expectEqualStrings("`order details`", tableName("# `order details`"));
}
