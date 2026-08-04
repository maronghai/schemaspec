const std = @import("std");
const diff_mod = @import("../diff/engine.zig");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const codegen = @import("../codegen/codegen.zig");
const typed_ast = @import("../types/typed_ast.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const dialect_enum = @import("../dialect/enum.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const utils = @import("../utils.zig");
const emit = @import("../diff/emit.zig");
const helpers = @import("migrate_helpers.zig");
const Field = ast_mod.Field;
const TypeInfo = ast_mod.TypeInfo;

const Dialect = dialect_enum.Dialect;

// ─── Helpers ───────────────────────────────────────────────

const optionalStrEq = utils.optionalStrEq;
const emitSingleTable = helpers.emitSingleTable;

// ─── generateFromDiff (orchestrator) ─────────────────────────

/// Generate forward migration SQL from a SchemaDiff. Outputs ALTER TABLE statements
/// wrapped in a BEGIN/COMMIT transaction.
pub fn generateFromDiff(
    alloc: std.mem.Allocator,
    d: diff_mod.SchemaDiff,
    new_typed: typed_ast.TypedAst,
    new_resolved: resolved_ast.ResolvedAst,
    dialect: Dialect,
) ![]const u8 {
    const plan_mod = @import("plan.zig");
    const plan = try plan_mod.planFromDiff(alloc, d);
    defer alloc.free(plan.operations);
    return generateFromPlan(alloc, plan, new_typed, new_resolved, dialect);
}

/// Generate forward migration SQL from a MigrationPlan.
pub fn generateFromPlan(
    alloc: std.mem.Allocator,
    plan: @import("plan.zig").MigrationPlan,
    new_typed: typed_ast.TypedAst,
    new_resolved: resolved_ast.ResolvedAst,
    dialect: Dialect,
) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    const w = &aw.writer;

    try w.writeAll("-- ");
    try w.writeAll(plan.header.comment);
    try w.writeAll("\n");
    try dialect_enum.writeMigrationHeader(w, plan.header.command);
    try w.writeAll("BEGIN;\n\n");

    var has_operations = false;
    const backend = dialect_mod.getBackend(dialect);

    for (plan.operations) |op| {
        switch (op) {
            .drop_table => |dt| {
                try w.writeAll("DROP TABLE IF EXISTS ");
                try backend.quoteIdent(w, dt.name);
                try w.writeAll(";\n\n");
                has_operations = true;
            },
            .create_table => |ct| {
                var cg = codegen.Codegen.init(alloc, dialect);
                has_operations = true;
                try emitSingleTable(alloc, w, &cg, new_resolved, ct.name, dialect);
            },
            .alter_table => |at| {
                var table_has_ops = false;
                var sub_needs_comma = false;
                var cg = codegen.Codegen.init(alloc, dialect);

                try emitAlterTableOps(alloc, w, backend, at, &cg, dialect, new_resolved, &table_has_ops, &sub_needs_comma);
                if (table_has_ops) {
                    has_operations = true;
                    try w.writeAll(";\n");
                }
            },
            .drop_view => |dv| {
                try w.writeAll("DROP VIEW IF EXISTS ");
                try backend.quoteIdent(w, dv.name);
                try w.writeAll(";\n\n");
                has_operations = true;
            },
            .create_view => |cv| {
                if (emit.findTypedView(new_typed, cv.name)) |view| {
                    try backend.emitCreateView(w, view.name, view.query);
                    try w.writeAll("\n");
                    has_operations = true;
                }
            },
            .modify_view => |mv| {
                try w.writeAll("DROP VIEW IF EXISTS ");
                try backend.quoteIdent(w, mv.name);
                try w.writeAll(";\n\n");
                if (emit.findTypedView(new_typed, mv.name)) |view| {
                    try backend.emitCreateView(w, view.name, view.query);
                    try w.writeAll("\n");
                    has_operations = true;
                }
            },
        }
    }

    try w.writeAll("COMMIT;\n");
    try w.flush();
    return try aw.toOwnedSlice();
}

// ─── Rollback Generation ─────────────────────────────────────

/// Generate rollback SQL from a SchemaDiff. Outputs the inverse operations
/// (re-create dropped tables, reverse ALTER TABLE changes) wrapped in BEGIN/COMMIT.
pub fn generateRollback(
    alloc: std.mem.Allocator,
    d: diff_mod.SchemaDiff,
    old_typed: typed_ast.TypedAst,
    old_resolved: resolved_ast.ResolvedAst,
    dialect: Dialect,
) ![]const u8 {
    const plan_mod = @import("plan.zig");
    const plan = try plan_mod.planFromDiff(alloc, d);
    defer alloc.free(plan.operations);
    const inv = try plan_mod.invertPlan(alloc, plan);
    defer {
        for (inv.operations) |op| {
            switch (op) {
                .alter_table => |at| {
                    alloc.free(at.field_diffs);
                    alloc.free(at.index_diffs);
                    alloc.free(at.fk_diffs);
                },
                else => {},
            }
        }
        alloc.free(inv.operations);
    }
    return generateFromPlan(alloc, inv, old_typed, old_resolved, dialect);
}

// ─── Shared Emission Functions ──────────────────────────────────

/// Emit ALTER TABLE operations from a plan's AlterTable operation.
/// Bridges the plan IR to the existing field/index/FK emission helpers.
fn emitAlterTableOps(
    alloc: std.mem.Allocator,
    w: anytype,
    backend: dialect_mod.DialectBackend,
    at: @import("plan.zig").MigrationPlan.AlterTable,
    cg: ?*codegen.Codegen,
    dialect: Dialect,
    resolved: resolved_ast.ResolvedAst,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    // Bridge to existing helpers by constructing a temporary TableDiff
    const td = diff_mod.TableDiff{
        .name = at.name,
        .action = .alter,
        .field_diffs = at.field_diffs,
        .index_diffs = at.index_diffs,
        .fk_diffs = at.fk_diffs,
        .metadata_diff = at.metadata_diff,
    };
    try emitFieldDiffs(alloc, w, backend, td, cg, dialect, resolved, table_has_ops, sub_needs_comma);
    try emitIndexDiffs(w, backend, td, table_has_ops, sub_needs_comma);
    try emitMetadataDiffs(w, backend, td, table_has_ops, sub_needs_comma);
    try emitFkDiffs(w, backend, td, table_has_ops, sub_needs_comma);
}

fn emitFieldDiffs(
    alloc: std.mem.Allocator,
    w: anytype,
    backend: dialect_mod.DialectBackend,
    td: diff_mod.TableDiff,
    cg: ?*codegen.Codegen,
    dialect: Dialect,
    resolved: resolved_ast.ResolvedAst,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    for (td.field_diffs) |fd| {
        switch (fd.action) {
            .add => try emitAddField(alloc, w, backend, td.name, fd, cg, dialect, resolved, table_has_ops, sub_needs_comma),
            .drop => try emitDropField(w, backend, td.name, fd, table_has_ops, sub_needs_comma),
            .modify => try emitModifyField(alloc, w, backend, td.name, fd, cg, dialect, resolved, table_has_ops, sub_needs_comma),
            .rename => try emitRenameField(alloc, w, backend, td.name, fd, cg, dialect, resolved, table_has_ops, sub_needs_comma),
        }
    }
}

fn emitAddField(
    alloc: std.mem.Allocator,
    w: anytype,
    backend: dialect_mod.DialectBackend,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
    cg: ?*codegen.Codegen,
    dialect: Dialect,
    resolved: resolved_ast.ResolvedAst,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    if (cg) |c| {
        try emit.beginAlterTable(w, backend, table_name, table_has_ops);
        const field_to_use = if (fd.new_field) |nf| nf else if (fd.old_field) |of| of else return;
        try emit.emitComma(w, sub_needs_comma);
        try w.writeAll("ADD COLUMN ");
        const typed_col = try TypeResolver.resolveColumn(alloc, field_to_use, dialect, resolved.custom_types);
        try c.emitColumnDef(w, typed_col);
    }
}

fn emitDropField(
    w: anytype,
    backend: dialect_mod.DialectBackend,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    try emit.beginAlterTable(w, backend, table_name, table_has_ops);
    try emit.emitComma(w, sub_needs_comma);
    try backend.emitAlterDropColumn(w, fd.name);
}

fn emitModifyField(
    alloc: std.mem.Allocator,
    w: anytype,
    backend: dialect_mod.DialectBackend,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
    cg: ?*codegen.Codegen,
    dialect: Dialect,
    resolved: resolved_ast.ResolvedAst,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    try emit.beginAlterTable(w, backend, table_name, table_has_ops);
    const field_to_use = if (fd.new_field) |nf| nf else if (fd.old_field) |of| of else return;
    try emit.emitComma(w, sub_needs_comma);
    try backend.emitAlterModifyColumn(w, field_to_use.name);
    if (backend.modify_needs_column_def) {
        const typed_col = try TypeResolver.resolveColumn(alloc, field_to_use, dialect, resolved.custom_types);
        if (cg) |c| {
            try c.emitColumnDefEx(w, typed_col, backend.modify_column_def_skips_name);
        }
    }
}

fn emitRenameField(
    alloc: std.mem.Allocator,
    w: anytype,
    backend: dialect_mod.DialectBackend,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
    cg: ?*codegen.Codegen,
    dialect: Dialect,
    resolved: resolved_ast.ResolvedAst,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    try emit.beginAlterTable(w, backend, table_name, table_has_ops);
    if (fd.rename_from) |old_name| {
        try emit.emitComma(w, sub_needs_comma);
        try backend.emitAlterRenameColumn(w, old_name, fd.name);
        if (backend.rename_needs_column_def) {
            const field_to_use = if (fd.new_field) |nf| nf else if (fd.old_field) |of| of else return;
            if (cg) |c| {
                const typed_col = try TypeResolver.resolveColumn(alloc, field_to_use, dialect, resolved.custom_types);
                try c.emitColumnDef(w, typed_col);
            }
        }
    }
}

fn emitIndexDiffs(
    w: anytype,
    backend: dialect_mod.DialectBackend,
    td: diff_mod.TableDiff,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    for (td.index_diffs) |idx_diff| {
        switch (idx_diff.action) {
            .add => {
                if (idx_diff.new_idx) |idx| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try backend.emitAlterAddIndex(w, td.name, idx);
                }
            },
            .drop => {
                if (idx_diff.old_idx) |idx| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try backend.emitAlterDropIndex(w, idx);
                }
            },
            .modify => {
                // Forward: drop old, add new; Rollback: drop new, add old
                const drop_idx = if (idx_diff.old_idx) |old_idx| old_idx else null;
                const add_idx = if (idx_diff.new_idx) |new_idx| new_idx else null;
                if (drop_idx) |di| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try backend.emitAlterDropIndex(w, di);
                }
                if (add_idx) |ai| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try backend.emitAlterAddIndex(w, td.name, ai);
                }
            },
        }
    }
}

fn emitMetadataDiffs(
    w: anytype,
    backend: dialect_mod.DialectBackend,
    td: diff_mod.TableDiff,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    if (td.metadata_diff) |md| {
        if (!optionalStrEq(md.old_comment, md.new_comment)) {
            const comment = md.new_comment;
            if (comment) |c| {
                const result = backend.commentResult();
                switch (result) {
                    .added_to_alter => {
                        try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                        try emit.emitComma(w, sub_needs_comma);
                        try backend.emitAlterTableComment(w, td.name, c);
                    },
                    .standalone_emitted => {
                        if (table_has_ops.*) {
                            try w.writeAll(";\n\n");
                            table_has_ops.* = false;
                            sub_needs_comma.* = false;
                        }
                        try backend.emitAlterTableComment(w, td.name, c);
                    },
                    .unsupported => {
                        try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                        try emit.emitComma(w, sub_needs_comma);
                        try backend.emitAlterTableComment(w, td.name, c);
                    },
                }
            }
        }
        if (!optionalStrEq(md.old_engine, md.new_engine)) {
            try emit.beginAlterTable(w, backend, td.name, table_has_ops);
            try emit.emitComma(w, sub_needs_comma);
            try backend.emitAlterEngine(w, md.new_engine);
        }
    }
}

fn emitFkDiffs(
    w: anytype,
    backend: dialect_mod.DialectBackend,
    td: diff_mod.TableDiff,
    table_has_ops: *bool,
    sub_needs_comma: *bool,
) !void {
    for (td.fk_diffs) |fk_diff| {
        switch (fk_diff.action) {
            .add => {
                if (fk_diff.new_fk) |fk| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try w.writeAll("ADD ");
                    try backend.emitForeignKey(w, fk);
                }
            },
            .drop => {
                if (fk_diff.old_fk) |fk| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try backend.emitAlterDropFk(w, fk);
                }
            },
            .modify => {
                // Forward: drop old, add new; Rollback: drop new, add old
                const drop_fk = if (fk_diff.old_fk) |old_fk| old_fk else null;
                const add_fk = if (fk_diff.new_fk) |new_fk| new_fk else null;
                if (drop_fk) |df| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try backend.emitAlterDropFk(w, df);
                }
                if (add_fk) |af| {
                    try emit.beginAlterTable(w, backend, td.name, table_has_ops);
                    try emit.emitComma(w, sub_needs_comma);
                    try w.writeAll("ADD ");
                    try backend.emitForeignKey(w, af);
                }
            },
        }
    }
}

