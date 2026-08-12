const std = @import("std");
const tk = @import("tokenizer.zig");
const diag = @import("../diagnostic.zig");
const ast_mod = @import("../types/ast.zig");
const FkDecl = ast_mod.FkDecl;
const FkAction = ast_mod.FkAction;
const FkActionType = ast_mod.FkActionType;

pub const FkParseResult = struct {
    fk: FkDecl,
    end_idx: usize,
};

/// Split a dotted reference like "table.f1.f2" into table and field parts.
/// Returns owned allocations: table string and fields slice (each element is owned).
/// Caller must free each field, then the fields slice, then the table.
fn parseDottedRef(
    alloc: std.mem.Allocator,
    ref: []const u8,
    trailing_dot_fallback: ?[]const u8,
) !struct { table: []const u8, fields: []const []const u8 } {
    var table: []const u8 = "";
    var fields = try std.ArrayList([]const u8).initCapacity(alloc, 4);

    if (std.mem.indexOfScalar(u8, ref, '.')) |dot| {
        table = try alloc.dupe(u8, ref[0..dot]);
        if (dot + 1 < ref.len) {
            const rest = ref[dot + 1 ..];
            var start: usize = 0;
            while (start < rest.len) {
                var end = start;
                while (end < rest.len and rest[end] != '.') : (end += 1) {}
                if (end > start) {
                    try fields.append(alloc, try alloc.dupe(u8, rest[start..end]));
                } else if (trailing_dot_fallback) |fb| {
                    try fields.append(alloc, try alloc.dupe(u8, fb));
                }
                start = if (end < rest.len) end + 1 else rest.len;
            }
        } else if (trailing_dot_fallback) |fb| {
            // Trailing dot: table. with nothing after the dot
            try fields.append(alloc, try alloc.dupe(u8, fb));
        }
    }
    return .{ .table = table, .fields = try fields.toOwnedSlice(alloc) };
}

/// Parse standalone FK: `> field_name ref_table[.ref_field] [actions]`
/// or inline reconstructed FK from field line.
pub fn parseFk(alloc: std.mem.Allocator, line: tk.Line) !FkDecl {
    var local_fields = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    var ref_table: []const u8 = "";
    var ref_fields = try std.ArrayList([]const u8).initCapacity(alloc, 4);

    const tokens = line.tokens;

    // Standard FK forms
    // Standalone FK (from tokenizer): [>, field_name, ref]  fi=1
    // Inline FK (reconstructed):     [field_name, >, ref]  fi=0, off=1
    const has_prefix = tokens.len >= 2 and std.mem.eql(u8, tokens[0], ">");
    const fi: usize = if (has_prefix) 1 else 0; // field index
    // Inline FK has `>` separator at fi+1, shifting ref by +1
    const has_sep = !has_prefix and tokens.len >= 2 and std.mem.eql(u8, tokens[1], ">");
    const off: usize = if (has_sep) 1 else 0; // offset for ref due to > separator
    const next_idx = fi + 1 + off;

    // Local field name: always at fi (0 for inline, 1 for standalone)
    const local_field_name = if (fi < tokens.len) line.tokens[fi] else "";

    // Reference index: skip > separator when present, also skip type token if present
    var ref_idx = if (has_sep) fi + 2 else next_idx;
    // When there's a separator and the token after > is a type (not a ref), skip it
    if (has_sep and ref_idx < tokens.len) {
        const candidate = tokens[ref_idx];
        const looks_like_ref = std.mem.indexOfScalar(u8, candidate, '.') != null or
            std.mem.eql(u8, candidate, "(") or
            candidate.len == 0;
        if (!looks_like_ref) {
            ref_idx += 1; // skip type token
        }
    }

    // When tokens[fi] contains a dot, it's the reference (ultra shorthand).
    const ref_is_at_fi = !has_sep and fi < tokens.len and
        std.mem.indexOfScalar(u8, tokens[fi], '.') != null;

    // For "> table" (no dot, no bracket, exactly 2 tokens), reference is at fi
    const ultra_no_dot = has_prefix and !has_sep and !ref_is_at_fi and tokens.len == 2;
    const ref_effective = if (ref_is_at_fi or ultra_no_dot) fi else ref_idx;

    const ref_has_dot = tokens.len > ref_effective and std.mem.indexOfScalar(u8, tokens[ref_effective], '.') != null;

    // Find first dot-containing token for compound FK support
    var dot_tok_idx: ?usize = null;
    {
        var si: usize = if (has_sep) fi + 2 else fi + 1;
        while (si < tokens.len) : (si += 1) {
            if (std.mem.indexOfScalar(u8, tokens[si], '.') != null) {
                dot_tok_idx = si;
                break;
            }
        }
    }

    // For compound FKs, the effective reference is the first dot-containing token
    const ref_compound = if (!ref_has_dot and dot_tok_idx != null) dot_tok_idx.? else ref_effective;
    const ref_has_dot_final = tokens.len > ref_compound and std.mem.indexOfScalar(u8, tokens[ref_compound], '.') != null;

    if (ref_has_dot_final) {
        // field table.field  or  table.field (inline ultra)
        if (ref_is_at_fi) {
            // Inline ultra: table.field — no local field
            const ref = line.tokens[ref_effective];
            if (std.mem.endsWith(u8, ref, ".") and ref.len > 1) {
                // Trailing dot: infer local field, use it as ref field
                ref_table = try alloc.dupe(u8, ref[0 .. ref.len - 1]);
                const inferred = try std.fmt.allocPrint(alloc, "{s}_id", .{ref_table});
                try local_fields.append(alloc, inferred);
                try ref_fields.append(alloc, try alloc.dupe(u8, inferred));
            } else {
                const parsed = try parseDottedRef(alloc, ref, null);
                ref_table = parsed.table;
                for (parsed.fields) |f| {
                    try ref_fields.append(alloc, try alloc.dupe(u8, f));
                }
                // Free parsed results after copying
                for (parsed.fields) |f| alloc.free(f);
                alloc.free(parsed.fields);
                // Infer local field from ref_table (e.g. users.id → users_id)
                const inferred = try std.fmt.allocPrint(alloc, "{s}_id", .{ref_table});
                try local_fields.append(alloc, inferred);
            }
        } else {
            // Standard: field(s) table.field(s)
            if (dot_tok_idx) |dti| {
                // Compound: collect all local fields before the dot token
                var li: usize = fi;
                while (li < dti) : (li += 1) {
                    try local_fields.append(alloc, try alloc.dupe(u8, line.tokens[li]));
                }
            } else if (fi < tokens.len) {
                try local_fields.append(alloc, try alloc.dupe(u8, local_field_name));
            }
            const ref = line.tokens[ref_compound];
            const parsed = try parseDottedRef(alloc, ref, local_field_name);
            ref_table = parsed.table;
            for (parsed.fields) |f| {
                try ref_fields.append(alloc, try alloc.dupe(u8, f));
            }
            // Free parsed results after copying
            for (parsed.fields) |f| alloc.free(f);
            alloc.free(parsed.fields);
        }
    } else if (ultra_no_dot) {
        // > table — ultra shorthand without dot (infer field = table_id, ref_field = id)
        ref_table = try alloc.dupe(u8, line.tokens[fi]);
        try ref_fields.append(alloc, try alloc.dupe(u8, "id"));
        const inferred = try std.fmt.allocPrint(alloc, "{s}_id", .{ref_table});
        try local_fields.append(alloc, inferred);
    } else if (tokens.len > ref_effective) {
        // field_name ref_table (shorthand-no-dot)
        try local_fields.append(alloc, try alloc.dupe(u8, local_field_name));
        const ref = line.tokens[ref_effective];
        if (std.mem.endsWith(u8, ref, ".") and ref.len > 1) {
            // Trailing dot: use local field name as ref field
            ref_table = try alloc.dupe(u8, ref[0 .. ref.len - 1]);
            try ref_fields.append(alloc, try alloc.dupe(u8, local_field_name));
        } else if (std.mem.indexOfScalar(u8, ref, '.')) |dot| {
            ref_table = try alloc.dupe(u8, ref[0..dot]);
            try ref_fields.append(alloc, try alloc.dupe(u8, ref[dot + 1 ..]));
        } else {
            ref_table = try alloc.dupe(u8, ref);
            try ref_fields.append(alloc, try alloc.dupe(u8, "id"));
        }
    }

    // Warn if FK form was unrecognized (empty fields/ref_table)
    if (local_fields.items.len == 0 and ref_table.len == 0) {
        diag.printDiagnostic(alloc, .{
            .severity = .warning,
            .line_no = line.line_no,
            .col = if (tokens.len > 0) diag.tokenColumn(tokens[0], line.raw) else null,
            .message = "unrecognized foreign key form",
            .expected = "> field_name table.field or > table.field",
            .source_line = line.raw,
        });
    }

    // Parse FK actions after reference (-S, -N, S, N)
    const actions = try parseFkActions(alloc, tokens, ref_compound + 1);

    return .{
        .fields = try local_fields.toOwnedSlice(alloc),
        .ref_table = ref_table,
        .ref_fields = try ref_fields.toOwnedSlice(alloc),
        .actions = actions,
        .line_no = line.line_no,
    };
}

/// Parse FK action tokens: -C (ON DELETE CASCADE), -N (ON DELETE SET NULL),
/// C (ON UPDATE CASCADE), N (ON UPDATE SET NULL).
pub fn parseFkActions(alloc: std.mem.Allocator, tokens: []const []const u8, start: usize) ![]const FkAction {
    var actions = try std.ArrayList(FkAction).initCapacity(alloc, 4);
    var i = start;
    while (i < tokens.len) : (i += 1) {
        const tok = tokens[i];
        // Combined token: -C, -N (no whitespace)
        if (tok.len == 2 and tok[0] == '-' and (tok[1] == 'C' or tok[1] == 'N')) {
            const act: FkActionType = if (tok[1] == 'C') .cascade else .set_null;
            try actions.append(alloc, .{ .trigger = .on_delete, .action = act });
            continue;
        }
        // Split tokens: - C, - N (space-separated)
        if (tok.len == 1 and tok[0] == '-' and i + 1 < tokens.len) {
            const act_tok = tokens[i + 1];
            if (act_tok.len == 1 and (act_tok[0] == 'C' or act_tok[0] == 'N')) {
                const act: FkActionType = if (act_tok[0] == 'C') .cascade else .set_null;
                try actions.append(alloc, .{ .trigger = .on_delete, .action = act });
                i += 1;
                continue;
            }
        }
        // ON UPDATE: standalone C or N
        if (tok.len == 1 and (tok[0] == 'C' or tok[0] == 'N')) {
            const act: FkActionType = if (tok[0] == 'C') .cascade else .set_null;
            try actions.append(alloc, .{ .trigger = .on_update, .action = act });
            continue;
        }
        break; // not an action token, stop
    }
    return try actions.toOwnedSlice(alloc);
}

/// Detect inline FK: `> table.field` or `table.field`.
/// Returns the FK and the index after all consumed tokens.
pub fn parseInlineFk(alloc: std.mem.Allocator, tokens: []const []const u8, idx: usize, field_name: []const u8, raw: []const u8, trimmed: []const u8, line_no: usize) !FkParseResult {
    var fk_tokens = try std.ArrayList([]const u8).initCapacity(alloc, 8);
    try fk_tokens.append(alloc, field_name);
    var j: usize = idx;
    if (std.mem.eql(u8, tokens[idx], ">")) {
        j = idx + 1;
        if (j < tokens.len) {
            const after_gt = tokens[j];
            if (std.mem.indexOfScalar(u8, after_gt, '.') == null) {
                j += 1; // skip type token
            }
        }
    }
    while (j < tokens.len) : (j += 1) {
        const rt = tokens[j];
        if (rt.len >= 1 and rt[0] == ':') break;
        if (rt.len >= 2 and rt[0] == '-' and rt[1] == '-') break;
        if (rt.len > 0 and rt[0] == ';') break;
        try fk_tokens.append(alloc, rt);
    }
    const fk_slice = try fk_tokens.toOwnedSlice(alloc);
    const fk_line = tk.Line{
        .line_type = .FK,
        .tokens = fk_slice,
        .raw = raw,
        .trimmed = trimmed,
        .line_no = line_no,
    };
    const fk = try parseFk(alloc, fk_line);
    // Skip FK action tokens that were already collected
    while (j < tokens.len) {
        const at = tokens[j];
        if (at.len == 2 and at[0] == '-' and (at[1] == 'C' or at[1] == 'N')) {
            j += 1;
            if (j < tokens.len and tokens[j].len == 1 and
                (tokens[j][0] == 'C' or tokens[j][0] == 'N'))
            {
                j += 1;
            }
        } else if (at.len == 1 and (at[0] == 'C' or at[0] == 'N')) {
            j += 1;
        } else if (at.len == 1 and at[0] == '-' and j + 1 < tokens.len) {
            const nxt = tokens[j + 1];
            if (nxt.len == 1 and (nxt[0] == 'C' or nxt[0] == 'N')) {
                j += 2;
            } else break;
        } else break;
    }
    return .{ .fk = fk, .end_idx = j };
}
