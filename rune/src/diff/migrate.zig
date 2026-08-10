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

// ─── Migration Context ─────────────────────────────────────
// Bundles shared state passed through all migration emission functions,
// replacing 9-parameter signatures with a single context struct.

const MigrationContext = struct {
    alloc: std.mem.Allocator,
    w: *std.Io.Writer,
    backend: *const dialect_mod.DialectBackend,
    cg: ?*codegen.Codegen,
    dialect: Dialect,
    resolved: resolved_ast.ResolvedAst,
    has_operations: *bool,
    needs_comma: *bool,
};

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

                var ctx = MigrationContext{
                    .alloc = alloc,
                    .w = w,
                    .backend = backend,
                    .cg = &cg,
                    .dialect = dialect,
                    .resolved = new_resolved,
                    .has_operations = &table_has_ops,
                    .needs_comma = &sub_needs_comma,
                };
                try emitAlterTableOps(&ctx, at);
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
            .drop_type => |dt| {
                try emitDropType(w, backend, dt.name, dialect);
                has_operations = true;
            },
            .create_type => |ct| {
                try emitCreateType(w, backend, ct.name, ct.type_def, dialect);
                has_operations = true;
            },
            .modify_type => |mt| {
                // For modify: drop old type, create new type
                try emitDropType(w, backend, mt.name, dialect);
                try emitCreateType(w, backend, mt.name, mt.new_type, dialect);
                has_operations = true;
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
    ctx: *MigrationContext,
    at: @import("plan.zig").MigrationPlan.AlterTable,
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
    try emitFieldDiffs(ctx, td);
    try emitIndexDiffs(ctx, td);
    try emitMetadataDiffs(ctx, td);
    try emitFkDiffs(ctx, td);
}

fn emitFieldDiffs(
    ctx: *MigrationContext,
    td: diff_mod.TableDiff,
) !void {
    for (td.field_diffs) |fd| {
        switch (fd.action) {
            .add => try emitAddField(ctx, td.name, fd),
            .drop => try emitDropField(ctx, td.name, fd),
            .modify => try emitModifyField(ctx, td.name, fd),
            .rename => try emitRenameField(ctx, td.name, fd),
        }
    }
}

fn emitAddField(
    ctx: *MigrationContext,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
) !void {
    if (ctx.cg) |c| {
        try emit.beginAlterTable(ctx.w, ctx.backend, table_name, ctx.has_operations);
        const field_to_use = if (fd.new_field) |nf| nf else if (fd.old_field) |of| of else return;
        try emit.emitComma(ctx.w, ctx.needs_comma);
        try ctx.w.writeAll("ADD COLUMN ");
        const typed_col = try TypeResolver.resolveColumn(ctx.alloc, field_to_use, ctx.dialect, ctx.resolved.custom_types);
        try c.emitColumnDef(ctx.w, typed_col);
    }
}

fn emitDropField(
    ctx: *MigrationContext,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
) !void {
    try emit.beginAlterTable(ctx.w, ctx.backend, table_name, ctx.has_operations);
    try emit.emitComma(ctx.w, ctx.needs_comma);
    try ctx.backend.emitAlterDropColumn(ctx.w, fd.name);
}

fn emitModifyField(
    ctx: *MigrationContext,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
) !void {
    try emit.beginAlterTable(ctx.w, ctx.backend, table_name, ctx.has_operations);
    const field_to_use = if (fd.new_field) |nf| nf else if (fd.old_field) |of| of else return;
    try emit.emitComma(ctx.w, ctx.needs_comma);
    try ctx.backend.emitAlterModifyColumn(ctx.w, field_to_use.name);
    if (ctx.backend.modify_needs_column_def) {
        const typed_col = try TypeResolver.resolveColumn(ctx.alloc, field_to_use, ctx.dialect, ctx.resolved.custom_types);
        if (ctx.cg) |c| {
            try c.emitColumnDefEx(ctx.w, typed_col, ctx.backend.modify_column_def_skips_name);
        }
    }
}

fn emitRenameField(
    ctx: *MigrationContext,
    table_name: []const u8,
    fd: diff_mod.FieldDiff,
) !void {
    try emit.beginAlterTable(ctx.w, ctx.backend, table_name, ctx.has_operations);
    if (fd.rename_from) |old_name| {
        try emit.emitComma(ctx.w, ctx.needs_comma);
        try ctx.backend.emitAlterRenameColumn(ctx.w, old_name, fd.name);
        if (ctx.backend.rename_needs_column_def) {
            const field_to_use = if (fd.new_field) |nf| nf else if (fd.old_field) |of| of else return;
            if (ctx.cg) |c| {
                const typed_col = try TypeResolver.resolveColumn(ctx.alloc, field_to_use, ctx.dialect, ctx.resolved.custom_types);
                try c.emitColumnDef(ctx.w, typed_col);
            }
        }
    }
}

fn emitIndexDiffs(
    ctx: *MigrationContext,
    td: diff_mod.TableDiff,
) !void {
    for (td.index_diffs) |idx_diff| {
        switch (idx_diff.action) {
            .add => {
                if (idx_diff.new_idx) |idx| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.backend.emitAlterAddIndex(ctx.w, td.name, idx);
                }
            },
            .drop => {
                if (idx_diff.old_idx) |idx| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.backend.emitAlterDropIndex(ctx.w, idx);
                }
            },
            .modify => {
                // Forward: drop old, add new; Rollback: drop new, add old
                const drop_idx = if (idx_diff.old_idx) |old_idx| old_idx else null;
                const add_idx = if (idx_diff.new_idx) |new_idx| new_idx else null;
                if (drop_idx) |di| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.backend.emitAlterDropIndex(ctx.w, di);
                }
                if (add_idx) |ai| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.backend.emitAlterAddIndex(ctx.w, td.name, ai);
                }
            },
        }
    }
}

fn emitMetadataDiffs(
    ctx: *MigrationContext,
    td: diff_mod.TableDiff,
) !void {
    if (td.metadata_diff) |md| {
        if (!optionalStrEq(md.old_comment, md.new_comment)) {
            const comment = md.new_comment;
            if (comment) |c| {
                const result = ctx.backend.commentResult();
                switch (result) {
                    .added_to_alter => {
                        try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                        try emit.emitComma(ctx.w, ctx.needs_comma);
                        try ctx.backend.emitAlterTableComment(ctx.w, td.name, c);
                    },
                    .standalone_emitted => {
                        if (ctx.has_operations.*) {
                            try ctx.w.writeAll(";\n\n");
                            ctx.has_operations.* = false;
                            ctx.needs_comma.* = false;
                        }
                        try ctx.backend.emitAlterTableComment(ctx.w, td.name, c);
                    },
                    .unsupported => {
                        try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                        try emit.emitComma(ctx.w, ctx.needs_comma);
                        try ctx.backend.emitAlterTableComment(ctx.w, td.name, c);
                    },
                }
            }
        }
        if (!optionalStrEq(md.old_engine, md.new_engine)) {
            try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
            try emit.emitComma(ctx.w, ctx.needs_comma);
            try ctx.backend.emitAlterEngine(ctx.w, md.new_engine);
        }
    }
}

fn emitFkDiffs(
    ctx: *MigrationContext,
    td: diff_mod.TableDiff,
) !void {
    for (td.fk_diffs) |fk_diff| {
        switch (fk_diff.action) {
            .add => {
                if (fk_diff.new_fk) |fk| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.w.writeAll("ADD ");
                    try ctx.backend.emitForeignKey(ctx.w, fk);
                }
            },
            .drop => {
                if (fk_diff.old_fk) |fk| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.backend.emitAlterDropFk(ctx.w, fk);
                }
            },
            .modify => {
                // Forward: drop old, add new; Rollback: drop new, add old
                const drop_fk = if (fk_diff.old_fk) |old_fk| old_fk else null;
                const add_fk = if (fk_diff.new_fk) |new_fk| new_fk else null;
                if (drop_fk) |df| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.backend.emitAlterDropFk(ctx.w, df);
                }
                if (add_fk) |af| {
                    try emit.beginAlterTable(ctx.w, ctx.backend, td.name, ctx.has_operations);
                    try emit.emitComma(ctx.w, ctx.needs_comma);
                    try ctx.w.writeAll("ADD ");
                    try ctx.backend.emitForeignKey(ctx.w, af);
                }
            },
        }
    }
}

// ─── Custom Type Emission ──────────────────────────────────────

/// Emit DROP TYPE statement for dialects that support it (PG, MySQL 8.0+).
fn emitDropType(
    w: *std.Io.Writer,
    backend: *const dialect_mod.DialectBackend,
    name: []const u8,
    dialect: Dialect,
) !void {
    switch (dialect) {
        .pg, .mysql => {
            try w.writeAll("DROP TYPE IF EXISTS ");
            try backend.quoteIdent(w, name);
            try w.writeAll(";\n\n");
        },
        .sqlite, .mssql, .oracle, .db2 => {
            // SQLite doesn't support CREATE/DROP TYPE; MSSQL/Oracle/Db2 use different syntax
            // Emit as a comment for documentation
            try w.writeAll("-- DROP TYPE ");
            try backend.quoteIdent(w, name);
            try w.writeAll(" -- (not supported in ");
            try w.writeAll(@tagName(dialect));
            try w.writeAll(")\n");
        },
    }
}

/// Emit CREATE TYPE statement for custom types.
fn emitCreateType(
    w: *std.Io.Writer,
    backend: *const dialect_mod.DialectBackend,
    name: []const u8,
    type_def: ast_mod.CustomType,
    dialect: Dialect,
) !void {
    switch (dialect) {
        .pg => {
            // PostgreSQL: CREATE TYPE name AS ENUM ('val1', 'val2', ...)
            try w.writeAll("CREATE TYPE ");
            try backend.quoteIdent(w, name);
            try w.writeAll(" AS ENUM (");
            try emitEnumValues(w, type_def, dialect);
            try w.writeAll(");\n");
        },
        .mysql => {
            // MySQL: CREATE TYPE is not standard; ENUM types are inline in column definitions
            // Emit as comment for documentation
            try w.writeAll("-- CREATE TYPE ");
            try backend.quoteIdent(w, name);
            try w.writeAll(" AS ENUM (");
            try emitEnumValues(w, type_def, dialect);
            try w.writeAll(") -- (MySQL uses inline ENUM)\n");
        },
        .sqlite, .mssql, .oracle, .db2 => {
            // SQLite doesn't support CREATE/DROP TYPE
            // Emit as comment for documentation
            try w.writeAll("-- CREATE TYPE ");
            try backend.quoteIdent(w, name);
            try w.writeAll(" AS ENUM (");
            try emitEnumValues(w, type_def, dialect);
            try w.writeAll(") -- (not supported in ");
            try w.writeAll(@tagName(dialect));
            try w.writeAll(")\n");
        },
    }
}

/// Emit enum values from a custom type definition.
fn emitEnumValues(
    w: *std.Io.Writer,
    type_def: ast_mod.CustomType,
    dialect: Dialect,
) !void {
    _ = dialect;
    // Extract enum values from the type definition.
    // In Rune syntax: ~ status : s { active, inactive, pending }
    // The enum values are stored in base.enum_type
    switch (type_def.base) {
        .enum_type => |values| {
            for (values, 0..) |val, i| {
                if (i > 0) try w.writeAll(", ");
                try w.writeAll("'");
                try w.writeAll(val);
                try w.writeAll("'");
            }
        },
        else => {
            // Non-enum base type — emit placeholder with type info
            try w.writeAll("'-- type: ");
            try w.writeAll(@tagName(type_def.base));
            try w.writeAll(" --'");
        },
    }
}
