const std = @import("std");
const ResolvedAst = @import("../types/resolved_ast.zig").ResolvedAst;
const LintConfig = @import("config.zig").LintConfig;
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;
const isRuleEnabled = @import("config.zig").isRuleEnabled;

// ─── Lint Rules ───────────────────────────────────────────────
// Data-driven dispatch table. Each handler is defined in a
// category module under lint/handlers/. Adding a new rule =
// add entry to RULES + implement handler in the appropriate module.

const structural = @import("handlers/structural.zig");
const naming = @import("handlers/naming.zig");
const validation = @import("handlers/validation.zig");
const compat = @import("handlers/compat.zig");
const fk_rules = @import("handlers/fk.zig");
const index_rules = @import("handlers/index.zig");
const view_rules = @import("handlers/view.zig");
const enum_rules = @import("handlers/enum.zig");
const portability_rules = @import("handlers/portability.zig");

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
    .{ .rule = .column_name_too_long, .handler = structural.checkColumnNameTooLong },
    .{ .rule = .index_columns_max, .handler = structural.checkIndexColumnsMax },
    .{ .rule = .column_no_comment, .handler = structural.checkColumnNoComment },
    // Naming rules
    .{ .rule = .naming, .handler = naming.checkNaming },
    .{ .rule = .naming_prefix, .handler = naming.checkNamingPrefix },
    .{ .rule = .fk_naming, .handler = naming.checkFkNaming },
    .{ .rule = .index_naming, .handler = naming.checkIndexNaming },
    .{ .rule = .timestamp_naming, .handler = naming.checkTimestampNaming },
    .{ .rule = .enum_value_naming, .handler = naming.checkEnumValueNaming },
    .{ .rule = .column_boolean_naming, .handler = naming.checkColumnBooleanNaming },
    .{ .rule = .custom_type_naming, .handler = naming.checkCustomTypeNaming },
    .{ .rule = .custom_type_name_too_long, .handler = naming.checkCustomTypeNameTooLong },
    .{ .rule = .custom_type_duplicate, .handler = naming.checkCustomTypeDuplicate },
    // FK validation rules (moved to fk.zig)
    .{ .rule = .no_index_fk, .handler = fk_rules.checkNoIndexFk },
    .{ .rule = .fk_cascade, .handler = fk_rules.checkFkCascade },
    .{ .rule = .fk_null, .handler = fk_rules.checkFkNull },
    .{ .rule = .fk_self_reference, .handler = fk_rules.checkFkSelfReference },
    .{ .rule = .circular_fk, .handler = fk_rules.checkCircularFk },
    .{ .rule = .fk_depth, .handler = fk_rules.checkFkDepth },
    .{ .rule = .fk_duplicate, .handler = fk_rules.checkFkDuplicate },
    .{ .rule = .fk_column_type_mismatch, .handler = fk_rules.checkFkColumnTypeMismatch },
    .{ .rule = .fk_on_delete_cascade, .handler = fk_rules.checkFkOnDeleteCascade },
    .{ .rule = .fk_missing_index, .handler = fk_rules.checkFkMissingIndex },
    .{ .rule = .fk_unidirectional, .handler = fk_rules.checkFkUnidirectional },
    .{ .rule = .fk_to_non_unique, .handler = fk_rules.checkFkToNonUnique },
    // Index validation rules (moved to index.zig)
    .{ .rule = .index_unused, .handler = index_rules.checkIndexUnused },
    .{ .rule = .duplicate_index, .handler = index_rules.checkDuplicateIndex },
    .{ .rule = .index_column_missing, .handler = index_rules.checkIndexColumnMissing },
    .{ .rule = .index_redundant_with_pk, .handler = index_rules.checkIndexRedundantWithPk },
    .{ .rule = .index_redundant_with_fk, .handler = index_rules.checkIndexRedundantWithFk },
    .{ .rule = .table_no_index, .handler = index_rules.checkTableNoIndex },
    .{ .rule = .index_name_too_long, .handler = index_rules.checkIndexNameTooLong },
    // View validation rules (moved to view.zig)
    .{ .rule = .view_no_select, .handler = view_rules.checkViewNoSelect },
    .{ .rule = .view_no_alias, .handler = view_rules.checkViewNoAlias },
    .{ .rule = .view_select_star, .handler = view_rules.checkViewSelectStar },
    .{ .rule = .view_naming, .handler = naming.checkViewNaming },
    .{ .rule = .view_dependency_cycle, .handler = view_rules.checkViewDependencyCycle },
    .{ .rule = .view_no_comment, .handler = view_rules.checkViewNoComment },
    .{ .rule = .view_name_too_long, .handler = view_rules.checkViewNameTooLong },
    .{ .rule = .view_select_missing_where, .handler = view_rules.checkViewSelectMissingWhere },
    // Enum validation rules (moved to enum.zig)
    .{ .rule = .enum_case, .handler = enum_rules.checkEnumCase },
    .{ .rule = .orphan_type, .handler = enum_rules.checkOrphanType },
    .{ .rule = .enum_empty, .handler = enum_rules.checkEnumEmpty },
    .{ .rule = .enum_value_duplicate, .handler = enum_rules.checkEnumValueDuplicate },
    .{ .rule = .enum_value_too_long, .handler = enum_rules.checkEnumValueTooLong },
    // General validation rules (staying in validation.zig)
    .{ .rule = .nullable_pk, .handler = validation.checkNullablePk },
    .{ .rule = .bool_default, .handler = validation.checkBoolDefault },
    .{ .rule = .column_default_required, .handler = validation.checkColumnDefaultRequired },
    .{ .rule = .nullable_column_default, .handler = validation.checkNullableColumnDefault },
    .{ .rule = .duplicate_column, .handler = validation.checkDuplicateColumn },
    .{ .rule = .unique_constraint, .handler = validation.checkUniqueConstraint },
    .{ .rule = .composite_pk, .handler = validation.checkCompositePk },
    .{ .rule = .column_unique_nullable, .handler = validation.checkColumnUniqueNullable },
    .{ .rule = .column_auto_increment_type, .handler = validation.checkColumnAutoIncrementType },
    .{ .rule = .column_unique_naming, .handler = validation.checkColumnUniqueNaming },
    .{ .rule = .column_auto_increment_nullable, .handler = validation.checkColumnAutoIncrementNullable },
    .{ .rule = .column_bad_default, .handler = validation.checkColumnBadDefault },
    .{ .rule = .column_default_function_check, .handler = validation.checkColumnDefaultFunctionCheck },
    .{ .rule = .auto_increment_without_pk, .handler = validation.checkAutoIncrementWithoutPk },
    // Compatibility rules
    .{ .rule = .serial_type, .handler = compat.checkSerialType },
    .{ .rule = .column_length, .handler = compat.checkColumnLength },
    .{ .rule = .cross_dialect_types, .handler = compat.checkCrossDialectTypes },
    // Portability & quality rules
    .{ .rule = .reserved_word, .handler = portability_rules.checkReservedWord },
    .{ .rule = .column_type_portability, .handler = portability_rules.checkColumnTypePortability },
    .{ .rule = .index_missing_fk_columns, .handler = portability_rules.checkIndexMissingFkColumns },
    .{ .rule = .timestamp_type, .handler = structural.checkTimestampType },
    .{ .rule = .pk_not_first, .handler = structural.checkPkNotFirst },
};

/// Run all enabled lint checks on a resolved schema.
pub fn runAll(alloc: std.mem.Allocator, ast: ResolvedAst, cfg: LintConfig) !std.ArrayList(LintResult) {
    var results = try std.ArrayList(LintResult).initCapacity(alloc, 8);
    errdefer results.deinit(alloc);

    for (RULES) |entry| {
        if (isRuleEnabled(entry.rule, cfg)) {
            try entry.handler(alloc, &results, ast, cfg);
        }
    }

    return results;
}

// ─── Helpers (re-exported for backward compatibility) ──────────

pub const isSnakeCase = naming.isSnakeCase;

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

test "RULES covers all LintRule variants" {
    try std.testing.expectEqual(std.meta.fields(LintRule).len, RULES.len);
}
