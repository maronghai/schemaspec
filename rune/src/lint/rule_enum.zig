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
            .count => "Table has more than 50 columns",
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
