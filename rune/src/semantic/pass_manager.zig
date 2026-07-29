const std = @import("std");
pub const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const diag = @import("../semantic/diagnostic.zig");
const symbol_table_mod = @import("../types/symbol_table.zig");
const ResolvedTable = resolved_ast.ResolvedTable;
const Template = ast_mod.Template;

// ─── Pass Manager ──────────────────────────────────────────────
// Extracted from semantic.zig (was analyzer.zig) for single-responsibility.

/// Shared mutable context passed to each semantic pass.
pub const PassContext = struct {
    alloc: std.mem.Allocator,
    tables: *std.ArrayList(ResolvedTable),
    schema: ?ast_mod.Schema,
    templates: std.StringHashMap(*const Template) = undefined,
    /// Set of template names referenced by tables (template_ref) or other templates (parents).
    /// Populated by the analyzer before passes run. Used by validate_schema for unused template detection.
    template_refs: std.StringHashMap(void) = undefined,
    diagnostics: *diag.DiagnosticCollector = undefined,
    symbol_table: symbol_table_mod.SymbolTable = undefined,
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
    .{ .name = "autofk", .run = @import("pass/autofk.zig").run, .depends_on = &.{}, .access = .{ .modifies_table_list = true } },
    .{ .name = "suffix_inference", .run = @import("pass/suffix_inference.zig").run, .depends_on = &.{"autofk"}, .access = .{ .writes_types = true } },
    .{ .name = "validate", .run = @import("pass/validate.zig").run, .depends_on = &.{ "autofk", "suffix_inference" }, .access = .{ .reads_tables = true } },
    .{ .name = "validate_type_modifiers", .run = @import("pass/validate_type_modifiers.zig").run, .depends_on = &.{"suffix_inference"}, .access = .{ .reads_tables = true } },
    .{ .name = "validate_indexes", .run = @import("pass/validate_indexes.zig").run, .depends_on = &.{"autofk"}, .access = .{ .reads_tables = true } },
    .{ .name = "validate_schema", .run = @import("pass/validate_schema.zig").run, .depends_on = &.{ "validate", "resolve_names" }, .access = .{ .reads_tables = true } },
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

/// Detect write-write conflicts between passes that could break reordering.
/// Two passes conflict if both write to the same resource and neither depends on the other.
/// Returns a list of conflicting pass name pairs. Caller must free the returned slice.
pub fn detectConflicts(alloc: std.mem.Allocator) ![][2][]const u8 {
    var result = std.ArrayList([2][]const u8).initCapacity(alloc, 8) catch return error.OutOfMemory;
    for (DEFAULT_PASSES, 0..) |a, i| {
        for (DEFAULT_PASSES[i + 1 ..]) |b| {
            if (hasConflict(a, b)) {
                if (!dependsOn(a, b) and !dependsOn(b, a)) {
                    if (!transitiveDependsOn(alloc, a, b) and !transitiveDependsOn(alloc, b, a)) {
                        result.append(alloc, .{ a.name, b.name }) catch return error.OutOfMemory;
                    }
                }
            }
        }
    }
    return try result.toOwnedSlice(alloc);
}

/// Check if pass a has a direct dependency on pass b.
pub fn dependsOn(a: SemanticPass, b: SemanticPass) bool {
    for (a.depends_on) |dep| {
        if (std.mem.eql(u8, dep, b.name)) return true;
    }
    return false;
}

/// Check if two passes have a write-write conflict on the same resource.
pub fn hasConflict(a: SemanticPass, b: SemanticPass) bool {
    if (a.access.writes_tables and b.access.writes_tables) return true;
    if (a.access.modifies_table_list and b.access.modifies_table_list) return true;
    if (a.access.writes_types and b.access.writes_types) return true;
    return false;
}

/// Check if there is a transitive dependency from a to b (through intermediate passes).
fn transitiveDependsOn(alloc: std.mem.Allocator, a: SemanticPass, b: SemanticPass) bool {
    var visited = std.BufSet.init(alloc);
    defer visited.deinit();
    var frontier = std.ArrayList([]const u8).initCapacity(alloc, 8) catch return false;
    defer frontier.deinit(alloc);
    for (a.depends_on) |dep| {
        frontier.append(alloc, dep) catch return false;
        visited.insert(dep) catch return false;
    }
    while (frontier.items.len > 0) {
        const current = frontier.pop() orelse break;
        if (std.mem.eql(u8, current, b.name)) return true;
        for (DEFAULT_PASSES) |pass| {
            if (std.mem.eql(u8, pass.name, current)) {
                for (pass.depends_on) |dep| {
                    if (!visited.contains(dep)) {
                        frontier.append(alloc, dep) catch return false;
                        visited.insert(dep) catch return false;
                    }
                }
            }
        }
    }
    return false;
}

/// Parallelizable group: passes that can run concurrently (no dependency, no write-write conflict).
/// Returns groups of pass indices that can run in parallel.
/// Groups are auto-computed from the dependency graph — no manual maintenance needed.
pub fn getParallelGroups() []const ParallelGroup {
    // Greedy graph coloring: assign each pass to the earliest group where it
    // can run concurrently with all passes already in that group.
    var group_count: usize = 0;
    // group_passes[i] = list of pass indices assigned to group i
    var group_passes: [DEFAULT_PASSES.len][DEFAULT_PASSES.len]usize = undefined;
    var group_sizes: [DEFAULT_PASSES.len]usize = undefined;

    for (DEFAULT_PASSES, 0..) |pass, i| {
        var placed = false;
        // Try each existing group
        for (0..group_count) |g| {
            var conflict = false;
            for (0..group_sizes[g]) |p| {
                const other = DEFAULT_PASSES[group_passes[g][p]];
                if (!canRunConcurrently(pass, other)) {
                    conflict = true;
                    break;
                }
            }
            if (!conflict) {
                group_passes[g][group_sizes[g]] = i;
                group_sizes[g] += 1;
                placed = true;
                break;
            }
        }
        // Create a new group if no existing group works
        if (!placed) {
            group_passes[group_count][0] = i;
            group_sizes[group_count] = 1;
            group_count += 1;
        }
    }

    // Build result — snapshot group_passes into stack-allocated slices.
    var result: [DEFAULT_PASSES.len]ParallelGroup = undefined;
    for (0..group_count) |g| {
        result[g] = .{
            .passes = group_passes[g][0..group_sizes[g]],
            .label = "", // labels are now dynamic; callers use .passes directly
        };
    }
    return result[0..group_count];
}

pub const ParallelGroup = struct {
    passes: []const usize,
    label: []const u8,
};

/// Check if two passes can run concurrently (no dependency, no write-write conflict).
pub fn canRunConcurrently(a: SemanticPass, b: SemanticPass) bool {
    // Check dependency
    for (a.depends_on) |dep| {
        if (std.mem.eql(u8, dep, b.name)) return false;
    }
    for (b.depends_on) |dep| {
        if (std.mem.eql(u8, dep, a.name)) return false;
    }
    // Check write-write conflict on tables
    if ((a.access.writes_tables and b.access.writes_tables) or
        (a.access.modifies_table_list and b.access.modifies_table_list) or
        (a.access.writes_types and b.access.writes_types))
    {
        return false;
    }
    return true;
}
