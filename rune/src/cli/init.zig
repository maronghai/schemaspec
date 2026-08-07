const std = @import("std");
const io_mod = @import("../io.zig");
const dialect_enum = @import("../dialect/enum.zig");

// ─── `rune init` ──────────────────────────────────────────────

pub const STARTER_SCHEMA =
    \\; Starter schema — edit this file to define your database
    \\
    \\; ── Schema ─────────────────────────────────────────────
    \\
    \\$ mydb
    \\
    \\; ── Tables ─────────────────────────────────────────────
    \\
    \\; Users table
    \\# users
    \\id       n++
    \\email    s128
    \\name     s64
    \\role     e(editor,viewer) =viewer
    \\@ email
    \\
    \\; Posts table
    \\# posts
    \\id         n++
    \\title      s256
    \\body       S
    \\author_id  n              ; FK → users.id (auto-inferred from _id suffix)
    \\status     e(draft,published,archived) =draft
    \\@ author_id
    \\@ status
    \\
    \\; Comments table
    \\# comments
    \\id        n++
    \\post_id   n               ; FK → posts.id
    \\author_id n                ; FK → users.id
    \\body      S
    \\@ post_id
    \\
;

pub fn handleInit(io: std.Io, alloc: std.mem.Allocator, name: ?[]const u8, output: ?[]const u8, output_dir: ?[]const u8, dialect: dialect_enum.Dialect) !void {
    const filename = name orelse "schema";
    const out_path = output orelse blk: {
        if (output_dir) |dir| {
            // Create directory recursively (like mkdir -p)
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
            break :blk try std.fmt.allocPrint(alloc, "{s}/{s}.ss", .{ dir, filename });
        }
        break :blk try std.fmt.allocPrint(alloc, "{s}.ss", .{filename});
    };
    // Prepend dialect hint comment for the user
    const dialect_name = @tagName(dialect);
    const schema_with_hint = try std.fmt.allocPrint(alloc, "; Target dialect: {s}\n{s}", .{ dialect_name, STARTER_SCHEMA });
    try io_mod.writeOutput(io, schema_with_hint, out_path, false);
    std.debug.print("Created {s} (dialect: {s})\n", .{ out_path, dialect_name });
    std.debug.print("Edit this file, then run: rune {s} -d {s}\n", .{ out_path, dialect_name });
}
