const std = @import("std");
const ast_mod = @import("../types/ast.zig");
const resolved_ast = @import("../types/resolved_ast.zig");
const stats_mod = @import("stats.zig");

// ─── Schema Audit ────────────────────────────────────────────
//
// Analyzes a ResolvedAst and produces a prioritized list of
// actionable recommendations for schema quality improvements.

/// Severity level for audit findings.
pub const Severity = enum {
    critical,
    warning,
    info,
};

/// A single audit finding.
pub const AuditFinding = struct {
    severity: Severity,
    category: []const u8,
    message: []const u8,
    table: ?[]const u8 = null,
};

/// Full audit report.
pub const AuditReport = struct {
    findings: []const AuditFinding,
    stats: stats_mod.Stats,
    score: u8, // 0–100 health score
};

/// Run a full schema audit and return a report.
pub fn auditSchema(alloc: std.mem.Allocator, resolved: resolved_ast.ResolvedAst) AuditReport {
    var findings = std.ArrayList(AuditFinding).initCapacity(alloc, 16) catch return .{
        .findings = &.{},
        .stats = stats_mod.computeStats(resolved),
        .score = 100,
    };

    const s = stats_mod.computeStats(resolved);

    // Check each table
    for (resolved.tables) |table| {
        // 1. Missing primary key
        var has_pk = false;
        for (table.fields) |field| {
            for (field.modifiers) |mod| {
                if (mod.kind == .primary_key) {
                    has_pk = true;
                    break;
                }
            }
            if (has_pk) break;
        }
        if (!has_pk) {
            findings.append(alloc, .{
                .severity = .critical,
                .category = "no-pk",
                .message = "Table has no primary key",
                .table = table.name,
            }) catch {};
        }

        // 2. Missing timestamps
        var has_created = false;
        var has_updated = false;
        for (table.fields) |field| {
            if (std.mem.eql(u8, field.name, "created_at") or std.mem.eql(u8, field.name, "create_at")) {
                has_created = true;
            }
            if (std.mem.eql(u8, field.name, "updated_at") or std.mem.eql(u8, field.name, "update_at")) {
                has_updated = true;
            }
        }
        if (!has_created or !has_updated) {
            findings.append(alloc, .{
                .severity = .warning,
                .category = "no-timestamps",
                .message = if (!has_created and !has_updated)
                    "Table missing created_at and updated_at timestamps"
                else if (!has_created)
                    "Table missing created_at timestamp"
                else
                    "Table missing updated_at timestamp",
                .table = table.name,
            }) catch {};
        }

        // 3. No indexes at all
        if (table.indexes.len == 0 and table.fks.len == 0) {
            findings.append(alloc, .{
                .severity = .warning,
                .category = "no-index",
                .message = "Table has no indexes",
                .table = table.name,
            }) catch {};
        }

        // 4. FK columns without index
        var fk_cols_no_index = false;
        for (table.fields) |field| {
            if (field.fk != null) {
                // Check if this column has an index
                var col_indexed = false;
                for (table.indexes) |idx| {
                    for (idx.fields) |col| {
                        if (std.mem.eql(u8, col, field.name)) {
                            col_indexed = true;
                            break;
                        }
                    }
                    if (col_indexed) break;
                }
                if (!col_indexed) {
                    fk_cols_no_index = true;
                    break;
                }
            }
        }
        if (fk_cols_no_index) {
            findings.append(alloc, .{
                .severity = .warning,
                .category = "fk-no-index",
                .message = "Foreign key columns without supporting index",
                .table = table.name,
            }) catch {};
        }

        // 5. Wide table
        if (table.fields.len > 30) {
            findings.append(alloc, .{
                .severity = .info,
                .category = "wide-table",
                .message = "Table has more than 30 columns — consider splitting",
                .table = table.name,
            }) catch {};
        }

        // 6. No comments
        if (table.comment == null) {
            findings.append(alloc, .{
                .severity = .info,
                .category = "no-comment",
                .message = "Table has no comment/description",
                .table = table.name,
            }) catch {};
        }
    }

    // 7. Empty custom types (enum types with no values)
    for (resolved.custom_types) |ct| {
        if (ct.base == .enum_type and ct.base.enum_type.len == 0) {
            findings.append(alloc, .{
                .severity = .warning,
                .category = "enum-empty",
                .message = "Custom type has no enum values",
                .table = ct.name,
            }) catch {};
        }
    }

    // Compute health score (100 = perfect, deductions for findings)
    var score: i32 = 100;
    for (findings.items) |f| {
        score -= switch (f.severity) {
            .critical => 15,
            .warning => 5,
            .info => 1,
        };
    }
    if (score < 0) score = 0;

    return .{
        .findings = findings.toOwnedSlice(alloc) catch return .{
            .findings = &.{},
            .stats = s,
            .score = 100,
        },
        .stats = s,
        .score = @intCast(score),
    };
}

// ─── Output Formatting ───────────────────────────────────────

/// Format audit report as human-readable text.
pub fn formatAuditText(alloc: std.mem.Allocator, report: AuditReport) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();

    try aw.writer.writeAll("Schema Health Audit\n");
    try aw.writer.writeAll("═══════════════════\n\n");

    // Score
    const grade = if (report.score >= 90) "A" else if (report.score >= 75) "B" else if (report.score >= 60) "C" else if (report.score >= 40) "D" else "F";
    try aw.writer.print("Health Score: {d}/100 ({s})\n\n", .{ report.score, grade });

    // Summary stats
    const summary = try stats_mod.formatSummary(alloc, report.stats);
    defer alloc.free(summary);
    try aw.writer.print("{s}\n\n", .{summary});

    if (report.findings.len == 0) {
        try aw.writer.writeAll("✓ No issues found. Schema looks healthy!\n");
        return try aw.toOwnedSlice();
    }

    // Count by severity
    var criticals: usize = 0;
    var warnings: usize = 0;
    var infos: usize = 0;
    for (report.findings) |f| {
        switch (f.severity) {
            .critical => criticals += 1,
            .warning => warnings += 1,
            .info => infos += 1,
        }
    }

    try aw.writer.print("Found {d} issue(s): {d} critical, {d} warning(s), {d} info\n\n", .{ report.findings.len, criticals, warnings, infos });

    // Findings by severity
    inline for (&.{ Severity.critical, Severity.warning, Severity.info }) |sev| {
        const label = switch (sev) {
            .critical => "CRITICAL",
            .warning => "WARNING",
            .info => "INFO",
        };
        var found_any = false;
        for (report.findings) |f| {
            if (f.severity == sev) {
                if (!found_any) {
                    try aw.writer.print("[{s}]\n", .{label});
                    found_any = true;
                }
                const table_str = if (f.table) |t| t else "<schema>";
                try aw.writer.print("  • {s}: {s}\n", .{ table_str, f.message });
            }
        }
        if (found_any) try aw.writer.writeAll("\n");
    }

    // Recommendations
    try aw.writer.writeAll("Recommendations:\n");
    if (criticals > 0) {
        try aw.writer.writeAll("  1. Fix critical issues first (missing primary keys)\n");
    }
    if (warnings > 0) {
        try aw.writer.writeAll("  2. Address warnings (missing indexes, timestamps)\n");
    }
    if (infos > 0) {
        try aw.writer.writeAll("  3. Consider info items for schema documentation\n");
    }

    return try aw.toOwnedSlice();
}

/// Format audit report as JSON.
pub fn formatAuditJson(alloc: std.mem.Allocator, report: AuditReport) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(alloc);
    defer aw.deinit();
    try aw.writer.print("{{\"score\":{d},\"findings\":[", .{report.score});

    for (report.findings, 0..) |f, i| {
        if (i > 0) try aw.writer.writeAll(",");
        const sev_str = switch (f.severity) {
            .critical => "critical",
            .warning => "warning",
            .info => "info",
        };
        if (f.table) |t| {
            try aw.writer.print("{{\"severity\":\"{s}\",\"category\":\"{s}\",\"message\":\"{s}\",\"table\":\"{s}\"}}", .{ sev_str, f.category, f.message, t });
        } else {
            try aw.writer.print("{{\"severity\":\"{s}\",\"category\":\"{s}\",\"message\":\"{s}\",\"table\":null}}", .{ sev_str, f.category, f.message });
        }
    }

    try aw.writer.writeAll("]}");
    return try aw.toOwnedSlice();
}

// ─── Tests ──────────────────────────────────────────────────

const testing = std.testing;

test "auditSchema: empty schema" {
    const resolved = resolved_ast.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .custom_types = &.{},
        .sql_comments = &.{},
    };
    const report = auditSchema(testing.allocator, resolved);
    defer {
        testing.allocator.free(report.findings);
    }
    try testing.expectEqual(@as(usize, 0), report.findings.len);
    try testing.expectEqual(@as(u8, 100), report.score);
}

test "auditSchema: table without PK" {
    var field_buf: [1]ast_mod.Field = undefined;
    field_buf[0] = .{
        .name = "name",
        .type_info = .{ .simple = "s64" },
        .modifiers = &.{},
        .fk = null,
        .check = null,
        .default_val = null,
        .comment = null,
        .line_no = 1,
    };
    var table_buf: [1]resolved_ast.ResolvedTable = undefined;
    table_buf[0] = .{
        .name = "users",
        .fields = &field_buf,
        .fks = &.{},
        .indexes = &.{},
        .comment = null,
        .template_ref = null,
        .conditional_blocks = &.{},
        .engine = null,
        .line_no = 1,
    };
    const resolved = resolved_ast.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &table_buf,
        .views = &.{},
        .custom_types = &.{},
        .sql_comments = &.{},
    };
    const report = auditSchema(testing.allocator, resolved);
    defer {
        testing.allocator.free(report.findings);
    }
    try testing.expect(report.findings.len > 0);
    // Should find no-pk and no-timestamps at minimum
    var found_pk = false;
    for (report.findings) |f| {
        if (std.mem.eql(u8, f.category, "no-pk")) found_pk = true;
    }
    try testing.expect(found_pk);
    try testing.expect(report.score < 100);
}

test "formatAuditText: produces output" {
    const resolved = resolved_ast.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .custom_types = &.{},
        .sql_comments = &.{},
    };
    const report = auditSchema(testing.allocator, resolved);
    defer {
        testing.allocator.free(report.findings);
    }
    const text = try formatAuditText(testing.allocator, report);
    defer testing.allocator.free(text);
    try testing.expect(text.len > 0);
    // Should contain health score
    try testing.expect(std.mem.indexOf(u8, text, "Health Score") != null);
}

test "formatAuditJson: produces valid JSON" {
    const resolved = resolved_ast.ResolvedAst{
        .schema_name = null,
        .schema_charset = null,
        .tables = &.{},
        .views = &.{},
        .custom_types = &.{},
        .sql_comments = &.{},
    };
    const report = auditSchema(testing.allocator, resolved);
    defer {
        testing.allocator.free(report.findings);
    }
    const json = try formatAuditJson(testing.allocator, report);
    defer testing.allocator.free(json);
    try testing.expect(json.len > 0);
    try testing.expect(std.mem.indexOf(u8, json, "\"score\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"findings\"") != null);
}
