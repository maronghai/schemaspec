const std = @import("std");
const sp = @import("../parser/sql_parser.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const Dialect = sp.Dialect;
const template_ext = @import("../reverse/template_extraction.zig");
const rc = @import("../reverse/column.zig");
const rf = @import("../reverse/fk.zig");

// ─── Reverse Codegen ─────────────────────────────────────────────
// Orchestrates SQL → SS generation. Column-level logic is delegated
// to reverse_column.zig, CHECK parsing to reverse_check.zig (via
// reverse_column.zig), and FK classification to reverse_fk.zig.

/// Reverse codegen engine: converts parsed SQL schema back to .ss format.
pub const ReverseCodegen = struct {
    alloc: std.mem.Allocator,
    dialect: Dialect,

    pub fn init(alloc: std.mem.Allocator, dialect: Dialect) ReverseCodegen {
        return .{ .alloc = alloc, .dialect = dialect };
    }

    /// Generate .ss schema from parsed SQL. Tables are output with inline type annotations.
    pub fn generate(self: *ReverseCodegen, schema: sp.SqlSchema) ![]const u8 {
        return self.generateInner(schema, false);
    }

    /// Generate .ss schema with template extraction — identifies common field patterns
    /// across tables and emits them as reusable templates (% name ...).
    pub fn generateWithTemplates(self: *ReverseCodegen, schema: sp.SqlSchema) ![]const u8 {
        return self.generateInner(schema, true);
    }

    fn generateInner(self: *ReverseCodegen, schema: sp.SqlSchema, extract_templates: bool) ![]const u8 {
        var aw = std.Io.Writer.Allocating.init(self.alloc);
        const w = &aw.writer;

        try emitSchemaHeader(self, w, schema);

        var tmpl_list: []template_ext.TemplateCandidate = &.{};
        if (extract_templates) {
            tmpl_list = try template_ext.findTemplates(self.alloc, schema);
            defer {
                for (tmpl_list) |t| {
                    self.alloc.free(t.fields);
                    self.alloc.free(t.table_indices);
                }
                self.alloc.free(tmpl_list);
            }
        }

        try emitTemplates(self, w, schema, tmpl_list);
        try emitTables(self, w, schema, tmpl_list);

        try w.flush();
        return try aw.toOwnedSlice();
    }
};

// ─── Sub-functions ──────────────────────────────────────────────

fn emitSchemaHeader(self: *ReverseCodegen, w: anytype, schema: sp.SqlSchema) !void {
    _ = self;
    if (schema.name) |name| {
        try w.print("$ {s}", .{name});
        if (schema.charset) |cs| {
            if (std.mem.eql(u8, cs, "utf8mb4") or std.mem.eql(u8, cs, "UTF8") or std.mem.eql(u8, cs, "utf8")) {
                // default charset — omit
            } else {
                try w.print(" {s}", .{cs});
            }
        }
        try w.writeAll("\n\n");
    }
}

fn emitTemplates(self: *ReverseCodegen, w: anytype, schema: sp.SqlSchema, tmpl_list: []template_ext.TemplateCandidate) !void {
    for (tmpl_list, 0..) |t, ti| {
        var ref_indexes: []const sp.SqlIndex = &.{};
        if (t.table_indices.len > 0) {
            ref_indexes = schema.tables[t.table_indices[0]].indexes;
        }

        // Find parent template (earlier template whose fields are a subset)
        var parent_name: ?[]const u8 = null;
        if (ti > 0) {
            var best_parent: usize = 0;
            var best_overlap: usize = 0;
            for (tmpl_list[0..ti], 0..) |prev, pi| {
                var overlap: usize = 0;
                for (prev.fields) |pf| {
                    for (t.fields) |tf| {
                        if (std.mem.eql(u8, pf.name, tf.name)) {
                            overlap += 1;
                            break;
                        }
                    }
                }
                if (overlap > best_overlap) {
                    best_overlap = overlap;
                    best_parent = pi;
                }
            }
            if (best_overlap > 0) {
                parent_name = tmpl_list[best_parent].name;
            }
        }

        // Output: % name [> parent] \n ...
        if (parent_name) |pn| {
            try w.print("% {s} > {s}\n...\n", .{ t.name, pn });
        } else {
            try w.print("% {s}\n...\n", .{t.name});
        }

        // Output only NEW fields (not in parent)
        for (t.fields) |col| {
            var in_parent = false;
            if (parent_name) |pn| {
                for (tmpl_list) |tl| {
                    if (std.mem.eql(u8, tl.name, pn)) {
                        for (tl.fields) |pf| {
                            if (std.mem.eql(u8, col.name, pf.name)) {
                                in_parent = true;
                                break;
                            }
                        }
                        break;
                    }
                }
            }
            if (in_parent) continue;
            try w.writeAll(col.name);
            try rc.writeColumnSuffix(w, col, ref_indexes, null, self.dialect);
            try w.writeAll("\n");
        }
        try w.writeAll("\n");
    }
}

fn emitTables(self: *ReverseCodegen, w: anytype, schema: sp.SqlSchema, tmpl_list: []template_ext.TemplateCandidate) !void {
    // Pre-build table_index → template_index lookup map for O(1) template resolution
    var table_to_template = std.AutoHashMap(usize, usize).init(self.alloc);
    defer table_to_template.deinit();
    for (tmpl_list, 0..) |t, ti| {
        for (t.table_indices) |table_idx| {
            try table_to_template.put(table_idx, ti);
        }
    }

    for (schema.tables, 0..) |table, ti| {
        // CHECK map
        var check_map = std.StringHashMap([]const u8).init(self.alloc);
        defer check_map.deinit();
        for (table.checks) |ck| {
            if (ck.field_name.len > 0) {
                if (rc.reverseCheck(self.alloc, ck.expr, ck.field_name)) |sym_expr| {
                    try check_map.put(ck.field_name, sym_expr);
                }
            }
        }

        // Find which template this table belongs to (if any)
        var table_template: ?[]const u8 = null;
        var table_template_fields: []const sp.SqlColumn = &.{};
        if (table_to_template.get(ti)) |tmpl_idx| {
            table_template = tmpl_list[tmpl_idx].name;
            table_template_fields = tmpl_list[tmpl_idx].fields;
        }

        // # [template_ref] table_name : comment
        try w.writeAll("# ");
        if (table_template) |tn| {
            try w.print("{s} ", .{tn});
        }
        try w.writeAll(table.name);
        if (table.comment) |c| {
            try w.print(" : {s}", .{c});
        }
        try w.writeAll("\n");

        // Output columns, skipping template fields if this table has a template
        for (table.columns) |col| {
            if (table_template != null) {
                var in_template = false;
                for (table_template_fields) |tcol| {
                    if (std.mem.eql(u8, col.name, tcol.name)) {
                        in_template = true;
                        break;
                    }
                }
                if (in_template) continue;
            }
            try w.writeAll(col.name);
            const ck = if (col.check_expr) |ce| rc.reverseCheck(self.alloc, ce, col.name) else check_map.get(col.name);
            try rc.writeColumnSuffix(w, col, table.indexes, ck, self.dialect);
            try w.writeAll("\n");
        }

        try emitStandaloneIndexes(self, w, table);
        try emitForeignKeys(self, w, table);

        if (ti < schema.tables.len - 1) try w.writeAll("\n");
    }
}

fn emitStandaloneIndexes(self: *ReverseCodegen, w: anytype, table: sp.SqlTable) !void {
    _ = self;
    for (table.indexes) |idx| {
        if (idx.kind == .primary_key) continue;
        if (rc.isInlineIndex(idx)) continue;

        try w.writeAll("\n");
        const is_auto = rc.isAutoGeneratedName(idx);
        switch (idx.kind) {
            .regular => {
                if (is_auto) {
                    try w.writeAll("@ ");
                    for (idx.fields, 0..) |f, fi| {
                        if (fi > 0) try w.writeAll(" ");
                        try w.writeAll(f);
                        if (fi < idx.descending.len and idx.descending[fi]) try w.writeAll("-");
                    }
                } else {
                    try w.print("@ {s} (", .{idx.name});
                    for (idx.fields, 0..) |f, fi| {
                        if (fi > 0) try w.writeAll(", ");
                        try w.writeAll(f);
                    }
                    try w.writeAll(")");
                }
            },
            .unique => {
                if (is_auto) {
                    try w.writeAll("@u ");
                    for (idx.fields, 0..) |f, fi| {
                        if (fi > 0) try w.writeAll(" ");
                        try w.writeAll(f);
                        if (fi < idx.descending.len and idx.descending[fi]) try w.writeAll("-");
                    }
                } else {
                    try w.print("@u {s} (", .{idx.name});
                    for (idx.fields, 0..) |f, fi| {
                        if (fi > 0) try w.writeAll(", ");
                        try w.writeAll(f);
                    }
                    try w.writeAll(")");
                }
            },
            .fulltext => try w.print("@f {s}", .{idx.name}),
            else => {}, // primary_key filtered above
        }
    }
}

fn emitForeignKeys(self: *ReverseCodegen, w: anytype, table: sp.SqlTable) !void {
    for (table.foreign_keys) |fk| {
        const cls = rf.classifyFk(self.alloc, fk);
        defer if (cls.text) |txt| self.alloc.free(txt);
        try w.writeAll("\n");
        if (cls.text) |txt| try w.writeAll(txt);
    }
}
