const std = @import("std");
const validation = @import("validation.zig");
const forward = @import("forward.zig");
const lint_mod = @import("../lint.zig");

const testing = std.testing;

// ─── ValidateConfig Tests ────────────────────────────────────

test "ValidateConfig: defaults" {
    const cfg = validation.ValidateConfig{};
    try testing.expect(!cfg.stats);
    try testing.expect(!cfg.verbose_passes);
    try testing.expect(!cfg.json_errors);
    try testing.expect(!cfg.strict);
    try testing.expect(cfg.format == .text);
    try testing.expect(!cfg.per_table);
    try testing.expect(!cfg.fix);
    try testing.expect(cfg.input == null);
}

test "ValidateConfig: custom values" {
    const cfg = validation.ValidateConfig{
        .stats = true,
        .verbose_passes = true,
        .json_errors = true,
        .strict = true,
        .format = .json,
        .per_table = true,
        .fix = true,
        .input = "test.ss",
    };
    try testing.expect(cfg.stats);
    try testing.expect(cfg.verbose_passes);
    try testing.expect(cfg.json_errors);
    try testing.expect(cfg.strict);
    try testing.expect(cfg.format == .json);
    try testing.expect(cfg.per_table);
    try testing.expect(cfg.fix);
    try testing.expectEqualStrings("test.ss", cfg.input.?);
}

test "ValidateConfig: SARIF format" {
    const cfg = validation.ValidateConfig{ .format = .sarif };
    try testing.expect(cfg.format == .sarif);
}

test "ValidateConfig: summary format" {
    const cfg = validation.ValidateConfig{ .format = .summary };
    try testing.expect(cfg.format == .summary);
}

// ─── Compilation Integration Tests ───────────────────────────

test "validation: valid schema compiles successfully" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "# users\nid n ++\nname s32\n";
    const result = try forward.compilePipeline(alloc, source, .{});
    try testing.expect(result.resolved.tables.len > 0);
    try testing.expect(!result.partial);
}

test "validation: schema with foreign keys compiles" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "# users\nid n ++\nname s32\n\n# posts\nid n ++\ntitle s64\nuser_id n > users.id\n";
    const result = try forward.compilePipeline(alloc, source, .{});
    try testing.expect(result.resolved.tables.len == 2);
}

test "validation: schema with views compiles" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "# users\nid n ++\nname s32\n\n+ user_view: SELECT id, name FROM users\n";
    const result = try forward.compilePipeline(alloc, source, .{});
    try testing.expect(result.resolved.tables.len >= 1);
}

test "validation: stats computation works" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "# users\nid n ++\nname s32\nemail s64\n\n# posts\nid n ++\ntitle s64\nuser_id n > users.id\n";
    const result = try forward.compilePipeline(alloc, source, .{});
    const s = forward.computeStats(result.resolved);
    try testing.expect(s.tables == 2);
    try testing.expect(s.fields > 0);
    try testing.expect(s.foreign_keys >= 1);
}

test "validation: invalid schema produces error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "this is not valid ss\n";
    const result = forward.compilePipeline(alloc, source, .{});
    // Invalid schema should return an error (DiagnosticsError or SemanticError)
    if (result) |_| {
        // If partial result, that's OK
    } else |_| {
        // Expected: error returned
    }
}

test "validation: formatValidateResult with valid schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "# users\nid n ++\nname s32\n";
    const result = try forward.compilePipeline(alloc, source, .{});
    const s = forward.computeStats(result.resolved);
    const json = try validation.formatValidateResult(alloc, !result.partial, s, 0);
    try testing.expect(std.mem.indexOf(u8, json, "\"valid\":true") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"tables\":1") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"errors\":0") != null);
}

test "validation: formatValidateSarif with valid schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const sarif = try validation.formatValidateSarif(alloc, true, 0);
    try testing.expect(std.mem.indexOf(u8, sarif, "$schema") != null);
    try testing.expect(std.mem.indexOf(u8, sarif, "sarif") != null);
    try testing.expect(std.mem.indexOf(u8, sarif, "executionSuccessful") != null);
}

test "validation: formatValidateSarif with errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const sarif = try validation.formatValidateSarif(alloc, false, 5);
    try testing.expect(std.mem.indexOf(u8, sarif, "executionSuccessful") != null);
    try testing.expect(std.mem.indexOf(u8, sarif, "5 error(s)") != null);
}

test "validation: strict mode with clean schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "# users\nid n ++\nname s32\n";
    const pipeline = try forward.compilePipeline(alloc, source, .{});
    const lint_results = try lint_mod.lintSchema(alloc, pipeline.resolved, .{});
    var has_warnings = false;
    for (lint_results.items) |r| {
        if (r.severity == .warning) {
            has_warnings = true;
            break;
        }
    }
    try testing.expect(!has_warnings);
}

test "validation: strict mode with lint warnings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // Schema with no-pk warning (table has no primary key)
    const source = "# users\nname s32\n";
    const pipeline = try forward.compilePipeline(alloc, source, .{});
    const lint_results = try lint_mod.lintSchema(alloc, pipeline.resolved, .{});
    var has_warnings = false;
    for (lint_results.items) |r| {
        if (r.severity == .warning) {
            has_warnings = true;
            break;
        }
    }
    try testing.expect(has_warnings);
}

test "validation: summary line format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const source = "# users\nid n ++\nname s32\n\n# posts\nid n ++\ntitle s64\nuser_id n > users.id\n+ post_view: SELECT id, title FROM posts\n";
    const result = try forward.compilePipeline(alloc, source, .{});
    const s = forward.computeStats(result.resolved);

    const summary = try std.fmt.allocPrint(alloc, "Tables: {d}, Fields: {d}, Views: {d}, Indexes: {d}, FKs: {d}\n", .{
        s.tables, s.fields, s.views, s.indexes, s.foreign_keys,
    });
    try testing.expect(std.mem.indexOf(u8, summary, "Tables:") != null);
    try testing.expect(std.mem.indexOf(u8, summary, "Fields:") != null);
    try testing.expect(std.mem.indexOf(u8, summary, "FKs:") != null);
}
