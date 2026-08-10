const std = @import("std");
pub const rule_enum = @import("rule_enum.zig");
pub const LintRule = rule_enum.LintRule;

// ─── Lint Config ─────────────────────────────────────────────
// Configuration types and TOML config file parsing.
//
// Adding a new lint rule requires ONLY adding the variant to LintRule enum.
// No changes needed in config.zig — RuleSet, isRuleEnabled, applyLintRules,
// and setRuleEnabled are all data-driven via @intFromEnum(LintRule).

pub const LintSeverity = enum { warning, info };

pub const LintResult = struct {
    rule: []const u8,
    table: []const u8,
    message: []const u8,
    severity: LintSeverity,
};

// ─── RuleSet: data-driven rule enable/disable ────────────────

const RULE_COUNT = @typeInfo(LintRule).@"enum".fields.len;

/// Data-driven set of enabled/disabled lint rules.
/// Indexed by LintRule enum ordinal — no per-rule boolean fields.
pub const RuleSet = struct {
    enabled: [RULE_COUNT]bool = initAllEnabled(),

    fn initAllEnabled() [RULE_COUNT]bool {
        return [_]bool{true} ** RULE_COUNT;
    }

    /// Check if a rule is enabled.
    pub fn isEnabled(self: RuleSet, rule: LintRule) bool {
        return self.enabled[@intFromEnum(rule)];
    }

    /// Set a rule's enabled state.
    pub fn setEnabled(self: *RuleSet, rule: LintRule, val: bool) void {
        self.enabled[@intFromEnum(rule)] = val;
    }

    /// Disable all rules.
    pub fn disableAll(self: *RuleSet) void {
        self.enabled = [_]bool{false} ** RULE_COUNT;
    }

    /// Disable all rules except the specified one.
    pub fn disableAllExcept(self: *RuleSet, except: LintRule) void {
        self.disableAll();
        self.setEnabled(except, true);
    }
};

/// Check if a lint rule is enabled in the given config.
pub fn isRuleEnabled(rule: LintRule, cfg: LintConfig) bool {
    return cfg.rules.isEnabled(rule);
}

pub const LintConfig = struct {
    rules: RuleSet = .{},
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
        cfg.rules.disableAll();
        for (enabled) |rule| {
            if (LintRule.fromName(rule)) |r| {
                cfg.rules.setEnabled(r, true);
            }
        }
    }

    // Disable listed rules
    if (rules.disabled) |disabled| {
        for (disabled) |rule| {
            if (LintRule.fromName(rule)) |r| {
                cfg.rules.setEnabled(r, false);
            }
        }
    }

    // Apply thresholds
    if (rules.thresholds.wide_table_max) |max| cfg.wide_table_max = max;
    if (rules.thresholds.count_min) |min| cfg.count_min = min;
    if (rules.thresholds.table_name_max) |max| cfg.table_name_max = max;

    return cfg;
}

// ─── Unit Tests ──────────────────────────────────────────────

const testing = std.testing;

test "RuleSet: all rules enabled by default" {
    const rs = RuleSet{};
    inline for (std.meta.fields(LintRule)) |field| {
        const rule = @field(LintRule, field.name);
        try testing.expect(rs.isEnabled(rule));
    }
}

test "RuleSet: disableAll disables all rules" {
    var rs = RuleSet{};
    rs.disableAll();
    inline for (std.meta.fields(LintRule)) |field| {
        const rule = @field(LintRule, field.name);
        try testing.expect(!rs.isEnabled(rule));
    }
}

test "RuleSet: setEnabled toggles individual rules" {
    var rs = RuleSet{};
    rs.setEnabled(.no_pk, false);
    try testing.expect(!rs.isEnabled(.no_pk));
    // Other rules remain enabled
    try testing.expect(rs.isEnabled(.naming));
    try testing.expect(rs.isEnabled(.fk_cascade));
}

test "RuleSet: isRuleEnabled delegates to rules.isEnabled" {
    var cfg = LintConfig{};
    try testing.expect(isRuleEnabled(.no_pk, cfg));
    cfg.rules.setEnabled(.no_pk, false);
    try testing.expect(!isRuleEnabled(.no_pk, cfg));
}

test "applyLintRules: enabled list disables all then enables listed" {
    const base = LintConfig{};
    const rules = LintRulesConfig{
        .enabled = &.{"no-pk"},
        .disabled = &.{"naming"},
    };
    const cfg = applyLintRules(base, rules);
    try testing.expect(cfg.rules.isEnabled(.no_pk));
    try testing.expect(!cfg.rules.isEnabled(.naming));
    try testing.expect(!cfg.rules.isEnabled(.fk_cascade));
}

test "applyLintRules: disabled list removes specific rules" {
    const base = LintConfig{};
    const rules = LintRulesConfig{
        .disabled = &.{"no-pk"},
    };
    const cfg = applyLintRules(base, rules);
    try testing.expect(!cfg.rules.isEnabled(.no_pk));
    try testing.expect(cfg.rules.isEnabled(.naming));
}

test "applyLintRules: thresholds are applied" {
    const base = LintConfig{};
    const rules = LintRulesConfig{
        .thresholds = .{ .wide_table_max = 50, .count_min = 5 },
    };
    const cfg = applyLintRules(base, rules);
    try testing.expectEqual(@as(usize, 50), cfg.wide_table_max);
    try testing.expectEqual(@as(usize, 5), cfg.count_min);
}
