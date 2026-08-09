const std = @import("std");
pub const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const diag = @import("../semantic/diagnostic.zig");
const template_mod = @import("../semantic/template.zig");
const pm = @import("../semantic/pass_manager.zig");
const symbol_table_mod = @import("../types/symbol_table.zig");
pub const PassContext = pm.PassContext;
pub const SemanticPass = pm.SemanticPass;
pub const DEFAULT_PASSES = pm.DEFAULT_PASSES;
const Ast = ast_mod.Ast;
const ResolvedTable = resolved_ast.ResolvedTable;
const ResolvedAst = resolved_ast.ResolvedAst;
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── SemanticAnalyzer ──────────────────────────────────────────

pub const SemanticAnalyzer = struct {
    alloc: std.mem.Allocator,
    verbose: bool,
    use_color: bool = false,
    /// Target dialect for conditional block resolution.
    dialect: Dialect = .mysql,

    pub fn init(alloc: std.mem.Allocator) SemanticAnalyzer {
        return .{ .alloc = alloc, .verbose = false };
    }

    pub fn initVerbose(alloc: std.mem.Allocator) SemanticAnalyzer {
        return .{ .alloc = alloc, .verbose = true };
    }

    pub fn initWithColor(alloc: std.mem.Allocator, verbose: bool, use_color: bool) SemanticAnalyzer {
        return .{ .alloc = alloc, .verbose = verbose, .use_color = use_color };
    }

    pub fn analyze(self: *SemanticAnalyzer, tree: Ast) !ResolvedAst {
        return self.analyzeWithCollector(tree, null);
    }

    /// Run semantic analysis with an optional external DiagnosticCollector.
    /// When collector is provided, diagnostics are written to it instead of stderr.
    /// The caller owns the collector and can inspect it after the call.
    pub fn analyzeWithCollector(self: *SemanticAnalyzer, tree: Ast, external_collector: ?*diag.DiagnosticCollector) !ResolvedAst {
        const resolved_tables = try template_mod.resolveAndApply(self.alloc, tree);

        var tables = try std.ArrayList(ResolvedTable).initCapacity(self.alloc, resolved_tables.len);
        for (resolved_tables) |t| {
            try tables.append(self.alloc, t);
        }

        const tmpl_map = try template_mod.buildTemplateMap(self.alloc, tree.templates);

        // Build set of referenced templates (for unused template detection)
        var template_refs = std.StringHashMap(void).init(self.alloc);
        for (tree.tables) |t| {
            if (t.template_ref) |tref| {
                _ = try template_refs.put(tref, {});
            }
        }
        for (tree.templates) |*t| {
            for (t.parents) |parent| {
                _ = try template_refs.put(parent, {});
            }
        }

        pm.validateDependencyOrder(self.alloc);
        pm.validatePassAccess(self.alloc);
        var owned_diagnostics = if (external_collector == null)
            try diag.DiagnosticCollector.init(self.alloc)
        else
            undefined;
        if (external_collector == null) {
            owned_diagnostics.use_color = self.use_color;
        }
        var diagnostics_ptr = if (external_collector) |ec| ec else &owned_diagnostics;
        var ctx = pm.PassContext.init(
            self.alloc,
            &tables,
            tree.schema,
            tmpl_map,
            template_refs,
            diagnostics_ptr,
            symbol_table_mod.SymbolTable.init(self.alloc),
        );
        ctx.dialect = self.dialect;
        ctx.views = tree.views;
        for (DEFAULT_PASSES) |pass| {
            if (self.verbose) {
                const table_count = ctx.tables.items.len;
                std.debug.print("  pass: {s} (tables={d}) ...\n", .{ pass.name, table_count });
            }
            const table_count_before = ctx.tables.items.len;
            try pass.run(&ctx);
            const table_count_after = ctx.tables.items.len;
            // Runtime validation: passes that don't declare modifies_table_list
            // must not change the table count
            if (!pass.access.modifies_table_list and table_count_before != table_count_after) {
                diagnostics_ptr.push(.{
                    .severity = .@"error",
                    .line_no = 0,
                    .message = "internal error: semantic pass changed table count without declaring modifies_table_list",
                });
                return error.PassConstraintViolation;
            }
            if (self.verbose) {
                std.debug.print("  pass: {s} done (tables={d})\n", .{ pass.name, table_count_after });
            }
        }

        // Only print diagnostics when using the internal collector (CLI mode)
        if (external_collector == null) {
            owned_diagnostics.printAll();
        }

        if (diagnostics_ptr.hasErrors()) {
            return error.SemanticError;
        }

        return .{
            .schema_name = if (tree.schema) |s| s.name else null,
            .schema_charset = if (tree.schema) |s| s.charset orelse "utf8mb4" else null,
            .custom_types = if (tree.schema) |s| s.custom_types else &.{},
            .tables = try tables.toOwnedSlice(self.alloc),
            .views = tree.views,
            .sql_comments = tree.sql_comments,
        };
    }
};

// ─── Diagnostic ──────────────────────────────────────────────

const trace = @import("../semantic/trace.zig");

pub fn diagnosticTrace(resolved: ResolvedAst) void {
    std.debug.print("=== [Stage 3: Semantic] ===\n\n", .{});

    std.debug.print("Suffix inference:\n", .{});
    std.debug.print("  _id -> int, _on -> date, _at -> datetime, (none) -> varchar(255)\n", .{});
    if (resolved.schema_name != null) {
        std.debug.print("  autofk: ", .{});
        var has_autofk = false;
        for (resolved.tables) |table| {
            for (table.fields) |field| {
                if (field.fk) |fk| {
                    if (fk.fields.len > 0 and fk.fields[0].len > 3 and std.mem.endsWith(u8, fk.fields[0], "_id")) {
                        has_autofk = true;
                        break;
                    }
                }
            }
            if (has_autofk) break;
        }
        if (has_autofk) {
            std.debug.print("yes\n", .{});
        } else {
            std.debug.print("no\n", .{});
        }
    }
    std.debug.print("\n", .{});

    if (resolved.tables.len > 0) {
        std.debug.print("Resolved tables ({d}):\n", .{resolved.tables.len});
        for (resolved.tables) |table| {
            std.debug.print("  # {s}", .{table.name});
            if (table.comment) |c| std.debug.print(" {s}", .{c});
            std.debug.print("\n", .{});

            for (table.fields) |field| {
                if (std.mem.eql(u8, field.name, "...")) continue;
                std.debug.print("    {s: <24} ", .{field.name});
                trace.fmtTypeInfo(field.type_info);
                trace.fmtModifiers(field.modifiers);
                if (field.default_val) |dv| std.debug.print(" DEFAULT {s}", .{dv.value});
                if (field.check) |ck| std.debug.print(" CHECK({s})", .{ck.expr});
                if (field.fk) |fk| {
                    std.debug.print(" -> {s}(", .{fk.ref_table});
                    for (fk.ref_fields, 0..) |f, fi| {
                        if (fi > 0) std.debug.print(",", .{});
                        std.debug.print("{s}", .{f});
                    }
                    std.debug.print(")", .{});
                    for (fk.actions) |action| {
                        trace.formatFkAction(action);
                    }
                }
                if (field.comment) |c| std.debug.print(" {s}", .{c});
                std.debug.print("\n", .{});
            }
            for (table.indexes) |idx| {
                trace.formatResolvedIndex(idx);
            }
        }
        std.debug.print("\n", .{});
    }

    if (resolved.sql_comments.len > 0) {
        std.debug.print("SQL Comments ({d}):\n", .{resolved.sql_comments.len});
        for (resolved.sql_comments) |sc| {
            std.debug.print("  L{d}: {s}\n", .{ sc.line_no, sc.text });
        }
        std.debug.print("\n", .{});
    }
}
