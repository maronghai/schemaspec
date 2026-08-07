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
    wide_table_max: usize = 30,
    count_min: usize = 2,
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
                    result.thresholds.wide_table_max = std.fmt.parseInt(usize, val_str, 10) catch null;
                } else if (std.mem.eql(u8, key, "count_min")) {
                    result.thresholds.count_min = std.fmt.parseInt(usize, val_str, 10) catch null;
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
        cfg.check_pk = false;
        cfg.check_naming = false;
        cfg.check_fk_index = false;
        cfg.check_timestamps = false;
        cfg.check_wide_table = false;
        cfg.check_enum_case = false;
        cfg.check_count = false;
        cfg.check_fk_cascade = false;
        cfg.check_nullable_pk = false;
        cfg.check_orphan_type = false;
        cfg.check_index_unused = false;
        cfg.check_circular_fk = false;
        for (enabled) |rule| {
            if (std.mem.eql(u8, rule, "no-pk")) cfg.check_pk = true;
            if (std.mem.eql(u8, rule, "naming")) cfg.check_naming = true;
            if (std.mem.eql(u8, rule, "no-index-fk")) cfg.check_fk_index = true;
            if (std.mem.eql(u8, rule, "no-timestamps")) cfg.check_timestamps = true;
            if (std.mem.eql(u8, rule, "wide-table")) cfg.check_wide_table = true;
            if (std.mem.eql(u8, rule, "enum-case")) cfg.check_enum_case = true;
            if (std.mem.eql(u8, rule, "count")) cfg.check_count = true;
            if (std.mem.eql(u8, rule, "fk-cascade")) cfg.check_fk_cascade = true;
            if (std.mem.eql(u8, rule, "nullable-pk")) cfg.check_nullable_pk = true;
            if (std.mem.eql(u8, rule, "orphan-type")) cfg.check_orphan_type = true;
            if (std.mem.eql(u8, rule, "index-unused")) cfg.check_index_unused = true;
            if (std.mem.eql(u8, rule, "circular-fk")) cfg.check_circular_fk = true;
        }
    }

    // Disable listed rules
    if (rules.disabled) |disabled| {
        for (disabled) |rule| {
            if (std.mem.eql(u8, rule, "no-pk")) cfg.check_pk = false;
            if (std.mem.eql(u8, rule, "naming")) cfg.check_naming = false;
            if (std.mem.eql(u8, rule, "no-index-fk")) cfg.check_fk_index = false;
            if (std.mem.eql(u8, rule, "no-timestamps")) cfg.check_timestamps = false;
            if (std.mem.eql(u8, rule, "wide-table")) cfg.check_wide_table = false;
            if (std.mem.eql(u8, rule, "enum-case")) cfg.check_enum_case = false;
            if (std.mem.eql(u8, rule, "count")) cfg.check_count = false;
            if (std.mem.eql(u8, rule, "fk-cascade")) cfg.check_fk_cascade = false;
            if (std.mem.eql(u8, rule, "nullable-pk")) cfg.check_nullable_pk = false;
            if (std.mem.eql(u8, rule, "orphan-type")) cfg.check_orphan_type = false;
            if (std.mem.eql(u8, rule, "index-unused")) cfg.check_index_unused = false;
            if (std.mem.eql(u8, rule, "circular-fk")) cfg.check_circular_fk = false;
        }
    }

    // Apply thresholds
    if (rules.thresholds.wide_table_max) |max| cfg.wide_table_max = max;
    if (rules.thresholds.count_min) |min| cfg.count_min = min;

    return cfg;
}
