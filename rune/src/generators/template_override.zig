const std = @import("std");
const version = @import("../version.zig");

// ─── Template Overrides ──────────────────────────────────────
// `.rune-template` files let users customize generator output without
// touching generator code. A template is discovered per generator by
// name (`<generator-name>.rune-template`) in the first of these
// directories that exists:
//
//   1. explicit dir (--template-dir)
//   2. ./.rune/templates/          (project-local)
//   3. ~/.rune/templates/          (user-global)
//
// Supported placeholders:
//   {{SCHEMA_NAME}} {{DIALECT}} {{VERSION}} {{GENERATOR}}
//   {{#TABLES}} ... {{TABLE_NAME}} ... {{/TABLES}}   (loop expansion)
//
// Unknown {{...}} tokens are emitted verbatim so users can layer their
// own conventions on top. Note: distinct from the schema registry
// (~/.rune/registry/, shared `%` template libraries) — this directory
// customizes *generator output*.

/// A loaded template override for one generator.
pub const TemplateOverride = struct {
    generator_name: []const u8,
    body: []const u8,
    source_path: []const u8,
};

/// Values substituted into a template during render.
pub const RenderContext = struct {
    schema_name: []const u8,
    dialect_name: []const u8,
    tables: []const []const u8,
};

/// Build the `<dir>/<generator>.rune-template` path.
fn templatePath(alloc: std.mem.Allocator, dir: []const u8, generator_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{s}/{s}.rune-template", .{ dir, generator_name });
}

/// Read a file, returning null if it does not exist (other errors propagate).
fn readFileIfExists(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(4 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}

/// Resolve the user-global override directory: `$HOME/.rune/templates/`
/// (or `$USERPROFILE` on Windows). Returns null when neither variable is set.
pub fn userTemplatesDir(alloc: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ?[]const u8 {
    const home = environ_map.get("HOME") orelse environ_map.get("USERPROFILE") orelse return null;
    return std.fs.path.join(alloc, &.{ home, ".rune", "templates" }) catch null;
}

/// Load a template override for `generator_name`.
///
/// Search order: `explicit_dir` > `./.rune/templates/` > `~/.rune/templates/`.
/// Returns null when no template file exists in any of them (callers fall
/// back to built-in generator logic).
pub fn load(
    io: std.Io,
    alloc: std.mem.Allocator,
    generator_name: []const u8,
    explicit_dir: ?[]const u8,
    environ_map: *const std.process.Environ.Map,
) !?TemplateOverride {
    if (explicit_dir) |dir| {
        if (try loadFromDir(io, alloc, dir, generator_name)) |t| return t;
    }
    if (try loadFromDir(io, alloc, ".rune/templates", generator_name)) |t| return t;
    if (userTemplatesDir(alloc, environ_map)) |dir| {
        if (try loadFromDir(io, alloc, dir, generator_name)) |t| return t;
    }
    return null;
}

fn loadFromDir(io: std.Io, alloc: std.mem.Allocator, dir: []const u8, generator_name: []const u8) !?TemplateOverride {
    const path = try templatePath(alloc, dir, generator_name);
    const body = (try readFileIfExists(io, alloc, path)) orelse return null;
    return .{
        .generator_name = try alloc.dupe(u8, generator_name),
        .body = body,
        .source_path = path,
    };
}

// ─── Render Engine ───────────────────────────────────────────

/// Render a template body against `ctx`, expanding global placeholders and
/// the `{{#TABLES}}...{{/TABLES}}` loop. An unmatched `{{#TABLES}}` or
/// `{{/TABLES}}` is an error.
pub fn render(
    alloc: std.mem.Allocator,
    tmpl: TemplateOverride,
    ctx: RenderContext,
) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();

    var i: usize = 0;
    while (i < tmpl.body.len) {
        if (std.mem.startsWith(u8, tmpl.body[i..], "{{#TABLES}}")) {
            const block_start = i + "{{#TABLES}}".len;
            const close_rel = std.mem.indexOf(u8, tmpl.body[block_start..], "{{/TABLES}}") orelse
                return error.UnmatchedTablesBlock;
            const block_body = tmpl.body[block_start .. block_start + close_rel];
            for (ctx.tables) |table_name| {
                try expandPlaceholders(&out.writer, block_body, tmpl.generator_name, ctx, table_name);
            }
            i = block_start + close_rel + "{{/TABLES}}".len;
        } else if (std.mem.startsWith(u8, tmpl.body[i..], "{{/TABLES}}")) {
            return error.UnmatchedTablesBlock;
        } else {
            // Expand placeholders up to the next {{#TABLES}} or {{/TABLES}}
            // marker so loop blocks are found even mid-text.
            const rest = tmpl.body[i..];
            const next_block = nextMarker(rest) orelse rest.len;
            try expandPlaceholders(&out.writer, rest[0..next_block], tmpl.generator_name, ctx, null);
            i += next_block;
        }
    }
    return out.toOwnedSlice();
}

/// Offset of the next `{{#TABLES}}` or `{{/TABLES}}` marker in `text`, if any.
fn nextMarker(text: []const u8) ?usize {
    const open = std.mem.indexOf(u8, text, "{{#TABLES}}");
    const close = std.mem.indexOf(u8, text, "{{/TABLES}}");
    if (open == null) return close;
    if (close == null) return open;
    return @min(open.?, close.?);
}

/// Expand `{{NAME}}` placeholders in `text`. When `table_name` is non-null,
/// `{{TABLE_NAME}}` resolves to it (loop iteration); otherwise it is left
/// verbatim. Unknown placeholders pass through unchanged.
fn expandPlaceholders(
    w: *std.Io.Writer,
    text: []const u8,
    generator_name: []const u8,
    ctx: RenderContext,
    table_name: ?[]const u8,
) !void {
    var i: usize = 0;
    while (i < text.len) {
        if (!std.mem.startsWith(u8, text[i..], "{{")) {
            try w.writeByte(text[i]);
            i += 1;
            continue;
        }
        const close = std.mem.indexOfPos(u8, text, i + 2, "}}") orelse {
            // No closing braces — emit the rest literally.
            try w.writeAll(text[i..]);
            return;
        };
        const inner = text[i + 2 .. close];
        if (std.mem.eql(u8, inner, "SCHEMA_NAME")) {
            try w.writeAll(ctx.schema_name);
        } else if (std.mem.eql(u8, inner, "DIALECT")) {
            try w.writeAll(ctx.dialect_name);
        } else if (std.mem.eql(u8, inner, "VERSION")) {
            try w.writeAll(version.VERSION);
        } else if (std.mem.eql(u8, inner, "GENERATOR")) {
            try w.writeAll(generator_name);
        } else if (std.mem.eql(u8, inner, "TABLE_NAME")) {
            if (table_name) |tn| try w.writeAll(tn) else try w.writeAll("{{TABLE_NAME}}");
        } else {
            // Unknown placeholder — keep it verbatim.
            try w.writeAll(text[i .. close + 2]);
        }
        i = close + 2;
    }
}
