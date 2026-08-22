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
    const tables = try parseTableBlocks(alloc, source);
    if (tables.len < 2) return source;

    // Build field entries per table
    var all_fields = try std.ArrayList([]const FieldEntry).initCapacity(alloc, tables.len);
    for (tables) |tbl| {
        var fields = try std.ArrayList(FieldEntry).initCapacity(alloc, tbl.field_lines.len);
        for (tbl.field_lines) |line| {
            try fields.append(alloc, .{ .name = fieldName(line), .line = line });
        }
        try all_fields.append(alloc, try fields.toOwnedSlice(alloc));
    }

    // Find the most valuable field set (fields co-occurring in most tables)
    const best = (findBestFieldSet(alloc, all_fields.items) catch return source) orelse return source;

    // Generate output
    var output = try std.ArrayList(u8).initCapacity(alloc, source.len + 256);

    // Write template
    try output.appendSlice(alloc, "% base\n");
    for (best.fields) |fe| {
        try output.appendSlice(alloc, fe.line);
        try output.append(alloc, '\n');
    }
    try output.append(alloc, '\n');

    // Write tables
    for (tables, 0..) |tbl, ti| {
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
            try output.appendSlice(alloc, tbl.name);
            try output.append(alloc, '\n');
            for (tbl.field_lines) |line| {
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
            for (tbl.field_lines) |line| {
                try output.appendSlice(alloc, line);
                try output.append(alloc, '\n');
            }
        }
        try output.append(alloc, '\n');
    }

    return try output.toOwnedSlice(alloc);
}

// ─── Parsing ─────────────────────────────────────────────────

fn parseTableBlocks(alloc: std.mem.Allocator, source: []const u8) ![]TableBlock {
    var blocks = try std.ArrayList(TableBlock).initCapacity(alloc, 32);
    var lines = std.mem.splitScalar(u8, source, '\n');
    var current_fields = try std.ArrayList([]const u8).initCapacity(alloc, 16);
    var current_name: []const u8 = "";
    var current_header: []const u8 = "";
    var has_table = false;

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        if (line.len > 0 and line[0] == '#') {
            if (has_table) {
                try blocks.append(alloc, .{
                    .name = current_name,
                    .header_line = current_header,
                    .field_lines = try current_fields.toOwnedSlice(alloc),
                });
                current_fields = try std.ArrayList([]const u8).initCapacity(alloc, 16);
            }
            current_name = tableName(line);
            current_header = line;
            has_table = true;
        } else if (has_table and line.len > 0 and line[0] != ';' and line[0] != '%' and line[0] != '@' and line[0] != '$'
            // Brace syntax: `{`/`}` delimit the table body — structural, not fields.
            // (tableName() strips a trailing `{` from the header separately.)
        and line[0] != '{' and !std.mem.eql(u8, std.mem.trim(u8, line, " \t"), "}")) {
            try current_fields.append(alloc, line);
        }
    }
    if (has_table) {
        try blocks.append(alloc, .{
            .name = current_name,
            .header_line = current_header,
            .field_lines = try current_fields.toOwnedSlice(alloc),
        });
    }
    return try blocks.toOwnedSlice(alloc);
}

fn tableName(header: []const u8) []const u8 {
    var rest = if (header.len > 1 and header[1] == ' ') header[2..] else header[1..];
    // Brace syntax: "# users {" → "users"
    rest = std.mem.trim(u8, rest, " \t");
    if (rest.len > 0 and rest[rest.len - 1] == '{') {
        rest = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
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
    return parts.next() orelse line;
}

// ─── Field Set Finding ───────────────────────────────────────

fn findBestFieldSet(alloc: std.mem.Allocator, all_fields: []const []const FieldEntry) !?Template {
    const table_count = all_fields.len;
    if (table_count < MIN_SHARED_TABLES) return null;

    // Step 1: Count how many tables each field name appears in
    var field_freq = std.StringHashMap(usize).init(alloc);
    defer field_freq.deinit();

    for (all_fields) |fields| {
        for (fields) |fe| {
            const gop = try field_freq.getOrPut(fe.name);
            if (!gop.found_existing) gop.value_ptr.* = 1 else gop.value_ptr.* += 1;
        }
    }

    // Step 2: Find the most frequent fields (appear in >= 2 tables)
    var frequent_fields = try std.ArrayList([]const u8).initCapacity(alloc, 32);
    var iter = field_freq.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* >= MIN_SHARED_TABLES) {
            try frequent_fields.append(alloc, entry.key_ptr.*);
        }
    }

    if (frequent_fields.items.len < MIN_TEMPLATE_FIELDS) return null;

    // Step 3: Find the largest set of frequent fields that co-occur in the most tables
    var best_fields: ?[]const []const u8 = null;
    var best_table_count: usize = 0;
    var best_field_count: usize = 0;

    for (frequent_fields.items) |seed| {
        var candidate = try std.ArrayList([]const u8).initCapacity(alloc, 16);
        try candidate.append(alloc, seed);

        // Find tables that have the seed
        var seed_tables = try std.ArrayList(usize).initCapacity(alloc, table_count);
        for (all_fields, 0..) |fields, ti| {
            for (fields) |fe| {
                if (std.mem.eql(u8, fe.name, seed)) {
                    try seed_tables.append(alloc, ti);
                    break;
                }
            }
        }

        // Try to add more fields that appear in ALL seed_tables
        for (frequent_fields.items) |candidate_field| {
            if (std.mem.eql(u8, candidate_field, seed)) continue;
            var in_all = true;
            for (seed_tables.items) |ti| {
                var found = false;
                for (all_fields[ti]) |fe| {
                    if (std.mem.eql(u8, fe.name, candidate_field)) {
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
                try candidate.append(alloc, candidate_field);
            }
        }

        // Score: tables_with_all_fields * field_count
        const t_count = seed_tables.items.len;
        const f_count = candidate.items.len;
        if (f_count >= MIN_TEMPLATE_FIELDS and t_count >= MIN_SHARED_TABLES) {
            if (t_count * f_count > best_table_count * best_field_count or
                (t_count * f_count == best_table_count * best_field_count and f_count > best_field_count))
            {
                best_table_count = t_count;
                best_field_count = f_count;
                best_fields = try candidate.toOwnedSlice(alloc);
            }
        }
        candidate.deinit(alloc);
        seed_tables.deinit(alloc);
    }

    frequent_fields.deinit(alloc);

    if (best_fields) |fields| {
        // Build FieldEntry list from the field names
        var template_fields = try std.ArrayList(FieldEntry).initCapacity(alloc, fields.len);
        for (fields) |fname| {
            // Find the line text from the first table that has this field
            for (all_fields) |tfields| {
                for (tfields) |fe| {
                    if (std.mem.eql(u8, fe.name, fname)) {
                        try template_fields.append(alloc, fe);
                        break;
                    }
                }
                // Check if we already added this field
                if (template_fields.items.len > 0 and
                    std.mem.eql(u8, template_fields.items[template_fields.items.len - 1].name, fname))
                {
                    break;
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
