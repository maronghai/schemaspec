const std = @import("std");
const testing = std.testing;
const lint_mod = @import("../lint.zig");
const lintSchema = lint_mod.lintSchema;
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../types/resolved_ast.zig").ResolvedTable;
const ast_mod = @import("../types/ast.zig");
const th = @import("test_helpers.zig");

// ─── Clean Schema ──────────────────────────────────────────────

test "lint: clean schema passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("name", .{ .simple = "s" }, &.{}, null),
        th.makeField("created_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    table.comment = "User accounts";
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    // Disable column-length rule since test fields use bare 's' type
    // Disable column-default-required since test fields have no defaults
    // Disable table-no-index since test tables have no explicit indexes
    // Disable column-no-comment since test fields don't have documentation
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_length, false);
    cfg.rules.setEnabled(.column_default_required, false);
    cfg.rules.setEnabled(.table_no_index, false);
    cfg.rules.setEnabled(.column_no_comment, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    try testing.expectEqual(@as(usize, 0), results.items.len);
}

// ─── No PK Tests ──────────────────────────────────────────────

test "lint: no PK detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "logs", &.{
        th.makeField("msg", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) found = true;
    }
    try testing.expect(found);
}

test "lint: composite PK via index passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "order_items", &.{
        th.makeField("order_id", .{ .simple = "n" }, &.{}, null),
        th.makeField("product_id", .{ .simple = "n" }, &.{}, null),
    }, &.{
        th.makeIndex("pk_order_items", .primary_key, &.{ "order_id", "product_id" }),
    });
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found_pk = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-pk")) found_pk = true;
    }
    try testing.expect(!found_pk);
}

// ─── Timestamps Tests ─────────────────────────────────────────

test "lint: no timestamps detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("name", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-timestamps")) found = true;
    }
    try testing.expect(found);
}

test "lint: timestamps present passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("name", .{ .simple = "s" }, &.{}, null),
        th.makeField("created_at", .{ .simple = "d" }, &.{}, null),
        th.makeField("updated_at", .{ .simple = "d" }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "no-timestamps")) {
            try testing.expect(false);
        }
    }
}

// ─── Wide Table Tests ─────────────────────────────────────────

test "lint: wide table detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var fields: [35]ast_mod.Field = undefined;
    for (0..35) |i| {
        var buf: [16]u8 = undefined;
        const name = std.fmt.bufPrint(&buf, "col_{d}", .{i}) catch "col";
        fields[i] = th.makeSimpleField(name);
    }
    const table = try th.makeTestTable(alloc, "wide_table", &fields, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "wide-table")) found = true;
    }
    try testing.expect(found);
}

test "lint: narrow table passes wide check" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "wide-table")) {
            try testing.expect(false);
        }
    }
}

// ─── Count Tests ──────────────────────────────────────────────

test "lint: low field count detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "empty_table", &.{
        th.makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "count")) found = true;
    }
    try testing.expect(found);
}

test "lint: sufficient field count passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
        th.makeSimpleField("email"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.no_pk, false);
    cfg.rules.setEnabled(.naming, false);
    cfg.rules.setEnabled(.no_index_fk, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "count")) {
            try testing.expect(false);
        }
    }
}

// ─── Empty Table Tests ────────────────────────────────────────

test "lint: empty table detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "empty_table", &.{}, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "empty-table")) found = true;
    }
    try testing.expect(found);
}

test "lint: non-empty table passes empty-table" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "empty-table")) {
            try testing.expect(false);
        }
    }
}

// ─── Table Comment Tests ──────────────────────────────────────

test "lint: table without comment detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "table-comment")) found = true;
    }
    try testing.expect(found);
}

test "lint: table with comment passes table-comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    table.comment = "User accounts table";
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "table-comment")) {
            try testing.expect(false);
        }
    }
}

// ─── Table Name Length Tests ──────────────────────────────────

test "lint: long table name detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const long_name = "this_is_a_very_long_table_name_that_exceeds_the_default_character_limit_of_sixty_four";
    const table = try th.makeTestTable(alloc, long_name, &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "table-name-length")) found = true;
    }
    try testing.expect(found);
}

test "lint: short table name passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "table-name-length")) {
            try testing.expect(false);
        }
    }
}

// ─── Column Length Tests ─────────────────────────────────────

test "lint: bare string type detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        // s is parsed as .varchar_explicit = 0 (no explicit length)
        th.makeField("name", .{ .varchar_explicit = 0 }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-length")) found = true;
    }
    try testing.expect(found);
}

test "lint: explicit varchar length passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("name", .{ .varchar_explicit = 64 }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-length")) {
            try testing.expect(false);
        }
    }
}

test "lint: column-length rule can be disabled" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("name", .{ .varchar_explicit = 0 }, &.{}, null),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_length, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-length")) {
            try testing.expect(false);
        }
    }
}

// ─── Naming Prefix Tests ────────────────────────────────────

test "lint: tbl_ prefix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "tbl_users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming-prefix")) found = true;
    }
    try testing.expect(found);
}

test "lint: t_ prefix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "t_config", &.{
        th.makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming-prefix")) found = true;
    }
    try testing.expect(found);
}

test "lint: table_ prefix detected" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "table_data", &.{
        th.makePkField("id"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    var found = false;
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming-prefix")) found = true;
    }
    try testing.expect(found);
}

test "lint: clean table name passes naming-prefix" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const test_ast = th.makeAst(tables);
    const results = try lintSchema(alloc, test_ast, .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "naming-prefix")) {
            try testing.expect(false);
        }
    }
}

// ─── column-no-comment ─────────────────────────────────────

test "lint: column without comment triggers column-no-comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Table has a comment, but column does not
    var table_buf: [1]ResolvedTable = undefined;
    var field_buf: [1]ast_mod.Field = undefined;
    field_buf[0] = th.makeField("name", .{ .simple = "s64" }, &.{}, null);
    table_buf[0] = .{
        .name = "users",
        .comment = "User accounts table",
        .doc = null,
        .engine = null,
        .fields = &field_buf,
        .fks = &.{},
        .indexes = &.{},
        .line_no = 1,
    };
    const tables = try alloc.dupe(ResolvedTable, &table_buf);
    const results = try lintSchema(alloc, th.makeAst(tables), .{});
    try testing.expect(th.findRule(results, "column-no-comment"));
}

test "lint: table without comment skips column-no-comment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Table has no comment, so column-no-comment should not trigger
    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeSimpleField("name"),
    }, &.{});
    const tables = try alloc.dupe(ResolvedTable, &.{table});
    const results = try lintSchema(alloc, th.makeAst(tables), .{});
    for (results.items) |r| {
        if (std.mem.eql(u8, r.rule, "column-no-comment")) {
            try testing.expect(false);
        }
    }
}

// ─── timestamp-type Tests ──────────────────────────────────────

test "lint: timestamp-type flags non-datetime column with timestamp name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "events", &.{
        th.makePkField("id"),
        th.makeField("verified_at", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const test_ast = th.makeAst(try alloc.dupe(ResolvedTable, &.{table}));
    const cfg = lint_mod.LintConfig{};
    const results = try lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "timestamp-type"));
}

test "lint: timestamp-type passes for datetime column with timestamp name" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "events", &.{
        th.makePkField("id"),
        th.makeField("verified_at", .{ .simple = "t" }, &.{}, null),
    }, &.{});
    const test_ast = th.makeAst(try alloc.dupe(ResolvedTable, &.{table}));
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_length, false);
    cfg.rules.setEnabled(.column_default_required, false);
    cfg.rules.setEnabled(.table_no_index, false);
    cfg.rules.setEnabled(.column_no_comment, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    cfg.rules.setEnabled(.table_comment, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "timestamp-type"));
}

// ─── pk-not-first Tests ──────────────────────────────────────

test "lint: pk-not-first flags pk not in first column" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makeField("name", .{ .simple = "s" }, &.{}, null),
        th.makePkField("id"),
    }, &.{});
    const test_ast = th.makeAst(try alloc.dupe(ResolvedTable, &.{table}));
    const cfg = lint_mod.LintConfig{};
    const results = try lintSchema(alloc, test_ast, cfg);
    try testing.expect(th.findRule(results, "pk-not-first"));
}

test "lint: pk-not-first passes when pk is first column" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const table = try th.makeTestTable(alloc, "users", &.{
        th.makePkField("id"),
        th.makeField("name", .{ .simple = "s" }, &.{}, null),
    }, &.{});
    const test_ast = th.makeAst(try alloc.dupe(ResolvedTable, &.{table}));
    var cfg = lint_mod.LintConfig{};
    cfg.rules.setEnabled(.column_length, false);
    cfg.rules.setEnabled(.column_default_required, false);
    cfg.rules.setEnabled(.table_no_index, false);
    cfg.rules.setEnabled(.column_no_comment, false);
    cfg.rules.setEnabled(.no_timestamps, false);
    cfg.rules.setEnabled(.table_comment, false);
    const results = try lintSchema(alloc, test_ast, cfg);
    try testing.expect(!th.findRule(results, "pk-not-first"));
}
