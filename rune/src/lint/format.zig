const std = @import("std");
const LintResult = @import("config.zig").LintResult;
const LintRule = @import("config.zig").LintRule;
const RULE_INFO = @import("rules.zig").RULE_INFO;

// ─── Lint Output Formatters ──────────────────────────────────
// Human-readable text, machine-readable JSON, and CI/CD SARIF output.

/// Write a JSON-escaped string (without surrounding quotes).
fn writeJsonString(writer: anytype, str: []const u8) !void {
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            else => try writer.writeByte(c),
        }
    }
}

/// Format lint results as a one-line summary.
pub fn formatSummary(alloc: std.mem.Allocator, results: []const LintResult) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    if (results.len == 0) {
        try aw.writer.writeAll("0 warning(s), 0 info(s)\n");
        return try aw.toOwnedSlice();
    }

    var warnings: usize = 0;
    var infos: usize = 0;
    for (results) |r| {
        if (r.severity == .warning) warnings += 1 else infos += 1;
    }
    try aw.writer.print("{d} warning(s), {d} info(s)\n", .{ warnings, infos });
    return try aw.toOwnedSlice();
}

/// Format lint results as human-readable text.
pub fn formatText(alloc: std.mem.Allocator, results: []const LintResult, use_color: bool) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    if (results.len == 0) {
        try aw.writer.writeAll("No lint issues found.\n");
        return try aw.toOwnedSlice();
    }

    var warnings: usize = 0;
    var infos: usize = 0;
    var fixable: usize = 0;
    for (results) |r| {
        const severity_str = if (r.severity == .warning) "warning" else "info";
        const prefix = if (use_color) "\x1b[33m" else "";
        const suffix = if (use_color) "\x1b[0m" else "";
        // Show "(fixable)" indicator next to fixable rules
        const fixable_suffix = blk: {
            if (LintRule.fromName(r.rule)) |rule| {
                if (rule.isFixable()) break :blk if (use_color) " \x1b[32m(fixable)\x1b[0m" else " (fixable)";
            }
            break :blk "";
        };
        try aw.writer.print("{s}{s}{s}: [{s}] {s}: {s}{s}\n", .{
            prefix, severity_str, suffix, r.rule, r.table, r.message, fixable_suffix,
        });
        if (r.severity == .warning) warnings += 1 else infos += 1;
        if (LintRule.fromName(r.rule)) |rule| {
            if (rule.isFixable()) fixable += 1;
        }
    }
    if (fixable > 0) {
        try aw.writer.print("\n{s}Lint summary: {d} warning(s), {d} info(s), {d} fixable\n", .{
            if (use_color) "\x1b[1m" else "", warnings, infos, fixable,
        });
    } else {
        try aw.writer.print("\n{s}Lint summary: {d} warning(s), {d} info(s)\n", .{
            if (use_color) "\x1b[1m" else "", warnings, infos,
        });
    }
    if (use_color) try aw.writer.writeAll("\x1b[0m");

    return try aw.toOwnedSlice();
}

/// Format lint results as JSON (machine-readable).
pub fn formatJson(alloc: std.mem.Allocator, results: []const LintResult) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    try aw.writer.writeAll("{\"issues\":[");
    for (results, 0..) |r, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"rule\":\"");
        try writeJsonString(&aw.writer, r.rule);
        try aw.writer.writeAll("\",\"table\":\"");
        try writeJsonString(&aw.writer, r.table);
        try aw.writer.writeAll("\",\"message\":\"");
        try writeJsonString(&aw.writer, r.message);
        try aw.writer.writeAll("\",\"severity\":\"");
        try aw.writer.writeAll(if (r.severity == .warning) "warning" else "info");
        try aw.writer.writeAll("\"}");
    }
    const has_warnings = for (results) |r| {
        if (r.severity == .warning) break true;
    } else false;
    try aw.writer.writeAll("],\"count\":");
    var count_buf: [20]u8 = undefined;
    const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{results.len}) catch "0";
    try aw.writer.writeAll(count_str);
    try aw.writer.writeAll(",\"has_warnings\":");
    try aw.writer.writeAll(if (has_warnings) "true" else "false");
    try aw.writer.writeAll("}");

    return try aw.toOwnedSlice();
}

/// Format lint results as SARIF 2.1.0 (CI/CD integration).
pub fn formatSarif(alloc: std.mem.Allocator, results: []const LintResult, version_str: []const u8, file_path: ?[]const u8) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    try aw.writer.writeAll("{\"$schema\":\"https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json\",\"version\":\"2.1.0\",\"runs\":[{\"tool\":{\"driver\":{\"name\":\"rune\",\"version\":\"");
    try writeJsonString(&aw.writer, version_str);
    try aw.writer.writeAll("\",\"rules\":[");

    // Derive rules from RULE_INFO — single source of truth for all rule metadata.
    // SARIF requires rule metadata in the output; we emit all rules so consumers
    // can filter by any rule ID without missing entries.
    for (RULE_INFO, 0..) |info, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"id\":\"");
        try writeJsonString(&aw.writer, info.rule.name());
        try aw.writer.writeAll("\",\"name\":\"");
        try writeJsonString(&aw.writer, info.rule.name());
        try aw.writer.writeAll("\",\"shortDescription\":{\"text\":\"");
        try writeJsonString(&aw.writer, info.description);
        try aw.writer.writeAll("\"},\"defaultConfiguration\":{\"level\":\"");
        try writeJsonString(&aw.writer, info.rule.lintLevel());
        try aw.writer.writeAll("\"}}");
    }

    try aw.writer.writeAll("]},\"results\":[");

    for (results, 0..) |r, i| {
        if (i > 0) try aw.writer.writeAll(",");
        try aw.writer.writeAll("{\"ruleId\":\"");
        try writeJsonString(&aw.writer, r.rule);
        try aw.writer.writeAll("\",\"level\":\"");
        try aw.writer.writeAll(if (r.severity == .warning) "warning" else "note");
        try aw.writer.writeAll("\",\"message\":{\"text\":\"");
        try writeJsonString(&aw.writer, r.message);
        try aw.writer.writeAll("\"},\"locations\":[{\"physicalLocation\":{\"artifactLocation\":{\"uri\":\"");
        if (file_path) |fp| {
            try writeJsonString(&aw.writer, fp);
        } else {
            try aw.writer.writeAll("schema.ss");
        }
        try aw.writer.writeAll("\"},\"region\":{\"startLine\":1}}}],\"fingerprints\":{\"run/rune/v1\":\"");
        try writeJsonString(&aw.writer, r.rule);
        try aw.writer.writeAll(":");
        try writeJsonString(&aw.writer, r.table);
        try aw.writer.writeAll("\"}}");
    }

    try aw.writer.writeAll("],\"artifacts\":[{\"location\":{\"uri\":\"");
    if (file_path) |fp| {
        try writeJsonString(&aw.writer, fp);
    } else {
        try aw.writer.writeAll("schema.ss");
    }
    try aw.writer.writeAll("\"}}]}]}");

    return try aw.toOwnedSlice();
}
