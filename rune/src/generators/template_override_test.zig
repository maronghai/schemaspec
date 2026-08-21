const std = @import("std");
const testing = std.testing;
const template_override = @import("template_override.zig");

const TemplateOverride = template_override.TemplateOverride;
const RenderContext = template_override.RenderContext;

fn makeTmpl(body: []const u8) TemplateOverride {
    return .{
        .generator_name = "prisma",
        .body = body,
        .source_path = "test.rune-template",
    };
}

fn makeCtx(tables: []const []const u8) RenderContext {
    return .{
        .schema_name = "myapp",
        .dialect_name = "pg",
        .tables = tables,
    };
}

// ─── render: global placeholders ─────────────────────────────

test "render replaces global placeholders" {
    const out = try template_override.render(
        testing.allocator,
        makeTmpl("// {{SCHEMA_NAME}} | {{DIALECT}} | {{VERSION}} | {{GENERATOR}}\n"),
        makeCtx(&.{}),
    );
    defer testing.allocator.free(out);
    try testing.expect(std.mem.startsWith(u8, out, "// myapp | pg | "));
    try testing.expect(std.mem.endsWith(u8, out, " | prisma\n"));
}

test "render leaves unknown placeholders verbatim" {
    const out = try template_override.render(
        testing.allocator,
        makeTmpl("{{UNKNOWN}} {{SCHEMA_NAME}}"),
        makeCtx(&.{}),
    );
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{{UNKNOWN}} myapp", out);
}

test "render passes through literal braces without placeholder" {
    const out = try template_override.render(
        testing.allocator,
        makeTmpl("a { b } c {{SCHEMA_NAME}} d"),
        makeCtx(&.{}),
    );
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("a { b } c myapp d", out);
}

// ─── render: tables loop ─────────────────────────────────────

test "render expands tables loop with TABLE_NAME" {
    const tmpl = makeTmpl(
        \\# {{SCHEMA_NAME}}
        \\{{#TABLES}}model {{TABLE_NAME}} {}
        \\{{/TABLES}}done
    );
    const out = try template_override.render(
        testing.allocator,
        tmpl,
        makeCtx(&.{ "user", "order" }),
    );
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("# myapp\nmodel user {}\nmodel order {}\ndone", out);
}

test "render empty tables produces no loop output" {
    const out = try template_override.render(
        testing.allocator,
        makeTmpl("{{#TABLES}}[{{TABLE_NAME}}]{{/TABLES}}"),
        makeCtx(&.{}),
    );
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("", out);
}

test "render globals work inside the loop body" {
    const out = try template_override.render(
        testing.allocator,
        makeTmpl("{{#TABLES}}{{SCHEMA_NAME}}.{{TABLE_NAME}}{{/TABLES}}"),
        makeCtx(&.{"user"}),
    );
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("myapp.user", out);
}

test "render TABLE_NAME outside a loop stays verbatim" {
    const out = try template_override.render(
        testing.allocator,
        makeTmpl("{{TABLE_NAME}}"),
        makeCtx(&.{"user"}),
    );
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{{TABLE_NAME}}", out);
}

// ─── render: unmatched block errors ──────────────────────────

test "render errors on unmatched open block" {
    try testing.expectError(
        error.UnmatchedTablesBlock,
        template_override.render(testing.allocator, makeTmpl("{{#TABLES}}x"), makeCtx(&.{})),
    );
}

test "render errors on unmatched close block" {
    try testing.expectError(
        error.UnmatchedTablesBlock,
        template_override.render(testing.allocator, makeTmpl("{{/TABLES}}"), makeCtx(&.{})),
    );
}

// ─── load: discovery (temp dir) ──────────────────────────────

test "load returns null when no template exists anywhere" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();

    const result = try template_override.load(
        testing.io,
        arena,
        "nonexistent-generator-xyz",
        null,
        &env,
    );
    try testing.expect(result == null);
}

test "load finds template in explicit dir first" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    // Explicit dir wins over project-local.
    _ = try tmp.dir.createDirPathOpen(testing.io, "explicit", .{});
    _ = try tmp.dir.createDirPathOpen(testing.io, ".rune/templates", .{});
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "explicit/prisma.rune-template",
        .data = "explicit",
    });
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = ".rune/templates/prisma.rune-template",
        .data = "project-local",
    });

    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var env = std.process.Environ.Map.init(arena);
    defer env.deinit();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_abs_len = try tmp.dir.realPath(testing.io, &path_buf);
    const explicit_path = try std.fs.path.join(arena, &.{ path_buf[0..tmp_abs_len], "explicit" });
    const found = (try template_override.load(testing.io, arena, "prisma", explicit_path, &env)).?;
    try testing.expectEqualStrings("explicit", found.body);
}
