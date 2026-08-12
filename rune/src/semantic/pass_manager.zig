const std = @import("std");
pub const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const diag = @import("../diagnostic.zig");
const symbol_table_mod = @import("../types/symbol_table.zig");
const ResolvedTable = resolved_ast.ResolvedTable;
const Template = ast_mod.Template;
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── Pass Manager ──────────────────────────────────────────────
// Extracted from semantic.zig (was analyzer.zig) for single-responsibility.

/// Shared mutable context passed to each semantic pass.
///
/// Always use `init()` to construct PassContext — all fields are required.
pub const PassContext = struct {
    alloc: std.mem.Allocator,
    tables: *std.ArrayList(ResolvedTable),
    schema: ?ast_mod.Schema,
    templates: std.StringHashMap(*const Template),
    /// Set of template names referenced by tables (template_ref) or other templates (parents).
    /// Populated by the analyzer before passes run. Used by validate_unused_templates for unused template detection.
    template_refs: std.StringHashMap(void),
    diagnostics: *diag.DiagnosticCollector,
    symbol_table: symbol_table_mod.SymbolTable,
    /// Target dialect for conditional block resolution.
    dialect: Dialect = .mysql,
    /// Views from the AST — available for view validation passes.
    views: []const ast_mod.View = &.{},

    /// Create a PassContext with proper initialization of all fields.
    /// Prefer this over struct literal for clarity and safety.
    pub fn init(
        alloc: std.mem.Allocator,
        tables: *std.ArrayList(ResolvedTable),
        schema: ?ast_mod.Schema,
        templates: std.StringHashMap(*const Template),
        template_refs: std.StringHashMap(void),
        diagnostics: *diag.DiagnosticCollector,
        symbol_table: symbol_table_mod.SymbolTable,
    ) PassContext {
        return .{
            .alloc = alloc,
            .tables = tables,
            .schema = schema,
            .templates = templates,
            .template_refs = template_refs,
            .diagnostics = diagnostics,
            .symbol_table = symbol_table,
            .views = &.{},
        };
    }
};

/// Access mode for a semantic pass — declares read/write behavior for conflict detection.
pub const PassAccess = struct {
    /// Pass reads table definitions (fields, FKs, indexes).
    reads_tables: bool = true,
    /// Pass modifies table definitions (adds/removes fields, FKs, indexes).
    writes_tables: bool = false,
    /// Pass adds or removes tables from the list.
    modifies_table_list: bool = false,
    /// Pass modifies field type inference (suffix_inference, type modifiers).
    writes_types: bool = false,
};

/// A semantic analysis pass that transforms the tables in PassContext.
pub const SemanticPass = struct {
    name: []const u8,
    run: *const fn (ctx: *PassContext) anyerror!void,
    depends_on: []const []const u8 = &.{},
    access: PassAccess = .{},
};

/// Default pass pipeline — order matters!
pub const DEFAULT_PASSES = [_]SemanticPass{
    .{ .name = "validate_template_types", .run = @import("pass/validate_template_types.zig").run, .depends_on = &.{}, .access = .{ .writes_tables = true } },
    .{ .name = "resolve_names", .run = @import("pass/resolve_names.zig").run, .depends_on = &.{"validate_template_types"}, .access = .{ .writes_tables = true } },
    .{ .name = "resolve_conditionals", .run = @import("pass/resolve_conditionals.zig").run, .depends_on = &.{"resolve_names"}, .access = .{ .writes_tables = true } },
    .{ .name = "autofk", .run = @import("pass/autofk.zig").run, .depends_on = &.{"resolve_conditionals"}, .access = .{ .modifies_table_list = true } },
    .{ .name = "suffix_inference", .run = @import("pass/suffix_inference.zig").run, .depends_on = &.{"autofk"}, .access = .{ .writes_types = true } },
    .{ .name = "validate", .run = @import("pass/validate.zig").run, .depends_on = &.{ "autofk", "suffix_inference" }, .access = .{ .reads_tables = true } },
    .{ .name = "validate_type_modifiers", .run = @import("pass/validate_type_modifiers.zig").run, .depends_on = &.{"suffix_inference"}, .access = .{ .reads_tables = true } },
    .{ .name = "validate_indexes", .run = @import("pass/validate_indexes.zig").run, .depends_on = &.{"autofk"}, .access = .{ .reads_tables = true } },
    // Validation passes (originally a single validate_schema.zig, split in v0.107.0):
    .{ .name = "validate_duplicates", .run = @import("pass/validate_duplicates.zig").run, .depends_on = &.{ "validate", "resolve_names" }, .access = .{ .reads_tables = true } },
    .{ .name = "validate_circular_fk", .run = @import("pass/validate_circular_fk.zig").run, .depends_on = &.{ "validate", "resolve_names" }, .access = .{ .reads_tables = true } },
    .{ .name = "validate_fk_targets", .run = @import("pass/validate_fk_targets.zig").run, .depends_on = &.{ "validate", "resolve_names" }, .access = .{ .reads_tables = true } },
    .{ .name = "validate_unused_templates", .run = @import("pass/validate_unused_templates.zig").run, .depends_on = &.{ "validate", "resolve_names" }, .access = .{ .reads_tables = true } },
    // FK field type compatibility (v0.133.0):
    .{ .name = "validate_fk_types", .run = @import("pass/validate_fk_types.zig").run, .depends_on = &.{ "validate", "resolve_names" }, .access = .{ .reads_tables = true } },
    // Cross-table index name collision detection (v0.125.0):
    .{ .name = "validate_index_names", .run = @import("pass/validate_index_names.zig").run, .depends_on = &.{"validate"}, .access = .{ .reads_tables = true } },
    // View validation (v0.192.0):
    .{ .name = "validate_views", .run = @import("pass/validate_views.zig").run, .depends_on = &.{ "validate", "resolve_names" }, .access = .{ .reads_tables = true } },
    // Template type conflict detection for tables (v0.198.0):
    .{ .name = "template_type_conflict", .run = @import("pass/template_type_conflict.zig").run, .depends_on = &.{ "resolve_names", "suffix_inference" }, .access = .{ .reads_tables = true } },
    // Unused custom type detection (v0.226.0):
    .{ .name = "validate_unused_enums", .run = @import("pass/validate_unused_enums.zig").run, .depends_on = &.{"resolve_names"}, .access = .{ .reads_tables = true } },
};

/// Validate dependency ordering at runtime (comptime safety check).
pub fn validateDependencyOrder(alloc: std.mem.Allocator) void {
    if (comptime std.debug.runtime_safety) {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        var seen_names = std.StringHashMap(void).init(arena.allocator());
        for (DEFAULT_PASSES) |pass| {
            for (pass.depends_on) |dep| {
                if (!seen_names.contains(dep)) {
                    std.debug.panic("SemanticPass '{s}' depends on '{s}' which has not run yet", .{ pass.name, dep });
                }
            }
            seen_names.put(pass.name, {}) catch {};
        }
    }
}

/// Check if pass `a` transitively depends on pass `b` (directly or indirectly).
pub fn transitivelyDependsOn(a_name: []const u8, b_name: []const u8) bool {
    if (std.mem.eql(u8, a_name, b_name)) return true;
    for (DEFAULT_PASSES) |pass| {
        if (std.mem.eql(u8, pass.name, a_name)) {
            for (pass.depends_on) |dep| {
                if (transitivelyDependsOn(dep, b_name)) return true;
            }
            return false;
        }
    }
    return false;
}

/// Validate that sequential passes don't have conflicting access patterns.
/// Two passes conflict if:
/// - Both write to tables (write-write conflict)
/// - One writes tables and the other reads but doesn't transitively depend on the writer
pub fn validatePassAccess(alloc: std.mem.Allocator) void {
    if (comptime std.debug.runtime_safety) {
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        var seen_writers = std.StringHashMap(PassAccess).init(arena.allocator());
        for (DEFAULT_PASSES) |pass| {
            // Check for write-write conflicts with earlier passes
            if (pass.access.writes_tables or pass.access.modifies_table_list or pass.access.writes_types) {
                var it = seen_writers.iterator();
                while (it.next()) |entry| {
                    const prev_name = entry.key_ptr.*;
                    const prev_access = entry.value_ptr.*;
                    // Check if current pass transitively depends on the previous writer
                    const depends = transitivelyDependsOn(pass.name, prev_name);
                    if (!depends and (prev_access.writes_tables and pass.access.writes_tables)) {
                        std.debug.panic(
                            "SemanticPass '{s}' writes tables but does not depend on '{s}' which also writes tables",
                            .{ pass.name, prev_name },
                        );
                    }
                }
            }
            // Track writers
            if (pass.access.writes_tables or pass.access.modifies_table_list or pass.access.writes_types) {
                seen_writers.put(pass.name, pass.access) catch {};
            }
        }
    }
}

// ─── Comptime Dependency Validation ──────────────────────────
// Validates at compile time that all dependency names in DEFAULT_PASSES
// actually exist as pass names. Catches typos and missing passes at compile time.

comptime {
    for (DEFAULT_PASSES) |pass| {
        for (pass.depends_on) |dep| {
            var found = false;
            for (DEFAULT_PASSES) |other| {
                if (std.mem.eql(u8, dep, other.name)) {
                    found = true;
                    break;
                }
            }
            if (!found) {
                @compileError(std.fmt.comptimePrint(
                    "SemanticPass '{s}' depends on '{s}' which does not exist in DEFAULT_PASSES",
                    .{ pass.name, dep },
                ));
            }
        }
    }
}
