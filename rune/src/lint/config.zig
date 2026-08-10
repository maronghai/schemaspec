const std = @import("std");

// ─── Lint Config ─────────────────────────────────────────────
// Configuration types and TOML config file parsing.

pub const LintSeverity = enum { warning, info };

pub const LintResult = struct {
    rule: []const u8,
    table: []const u8,
    message: []const u8,
    severity: LintSeverity,
};

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

    /// Check if this rule is enabled in the given config.
    pub fn isEnabled(self: LintRule, cfg: LintConfig) bool {
        return switch (self) {
            .no_pk => cfg.check_pk,
            .naming => cfg.check_naming,
            .no_index_fk => cfg.check_fk_index,
            .no_timestamps => cfg.check_timestamps,
            .wide_table => cfg.check_wide_table,
            .enum_case => cfg.check_enum_case,
            .count => cfg.check_count,
            .fk_cascade => cfg.check_fk_cascade,
            .nullable_pk => cfg.check_nullable_pk,
            .orphan_type => cfg.check_orphan_type,
            .index_unused => cfg.check_index_unused,
            .circular_fk => cfg.check_circular_fk,
            .duplicate_index => cfg.check_duplicate_index,
            .empty_table => cfg.check_empty_table,
            .table_comment => cfg.check_table_comment,
            .serial_type => cfg.check_serial_type,
            .table_name_length => cfg.check_table_name_length,
            .column_length => cfg.check_column_length,
            .index_column_missing => cfg.check_index_column_missing,
            .naming_prefix => cfg.check_naming_prefix,
            .fk_naming => cfg.check_fk_naming,
            .bool_default => cfg.check_bool_default,
            .view_no_select => cfg.check_view_no_select,
            .column_default_required => cfg.check_column_default_required,
            .index_naming => cfg.check_index_naming,
            .nullable_column_default => cfg.check_nullable_column_default,
            .timestamp_naming => cfg.check_timestamp_naming,
            .enum_value_naming => cfg.check_enum_value_naming,
            .fk_null => cfg.check_fk_null,
            .cross_dialect_types => cfg.check_cross_dialect_types,
        };
    }

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
            .index_column_missing => true,
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
        };
    }
};

pub const LintConfig = struct {
    check_pk: bool = true,
    check_naming: bool = true,
    check_fk_index: bool = true,
    check_timestamps: bool = true,
    check_wide_table: bool = true,
    check_enum_case: bool = true,
    check_count: bool = true,
    check_fk_cascade: bool = true,
    check_nullable_pk: bool = true,
    check_orphan_type: bool = true,
    check_index_unused: bool = true,
    check_circular_fk: bool = true,
    check_duplicate_index: bool = true,
    check_empty_table: bool = true,
    check_table_comment: bool = true,
    check_serial_type: bool = true,
    check_table_name_length: bool = true,
    check_column_length: bool = true,
    check_index_column_missing: bool = true,
    check_naming_prefix: bool = true,
    check_fk_naming: bool = true,
    check_bool_default: bool = true,
    check_view_no_select: bool = true,
    check_column_default_required: bool = true,
    check_index_naming: bool = true,
    check_nullable_column_default: bool = true,
    check_timestamp_naming: bool = true,
    check_enum_value_naming: bool = true,
    check_fk_null: bool = true,
    check_cross_dialect_types: bool = true,
    wide_table_max: usize = 30,
    count_min: usize = 2,
    table_name_max: usize = 64,
};

// ─── Diff-aware Lint ─────────────────────────────────────────

pub const LintDiffResult = struct {
    old_results: []const LintResult,
    new_results: []const LintResult,
    added: []const LintResult,
};

/// Compare lint results between two schemas, returning only newly introduced issues.
pub fn lintDiff(old_results: []const LintResult, new_results: []const LintResult, alloc: std.mem.Allocator) !LintDiffResult {
    var added = try std.ArrayList(LintResult).initCapacity(alloc, new_results.len);
    errdefer added.deinit(alloc);

    for (new_results) |new_r| {
        var found = false;
        for (old_results) |old_r| {
            if (std.mem.eql(u8, old_r.rule, new_r.rule) and
                std.mem.eql(u8, old_r.table, new_r.table) and
                std.mem.eql(u8, old_r.message, new_r.message))
            {
                found = true;
                break;
            }
        }
        if (!found) {
            try added.append(alloc, new_r);
        }
    }

    return .{
        .old_results = old_results,
        .new_results = new_results,
        .added = try added.toOwnedSlice(alloc),
    };
}

// ─── Lint Config File ────────────────────────────────────────

pub const LintRulesConfig = struct {
    enabled: ?[]const []const u8 = null,
    disabled: ?[]const []const u8 = null,
    severity_overrides: []const SeverityOverride = &.{},
    thresholds: Thresholds = .{},

    pub const SeverityOverride = struct {
        rule: []const u8,
        severity: []const u8,
    };

    pub const Thresholds = struct {
        wide_table_max: ?usize = null,
        count_min: ?usize = null,
        table_name_max: ?usize = null,
    };
};

/// Parse a rune-lint.toml rules file.
pub fn parseLintRules(alloc: std.mem.Allocator, data: []const u8) !LintRulesConfig {
    var result = LintRulesConfig{};
    var enabled_list = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    errdefer enabled_list.deinit(alloc);
    var disabled_list = try std.ArrayList([]const u8).initCapacity(alloc, 4);
    errdefer disabled_list.deinit(alloc);
    var severity_list = try std.ArrayList(LintRulesConfig.SeverityOverride).initCapacity(alloc, 4);
    errdefer severity_list.deinit(alloc);
    var in_severity = false;
    var in_thresholds = false;

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (std.mem.eql(u8, line, "[lint]")) {
            in_severity = false;
            in_thresholds = false;
            continue;
        }
        if (std.mem.eql(u8, line, "[lint.severity]")) {
            in_severity = true;
            in_thresholds = false;
            continue;
        }
        if (std.mem.eql(u8, line, "[lint.thresholds]")) {
            in_thresholds = true;
            in_severity = false;
            continue;
        }

        if (in_severity) {
            if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
                const key = std.mem.trim(u8, line[0..eq_pos], " \t");
                const val = std.mem.trim(u8, line[eq_pos + 1 ..], " \t\"'");
                try severity_list.append(alloc, .{ .rule = key, .severity = val });
            }
            continue;
        }

        if (in_thresholds) {
            if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
                const key = std.mem.trim(u8, line[0..eq_pos], " \t");
                const val_str = std.mem.trim(u8, line[eq_pos + 1 ..], " \t");
                if (std.mem.eql(u8, key, "wide_table_max")) {
                    result.thresholds.wide_table_max = std.fmt.parseInt(usize, val_str, 10) catch return error.InvalidConfigValue;
                } else if (std.mem.eql(u8, key, "count_min")) {
                    result.thresholds.count_min = std.fmt.parseInt(usize, val_str, 10) catch return error.InvalidConfigValue;
                } else if (std.mem.eql(u8, key, "table_name_max")) {
                    result.thresholds.table_name_max = std.fmt.parseInt(usize, val_str, 10) catch return error.InvalidConfigValue;
                }
            }
            continue;
        }

        if (std.mem.indexOf(u8, line, "=")) |eq_pos| {
            const key = std.mem.trim(u8, line[0..eq_pos], " \t");
            const val = std.mem.trim(u8, line[eq_pos + 1 ..], " \t\"'");

            if (std.mem.eql(u8, key, "enabled")) {
                var items = std.mem.splitScalar(u8, val, ',');
                while (items.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " \t\"'");
                    if (trimmed.len > 0) {
                        try enabled_list.append(alloc, trimmed);
                    }
                }
            } else if (std.mem.eql(u8, key, "disabled")) {
                var items = std.mem.splitScalar(u8, val, ',');
                while (items.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " \t\"'");
                    if (trimmed.len > 0) {
                        try disabled_list.append(alloc, trimmed);
                    }
                }
            }
        }
    }

    if (enabled_list.items.len > 0) {
        result.enabled = try enabled_list.toOwnedSlice(alloc);
    }
    if (disabled_list.items.len > 0) {
        result.disabled = try disabled_list.toOwnedSlice(alloc);
    }
    if (severity_list.items.len > 0) {
        result.severity_overrides = try severity_list.toOwnedSlice(alloc);
    }

    return result;
}

/// Apply lint rules config to LintConfig — filters and overrides based on rules file.
pub fn applyLintRules(base: LintConfig, rules: LintRulesConfig) LintConfig {
    var cfg = base;

    // If enabled list is set, disable everything first, then enable listed rules
    if (rules.enabled) |enabled| {
        cfg = LintConfig{
            .check_pk = false,
            .check_naming = false,
            .check_fk_index = false,
            .check_timestamps = false,
            .check_wide_table = false,
            .check_enum_case = false,
            .check_count = false,
            .check_fk_cascade = false,
            .check_nullable_pk = false,
            .check_orphan_type = false,
            .check_index_unused = false,
            .check_circular_fk = false,
            .check_duplicate_index = false,
            .check_empty_table = false,
            .check_table_comment = false,
            .check_serial_type = false,
            .check_table_name_length = false,
            .check_column_length = false,
            .check_index_column_missing = false,
            .check_naming_prefix = false,
            .check_fk_naming = false,
            .check_bool_default = false,
            .check_view_no_select = false,
            .check_column_default_required = false,
            .check_index_naming = false,
            .check_nullable_column_default = false,
            .check_timestamp_naming = false,
            .check_enum_value_naming = false,
            .check_fk_null = false,
            .check_cross_dialect_types = false,
            .wide_table_max = base.wide_table_max,
            .count_min = base.count_min,
            .table_name_max = base.table_name_max,
        };
        for (enabled) |rule| {
            if (LintRule.fromName(rule)) |r| {
                cfg = setRuleEnabled(cfg, r, true);
            }
        }
    }

    // Disable listed rules
    if (rules.disabled) |disabled| {
        for (disabled) |rule| {
            if (LintRule.fromName(rule)) |r| {
                cfg = setRuleEnabled(cfg, r, false);
            }
        }
    }

    // Apply thresholds
    if (rules.thresholds.wide_table_max) |max| cfg.wide_table_max = max;
    if (rules.thresholds.count_min) |min| cfg.count_min = min;
    if (rules.thresholds.table_name_max) |max| cfg.table_name_max = max;

    return cfg;
}

/// Set a rule's enabled state in a LintConfig.
fn setRuleEnabled(cfg: LintConfig, rule: LintRule, enabled: bool) LintConfig {
    var c = cfg;
    switch (rule) {
        .no_pk => c.check_pk = enabled,
        .naming => c.check_naming = enabled,
        .no_index_fk => c.check_fk_index = enabled,
        .no_timestamps => c.check_timestamps = enabled,
        .wide_table => c.check_wide_table = enabled,
        .enum_case => c.check_enum_case = enabled,
        .count => c.check_count = enabled,
        .fk_cascade => c.check_fk_cascade = enabled,
        .nullable_pk => c.check_nullable_pk = enabled,
        .orphan_type => c.check_orphan_type = enabled,
        .index_unused => c.check_index_unused = enabled,
        .circular_fk => c.check_circular_fk = enabled,
        .duplicate_index => c.check_duplicate_index = enabled,
        .empty_table => c.check_empty_table = enabled,
        .table_comment => c.check_table_comment = enabled,
        .serial_type => c.check_serial_type = enabled,
        .table_name_length => c.check_table_name_length = enabled,
        .column_length => c.check_column_length = enabled,
        .index_column_missing => c.check_index_column_missing = enabled,
        .naming_prefix => c.check_naming_prefix = enabled,
        .fk_naming => c.check_fk_naming = enabled,
        .bool_default => c.check_bool_default = enabled,
        .view_no_select => c.check_view_no_select = enabled,
        .column_default_required => c.check_column_default_required = enabled,
        .index_naming => c.check_index_naming = enabled,
        .nullable_column_default => c.check_nullable_column_default = enabled,
        .timestamp_naming => c.check_timestamp_naming = enabled,
        .enum_value_naming => c.check_enum_value_naming = enabled,
        .fk_null => c.check_fk_null = enabled,
        .cross_dialect_types => c.check_cross_dialect_types = enabled,
    }
    return c;
}
