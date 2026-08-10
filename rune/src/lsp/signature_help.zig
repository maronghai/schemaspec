const std = @import("std");
const TypedAst = @import("../types/typed_ast.zig").TypedAst;
const TypedColumn = @import("../types/typed_ast.zig").TypedColumn;
const protocol = @import("protocol.zig");
const Position = protocol.Position;

// ─── Signature Help ──────────────────────────────────────────
// Provides textDocument/signatureHelp for table field declarations,
// FK references, and custom type definitions.

pub const SignatureHelp = struct {
    signatures: []const SignatureInformation,
    active_signature: u32 = 0,
    active_parameter: u32 = 0,
};

pub const SignatureInformation = struct {
    label: []const u8,
    documentation: ?[]const u8 = null,
    parameters: []const ParameterInformation,
};

pub const ParameterInformation = struct {
    label: []const u8,
    documentation: ?[]const u8 = null,
};

/// Get signature help at the given position in the document.
pub fn getSignatureHelp(
    alloc: std.mem.Allocator,
    ast: TypedAst,
    doc_text: []const u8,
    position: Position,
) ?SignatureHelp {
    // Find which line we're on
    const line = findLine(doc_text, position.line) orelse return null;

    // Check if we're inside a table block (between { and })
    if (isInsideTable(line)) {
        return getFieldSignature(alloc, line);
    }

    // Check if we're on an FK line
    if (std.mem.indexOf(u8, line, "->") != null) {
        return getFkSignature(alloc, ast, line);
    }

    return null;
}

/// Get field declaration signature help.
fn getFieldSignature(alloc: std.mem.Allocator, line: []const u8) ?SignatureHelp {
    // Parse field name from the line (first token before type)
    const trimmed = std.mem.trimStart(u8, line, " \t");
    if (trimmed.len == 0) return null;

    // Extract field name (first word)
    var name_end: usize = 0;
    while (name_end < trimmed.len and trimmed[name_end] != ' ' and trimmed[name_end] != '\t' and trimmed[name_end] != ':' and trimmed[name_end] != '\n') {
        name_end += 1;
    }
    const field_name = trimmed[0..name_end];

    // Common field modifiers for documentation
    const modifiers = [_]ParameterInformation{
        .{ .label = "PK", .documentation = "Primary key constraint" },
        .{ .label = "++", .documentation = "Auto-increment (INTEGER PRIMARY KEY AUTOINCREMENT)" },
        .{ .label = "!NN", .documentation = "NOT NULL constraint" },
        .{ .label = "?", .documentation = "Nullable column" },
        .{ .label = "= <value>", .documentation = "Default value" },
        .{ .label = "# <table>", .documentation = "Inline foreign key reference" },
        .{ .label = "// <text>", .documentation = "Inline comment" },
        .{ .label = "@ check(<expr>)", .documentation = "CHECK constraint" },
        .{ .label = "+ <text>", .documentation = "Documentation comment" },
    };

    // Build label directly using a fixed buffer
    var label_buf: [128]u8 = undefined;
    const label_len = std.fmt.bufPrint(&label_buf, "{s} <type> [modifiers]", .{field_name}) catch return null;
    const label = alloc.dupe(u8, label_len) catch return null;

    return .{
        .signatures = &.{
            .{
                .label = label,
                .documentation = "Column declaration: name type [modifiers]",
                .parameters = alloc.dupe(ParameterInformation, &modifiers) catch &.{},
            },
        },
        .active_signature = 0,
        .active_parameter = 0,
    };
}

/// Get FK reference signature help.
fn getFkSignature(alloc: std.mem.Allocator, ast: TypedAst, line: []const u8) ?SignatureHelp {
    _ = ast;

    const fk_params = [_]ParameterInformation{
        .{ .label = "<table>", .documentation = "Referenced table name" },
        .{ .label = "<field(s)>", .documentation = "Referenced field(s) in the target table" },
        .{ .label = "on-delete <action>", .documentation = "ON DELETE action: cascade | restrict | set-null | set-default | no-action" },
        .{ .label = "on-update <action>", .documentation = "ON UPDATE action: cascade | restrict | set-null | set-default | no-action" },
    };

    // Detect which parameter we're at based on position after ->
    var active_param: u32 = 0;
    if (std.mem.indexOf(u8, line, "on-delete") != null) active_param = 2;
    if (std.mem.indexOf(u8, line, "on-update") != null) active_param = 3;

    return .{
        .signatures = &.{
            .{
                .label = "-> <table>.<field(s)> [on-delete <action>] [on-update <action>]",
                .documentation = "Foreign key declaration",
                .parameters = alloc.dupe(ParameterInformation, &fk_params) catch &.{},
            },
        },
        .active_signature = 0,
        .active_parameter = active_param,
    };
}

/// Find the line text for a given 0-based line number.
fn findLine(doc_text: []const u8, target_line: u32) ?[]const u8 {
    var current_line: u32 = 0;
    var start: usize = 0;

    for (doc_text, 0..) |ch, i| {
        if (current_line == target_line) {
            if (ch == '\n' or i == doc_text.len - 1) {
                const end = if (ch == '\n') i else i + 1;
                return doc_text[start..end];
            }
        }
        if (ch == '\n') {
            current_line += 1;
            start = i + 1;
        }
    }
    return null;
}

/// Check if we're inside a table block (line has content between { and }).
fn isInsideTable(line: []const u8) bool {
    // Simple heuristic: if the line has a colon or is indented, it's likely a field
    const trimmed = std.mem.trimStart(u8, line, " \t");
    if (trimmed.len == 0) return false;
    // Lines starting with # or % are table/template headers, not fields
    if (trimmed.len > 0 and (trimmed[0] == '#' or trimmed[0] == '%')) return false;
    // Lines starting with @ are directives
    if (trimmed.len > 0 and trimmed[0] == '@') return false;
    // Lines starting with ; are comments
    if (trimmed.len > 0 and trimmed[0] == ';') return false;
    // Lines starting with -> are FK declarations
    if (trimmed.len >= 2 and trimmed[0] == '-' and trimmed[1] == '>') return false;
    return true;
}

/// Write SignatureHelp as JSON.
pub fn writeSignatureHelp(w: anytype, help: SignatureHelp) !void {
    try w.writeByte('{');
    try w.writeAll("\"signatures\":[");
    for (help.signatures, 0..) |sig, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeByte('{');
        try protocol.writeJsonField(w, "label", sig.label);
        if (sig.documentation) |doc| {
            try w.writeByte(',');
            try protocol.writeJsonField(w, "documentation", doc);
        }
        try w.writeAll(",\"parameters\":[");
        for (sig.parameters, 0..) |param, j| {
            if (j > 0) try w.writeByte(',');
            try w.writeByte('{');
            try protocol.writeJsonField(w, "label", param.label);
            if (param.documentation) |doc| {
                try w.writeByte(',');
                try protocol.writeJsonField(w, "documentation", doc);
            }
            try w.writeByte('}');
        }
        try w.writeByte(']');
        try w.writeByte('}');
    }
    try w.writeByte(']');
    try w.print(",\"activeSignature\":{d}", .{help.active_signature});
    try w.print(",\"activeParameter\":{d}", .{help.active_parameter});
    try w.writeByte('}');
}

// ─── Tests ───────────────────────────────────────────────────

test "SignatureHelp: field declaration" {
    const alloc = std.testing.allocator;
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const doc = "# users {\n  id N4 ++\n}";
    const result = getSignatureHelp(alloc, ast, doc, .{ .line = 1, .character = 5 });
    // Line 1 is "  id N4 ++" which is inside table
    try std.testing.expect(result != null);
    if (result) |help| {
        // Free allocated label
        if (help.signatures.len > 0) {
            alloc.free(help.signatures[0].label);
            if (help.signatures[0].parameters.len > 0) {
                alloc.free(help.signatures[0].parameters);
            }
        }
    }
}

test "SignatureHelp: FK declaration" {
    const alloc = std.testing.allocator;
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const doc = "# users {\n  -> posts.id\n}";
    const result = getSignatureHelp(alloc, ast, doc, .{ .line = 1, .character = 5 });
    try std.testing.expect(result != null);
    if (result) |help| {
        try std.testing.expectEqual(@as(u32, 0), help.active_signature);
        // Free allocated parameters
        if (help.signatures.len > 0) {
            if (help.signatures[0].parameters.len > 0) {
                alloc.free(help.signatures[0].parameters);
            }
        }
    }
}

test "SignatureHelp: no help for table header" {
    const ast = TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };
    const doc = "# users {\n}";
    const result = getSignatureHelp(std.testing.allocator, ast, doc, .{ .line = 0, .character = 0 });
    try std.testing.expect(result == null);
}
