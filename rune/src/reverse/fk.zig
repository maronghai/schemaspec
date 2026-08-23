const std = @import("std");
const sp = @import("../parser/sql_parser.zig");

// ─── FK Reverse Classification ─────────────────────────────────
// Extracted from reverse_codegen.zig for single-responsibility.
// Classifies SQL foreign keys into SS shorthand/full forms.

pub const FkForm = enum { shorthand, full };

pub const FkClassification = struct {
    form: FkForm,
    text: ?[]const u8,
};

pub fn classifyFk(alloc: std.mem.Allocator, fk: sp.SqlForeignKey) FkClassification {
    const single = fk.fields.len == 1 and fk.ref_fields.len == 1;
    const ref_is_id = fk.ref_fields.len == 1 and std.mem.eql(u8, fk.ref_fields[0], "id");

    if (single and ref_is_id and fk.actions.len == 0) return .{ .form = .shorthand, .text = fmtFk(alloc, "> {s} {s}.id", .{ fk.fields[0], fk.ref_table }) };

    // Full form — use ArrayList for dynamic sizing
    var buf = std.ArrayList(u8).initCapacity(alloc, 64) catch return .{ .form = .full, .text = null };
    buf.appendSlice(alloc, "> ") catch return .{ .form = .full, .text = null };
    if (single) {
        buf.appendSlice(alloc, fk.fields[0]) catch return .{ .form = .full, .text = null };
    } else {
        buf.append(alloc, '(') catch return .{ .form = .full, .text = null };
        for (fk.fields, 0..) |f, i| {
            if (i > 0) buf.appendSlice(alloc, ", ") catch return .{ .form = .full, .text = null };
            buf.appendSlice(alloc, f) catch return .{ .form = .full, .text = null };
        }
        buf.append(alloc, ')') catch return .{ .form = .full, .text = null };
    }
    buf.append(alloc, ' ') catch return .{ .form = .full, .text = null };
    buf.appendSlice(alloc, fk.ref_table) catch return .{ .form = .full, .text = null };
    // No explicit column list (`REFERENCES table`) — omit the parentheses;
    // the target defaults to the referenced table's primary key.
    if (fk.ref_fields.len > 0) {
        buf.append(alloc, '(') catch return .{ .form = .full, .text = null };
        for (fk.ref_fields, 0..) |f, i| {
            if (i > 0) buf.appendSlice(alloc, ", ") catch return .{ .form = .full, .text = null };
            buf.appendSlice(alloc, f) catch return .{ .form = .full, .text = null };
        }
        buf.append(alloc, ')') catch return .{ .form = .full, .text = null };
    }

    for (fk.actions) |a| {
        // RESTRICT / NO ACTION are the .ss default (omitted) — emitting them
        // would round-trip as explicit tokens the language doesn't have.
        if (a.action == .restrict or a.action == .no_action) continue;
        buf.append(alloc, ' ') catch return .{ .form = .full, .text = null };
        switch (a.trigger) {
            .on_delete => switch (a.action) {
                .cascade => buf.appendSlice(alloc, "-C") catch {},
                .set_null => buf.appendSlice(alloc, "-N") catch {},
                else => buf.appendSlice(alloc, "-?") catch {},
            },
            .on_update => switch (a.action) {
                .cascade => buf.appendSlice(alloc, "C") catch {},
                .set_null => buf.appendSlice(alloc, "N") catch {},
                else => buf.appendSlice(alloc, "?") catch {},
            },
        }
    }

    return .{ .form = .full, .text = buf.toOwnedSlice(alloc) catch null };
}

fn fmtFk(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ?[]const u8 {
    return std.fmt.allocPrint(alloc, fmt, args) catch null;
}
