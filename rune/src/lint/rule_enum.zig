const std = @import("std");

// ─── Lint Rule Enum ─────────────────────────────────────────
// Single source of truth for all lint rules.
// Extracted from lint/config.zig for single-responsibility.

/// Enumeration of all lint rules. Provides a single source of truth for rule names,
/// config field mapping, and enable/disable logic.
pub const LintRule = enum {
    no_pk,
    naming,
    no_index_fk,
    no_timestamps,
    wide_table,
    enum_case,
    count,
    fk_cascade,
    nullable_pk,
    orphan_type,
    index_unused,
    circular_fk,
    duplicate_index,
    empty_table,
    table_comment,
    serial_type,
    table_name_length,
    column_length,
    index_column_missing,
    naming_prefix,
    fk_naming,
    bool_default,
    view_no_select,
    column_default_required,
    index_naming,
    nullable_column_default,
    timestamp_naming,
    enum_value_naming,
    fk_null,
    cross_dialect_types,
    view_no_alias,
    fk_self_reference,
    enum_empty,
    view_naming,
    duplicate_column,
    view_select_star,
    enum_value_duplicate,
    column_boolean_naming,
    fk_depth,
    unique_constraint,
    composite_pk,
    fk_duplicate,
    reserved_word,
    column_type_portability,
    index_missing_fk_columns,

    /// Human-readable rule name for config files and output.
    pub fn name(self: LintRule) []const u8 {
        return switch (self) {
            .no_pk => "no-pk",
            .naming => "naming",
            .no_index_fk => "no-index-fk",
            .no_timestamps => "no-timestamps",
            .wide_table => "wide-table",
            .enum_case => "enum-case",
            .count => "count",
            .fk_cascade => "fk-cascade",
            .nullable_pk => "nullable-pk",
            .orphan_type => "orphan-type",
            .index_unused => "index-unused",
            .circular_fk => "circular-fk",
            .duplicate_index => "duplicate-index",
            .empty_table => "empty-table",
            .table_comment => "table-comment",
            .serial_type => "serial-type",
            .table_name_length => "table-name-length",
            .column_length => "column-length",
            .index_column_missing => "index-column-missing",
            .naming_prefix => "naming-prefix",
            .fk_naming => "fk-naming",
            .bool_default => "bool-default",
            .view_no_select => "view-no-select",
            .column_default_required => "column-default-required",
            .index_naming => "index-naming",
            .nullable_column_default => "nullable-column-default",
            .timestamp_naming => "timestamp-naming",
            .enum_value_naming => "enum-value-naming",
            .fk_null => "fk-null",
            .cross_dialect_types => "cross-dialect-types",
            .view_no_alias => "view-no-alias",
            .fk_self_reference => "fk-self-reference",
            .enum_empty => "enum-empty",
            .view_naming => "view-naming",
            .duplicate_column => "duplicate-column",
            .view_select_star => "view-select-star",
            .enum_value_duplicate => "enum-value-duplicate",
            .column_boolean_naming => "column-boolean-naming",
            .fk_depth => "fk-depth",
            .unique_constraint => "unique-constraint",
            .composite_pk => "composite-pk",
            .fk_duplicate => "fk-duplicate",
            .reserved_word => "reserved-word",
            .column_type_portability => "column-type-portability",
            .index_missing_fk_columns => "index-missing-fk-columns",
        };
    }

    /// Parse a rule name string into a LintRule enum value.
    pub fn fromName(n: []const u8) ?LintRule {
        inline for (std.meta.fields(LintRule)) |field| {
            if (std.mem.eql(u8, @field(LintRule, field.name).name(), n)) {
                return @field(LintRule, field.name);
            }
        }
        return null;
    }

    /// Check if this rule supports auto-fix via `rune lint --fix`.
    pub fn isFixable(self: LintRule) bool {
        return switch (self) {
            .no_pk => true,
            .no_timestamps => true,
            .empty_table => true,
            .serial_type => true,
            .bool_default => true,
            .nullable_column_default => true,
            .duplicate_index => true,
            .column_default_required => true,
            .no_index_fk => true,
            .duplicate_column => true,
            .index_missing_fk_columns => true,
            .view_select_star => false,
            .enum_value_duplicate => false,
            .column_boolean_naming => false,
            .fk_depth => false,
            else => false,
        };
    }

    /// Human-readable description for `--show-rules` and config generation.
    pub fn description(self: LintRule) []const u8 {
        return switch (self) {
            .no_pk => "Table has no primary key",
            .naming => "Table names should be singular (CamelCase → snake_case)",
            .no_index_fk => "Foreign key columns without an index",
            .no_timestamps => "Table missing create_at/update_at timestamps",
            .wide_table => "Table has more than 30 columns",
            .enum_case => "Custom type enum values should be UPPER_CASE",
            .count => "Table has fewer than minimum field count",
            .fk_cascade => "Foreign key without explicit ON DELETE/UPDATE actions",
            .nullable_pk => "Primary key column is nullable",
            .orphan_type => "Custom type defined but not used by any table",
            .index_unused => "Index on column not used in any FK",
            .circular_fk => "Circular foreign key dependency between tables",
            .duplicate_index => "Duplicate index on the same column(s)",
            .empty_table => "Table has no columns",
            .table_comment => "Table missing comment/description",
            .serial_type => "PostgreSQL-specific serial type (use n++ for portability)",
            .table_name_length => "Table name exceeds max length (default: 64)",
            .column_length => "String column without explicit length",
            .index_column_missing => "Index references column not in table",
            .naming_prefix => "Table name uses anti-pattern prefix (tbl_, t_, tb_)",
            .fk_naming => "FK column doesn't follow <table>_id convention",
            .bool_default => "Boolean column without explicit default",
            .view_no_select => "View has no SELECT statement",
            .column_default_required => "Non-PK non-nullable column without DEFAULT",
            .index_naming => "Index name doesn't follow <table>_<columns> convention",
            .nullable_column_default => "Nullable non-PK column without DEFAULT",
            .timestamp_naming => "Datetime column should be created_at/updated_at",
            .enum_value_naming => "Enum values should be UPPER_CASE",
            .fk_null => "Foreign key column is nullable",
            .cross_dialect_types => "MySQL-specific types not portable to other dialects",
            .view_no_alias => "View SELECT uses expressions without column aliases",
            .fk_self_reference => "Foreign key references the same table (self-reference)",
            .enum_empty => "Custom type enum has no values",
            .view_naming => "View name doesn't follow <entity>_view or v_<entity> convention",
            .duplicate_column => "Table has columns with the same name",
            .view_select_star => "View uses SELECT * (prefer explicit columns for portability)",
            .enum_value_duplicate => "Custom type has duplicate enum values",
            .column_boolean_naming => "Boolean column should use is_/has_/can_ prefix",
            .fk_depth => "Foreign key reference chain exceeds 3 levels",
            .unique_constraint => "UNIQUE constraint on column that is already the primary key",
            .composite_pk => "Multiple auto-increment primary keys in one table",
            .fk_duplicate => "Multiple foreign keys reference the same target table",
            .reserved_word => "Table or column name uses a SQL reserved word",
            .column_type_portability => "Column type may not be portable across dialects",
            .index_missing_fk_columns => "Table has foreign keys but no index on FK columns",
        };
    }

    /// SARIF severity level for this rule. Used by formatSarif to emit rule metadata.
    pub fn lintLevel(self: LintRule) []const u8 {
        return switch (self) {
            .no_pk => "error",
            .naming => "note",
            .no_index_fk => "warning",
            .no_timestamps => "note",
            .wide_table => "warning",
            .enum_case => "note",
            .count => "note",
            .fk_cascade => "note",
            .nullable_pk => "warning",
            .orphan_type => "note",
            .index_unused => "note",
            .circular_fk => "warning",
            .duplicate_index => "warning",
            .empty_table => "warning",
            .table_comment => "note",
            .serial_type => "note",
            .table_name_length => "note",
            .column_length => "note",
            .index_column_missing => "warning",
            .naming_prefix => "note",
            .fk_naming => "note",
            .bool_default => "note",
            .view_no_select => "note",
            .column_default_required => "warning",
            .index_naming => "note",
            .nullable_column_default => "note",
            .timestamp_naming => "note",
            .enum_value_naming => "note",
            .fk_null => "warning",
            .cross_dialect_types => "warning",
            .view_no_alias => "note",
            .fk_self_reference => "note",
            .enum_empty => "warning",
            .view_naming => "note",
            .duplicate_column => "warning",
            .view_select_star => "note",
            .enum_value_duplicate => "warning",
            .column_boolean_naming => "note",
            .fk_depth => "warning",
            .unique_constraint => "note",
            .composite_pk => "warning",
            .fk_duplicate => "note",
            .reserved_word => "warning",
            .column_type_portability => "note",
            .index_missing_fk_columns => "warning",
        };
    }
};

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "LintRule: all rules have names" {
    inline for (std.meta.fields(LintRule)) |field| {
        const rule = @field(LintRule, field.name);
        const rule_name = rule.name();
        try testing.expect(rule_name.len > 0);
    }
}

test "LintRule: fromName roundtrip" {
    inline for (std.meta.fields(LintRule)) |field| {
        const rule = @field(LintRule, field.name);
        const rule_name = rule.name();
        const parsed = LintRule.fromName(rule_name);
        try testing.expect(parsed != null);
        try testing.expectEqual(rule, parsed.?);
    }
}

test "LintRule: all rules have descriptions" {
    inline for (std.meta.fields(LintRule)) |field| {
        const rule = @field(LintRule, field.name);
        const desc = rule.description();
        try testing.expect(desc.len > 0);
    }
}

test "LintRule: isFixable returns bool" {
    inline for (std.meta.fields(LintRule)) |field| {
        const rule = @field(LintRule, field.name);
        _ = rule.isFixable();
    }
}

test "LintRule: lintLevel returns valid level" {
    inline for (std.meta.fields(LintRule)) |field| {
        const rule = @field(LintRule, field.name);
        const level = rule.lintLevel();
        try testing.expect(level.len > 0);
        // Must be one of the three SARIF severity levels
        try testing.expect(
            std.mem.eql(u8, level, "error") or
                std.mem.eql(u8, level, "warning") or
                std.mem.eql(u8, level, "note"),
        );
    }
}
