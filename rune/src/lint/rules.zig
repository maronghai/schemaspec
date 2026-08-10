const std = @import("std");
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const LintConfig = @import("config.zig").LintConfig;
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;

// ─── Lint Rules ───────────────────────────────────────────────
// Data-driven dispatch table. Each handler is defined in a
// category module under lint/handlers/. Adding a new rule =
// add entry to RULES + implement handler in the appropriate module.

const structural = @import("handlers/structural.zig");
const naming = @import("handlers/naming.zig");
const validation = @import("handlers/validation.zig");
const compat = @import("handlers/compat.zig");

/// Metadata for a lint rule — single source of truth for `--show-rules` and `--init`.
pub const RuleInfo = struct {
    rule: LintRule,
    description: []const u8,
    fixable: bool,
};

/// All rule metadata, derived from LintRule enum. Use this instead of hardcoded lists.
pub const RULE_INFO = initRuleInfo();

fn initRuleInfo() [std.meta.fields(LintRule).len]RuleInfo {
    var info: [std.meta.fields(LintRule).len]RuleInfo = undefined;
    inline for (std.meta.fields(LintRule), 0..) |field, i| {
        const r: LintRule = @enumFromInt(field.value);
        info[i] = .{
            .rule = r,
            .description = r.description(),
            .fixable = r.isFixable(),
        };
    }
    return info;
}

/// Handler function signature for data-driven dispatch.
const RuleHandler = *const fn (alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) anyerror!void;

/// Dispatch table entry: rule enum + handler function.
const RuleEntry = struct {
    rule: LintRule,
    handler: RuleHandler,
};

/// Table-driven rule dispatch — eliminates 22 repetitive guard-then-call blocks.
/// Adding a new rule = add entry to RULES + implement handler in appropriate module.
const RULES = [_]RuleEntry{
    // Structural rules
    .{ .rule = .no_pk, .handler = structural.checkNoPk },
    .{ .rule = .no_timestamps, .handler = structural.checkNoTimestamps },
    .{ .rule = .wide_table, .handler = structural.checkWideTable },
    .{ .rule = .count, .handler = structural.checkCount },
    .{ .rule = .empty_table, .handler = structural.checkEmptyTable },
    .{ .rule = .table_comment, .handler = structural.checkTableComment },
    .{ .rule = .table_name_length, .handler = structural.checkTableNameLength },
    // Naming rules
    .{ .rule = .naming, .handler = naming.checkNaming },
    .{ .rule = .naming_prefix, .handler = naming.checkNamingPrefix },
    .{ .rule = .fk_naming, .handler = naming.checkFkNaming },
    .{ .rule = .index_naming, .handler = naming.checkIndexNaming },
    .{ .rule = .timestamp_naming, .handler = naming.checkTimestampNaming },
    .{ .rule = .enum_value_naming, .handler = naming.checkEnumValueNaming },
    // Validation rules
    .{ .rule = .no_index_fk, .handler = validation.checkNoIndexFk },
    .{ .rule = .fk_cascade, .handler = validation.checkFkCascade },
    .{ .rule = .nullable_pk, .handler = validation.checkNullablePk },
    .{ .rule = .enum_case, .handler = validation.checkEnumCase },
    .{ .rule = .orphan_type, .handler = validation.checkOrphanType },
    .{ .rule = .index_unused, .handler = validation.checkIndexUnused },
    .{ .rule = .circular_fk, .handler = validation.checkCircularFk },
    .{ .rule = .duplicate_index, .handler = validation.checkDuplicateIndex },
    .{ .rule = .index_column_missing, .handler = validation.checkIndexColumnMissing },
    .{ .rule = .bool_default, .handler = validation.checkBoolDefault },
    .{ .rule = .view_no_select, .handler = validation.checkViewNoSelect },
    .{ .rule = .column_default_required, .handler = validation.checkColumnDefaultRequired },
    .{ .rule = .nullable_column_default, .handler = validation.checkNullableColumnDefault },
    .{ .rule = .fk_null, .handler = validation.checkFkNull },
    // Compatibility rules
    .{ .rule = .serial_type, .handler = compat.checkSerialType },
    .{ .rule = .column_length, .handler = compat.checkColumnLength },
    .{ .rule = .cross_dialect_types, .handler = compat.checkCrossDialectTypes },
};

/// Run all enabled lint checks on a resolved schema.
pub fn runAll(alloc: std.mem.Allocator, ast: ResolvedAst, cfg: LintConfig) !std.ArrayList(LintResult) {
    var results = try std.ArrayList(LintResult).initCapacity(alloc, 8);
    errdefer results.deinit(alloc);

    for (RULES) |entry| {
        if (entry.rule.isEnabled(cfg)) {
            try entry.handler(alloc, &results, ast, cfg);
        }
    }

    return results;
}

// ─── Helpers (re-exported for backward compatibility) ──────────

pub const isSnakeCase = naming.isSnakeCase;
pub const isUpperSnakeCase = naming.isUpperSnakeCase;

// ─── Tests ──────────────────────────────────────────────────

test "isSnakeCase valid" {
    try std.testing.expect(isSnakeCase("hello"));
    try std.testing.expect(isSnakeCase("snake_case"));
    try std.testing.expect(isSnakeCase("a"));
    try std.testing.expect(isSnakeCase("my_table_name"));
    try std.testing.expect(isSnakeCase("field1"));
}

test "isSnakeCase invalid" {
    // Consecutive underscores
    try std.testing.expect(!isSnakeCase("a__b"));
    // Starts with digit
    try std.testing.expect(!isSnakeCase("123abc"));
    // Leading underscore
    try std.testing.expect(!isSnakeCase("_leading"));
    // Trailing underscore
    try std.testing.expect(!isSnakeCase("trailing_"));
    // Uppercase
    try std.testing.expect(!isSnakeCase("CamelCase"));
    try std.testing.expect(!isSnakeCase("UPPER"));
    // Empty
    try std.testing.expect(!isSnakeCase(""));
}

// ─── RULE_INFO Consistency Tests ──────────────────────────────

test "RULE_INFO covers all LintRule enum values" {
    // RULE_INFO length must match enum field count
    try std.testing.expectEqual(std.meta.fields(LintRule).len, RULE_INFO.len);
}

test "RULE_INFO entries have non-empty descriptions" {
    for (RULE_INFO) |info| {
        try std.testing.expect(info.description.len > 0);
        try std.testing.expect(info.rule.name().len > 0);
    }
}

test "RULE_INFO fixable flags match LintRule.isFixable" {
    for (RULE_INFO) |info| {
        try std.testing.expectEqual(info.rule.isFixable(), info.fixable);
    }
}

test "RULE_INFO descriptions match LintRule.description" {
    for (RULE_INFO) |info| {
        try std.testing.expectEqualStrings(info.rule.description(), info.description);
    }
}
