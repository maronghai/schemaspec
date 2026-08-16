const std = @import("std");
const ResolvedAst = @import("../../types/resolved_ast.zig").ResolvedAst;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const LintConfig = @import("../config.zig").LintConfig;
const LintResult = @import("../config.zig").LintResult;

// ─── Naming Rules ──────────────────────────────────────────────
// Rules that check naming conventions: snake_case, prefixes,
// FK naming, index naming, timestamp naming, enum value naming.

pub fn checkNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        if (!isSnakeCase(table.name)) {
            const msg = try std.fmt.allocPrint(alloc, "table name '{s}' should use snake_case", .{table.name});
            try results.append(alloc, .{
                .rule = "naming",
                .table = table.name,
                .message = msg,
                .severity = .info,
            });
        }
        for (table.fields) |field| {
            if (!isSnakeCase(field.name)) {
                const msg = try std.fmt.allocPrint(alloc, "column name '{s}' should use snake_case", .{field.name});
                try results.append(alloc, .{
                    .rule = "naming",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

pub fn checkNamingPrefix(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    const prefixes = [_][]const u8{ "tbl_", "t_", "tb_", "table_" };
    for (ast.tables) |table| {
        for (prefixes) |prefix| {
            if (table.name.len > prefix.len and std.mem.startsWith(u8, table.name, prefix)) {
                const msg = try std.fmt.allocPrint(alloc, "table name '{s}' uses anti-pattern prefix '{s}'", .{ table.name, prefix });
                try results.append(alloc, .{
                    .rule = "naming-prefix",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
                break;
            }
        }
    }
}

pub fn checkFkNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            // Check if field has a FK reference
            var has_fk = false;
            for (table.fks) |fk| {
                for (fk.fields) |col| {
                    if (std.mem.eql(u8, col, field.name)) {
                        has_fk = true;
                        break;
                    }
                }
                if (has_fk) break;
            }
            if (!has_fk) continue;

            // FK columns should end with _id
            if (!std.mem.endsWith(u8, field.name, "_id")) {
                const msg = try std.fmt.allocPrint(alloc, "FK column '{s}' should follow '<table>_id' naming convention", .{field.name});
                try results.append(alloc, .{
                    .rule = "fk-naming",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

pub fn checkIndexNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.indexes) |idx| {
            // Skip primary key and unique indexes (they have implicit names)
            if (idx.kind == .primary_key or idx.kind == .unique) continue;

            // Expected pattern: <table>_<col1>_[<col2>_...]_idx or <table>_<col1>_[<col2>_...]_key
            const expected_prefix = try std.fmt.allocPrint(alloc, "{s}_", .{table.name});
            defer alloc.free(expected_prefix);

            if (!std.mem.startsWith(u8, idx.name, expected_prefix)) {
                const msg = try std.fmt.allocPrint(alloc, "index '{s}' should follow '<table>_<columns>' naming convention", .{idx.name});
                try results.append(alloc, .{
                    .rule = "index-naming",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

pub fn checkTimestampNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (!field.type_info.isDatetime()) continue;

            // Acceptable timestamp column names
            const valid_names = [_][]const u8{ "created_at", "updated_at", "deleted_at", "expires_at", "started_at", "ended_at", "verified_at", "last_login_at" };
            var valid = false;
            for (valid_names) |vn| {
                if (std.mem.eql(u8, field.name, vn)) {
                    valid = true;
                    break;
                }
            }
            if (!valid) {
                // Check if it ends with _at or _date — these are acceptable
                if (std.mem.endsWith(u8, field.name, "_at") or std.mem.endsWith(u8, field.name, "_date")) {
                    continue;
                }
                const msg = try std.fmt.allocPrint(alloc, "datetime column '{s}' should follow '<event>_at' or '<event>_date' naming convention", .{field.name});
                try results.append(alloc, .{
                    .rule = "timestamp-naming",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

pub fn checkEnumValueNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        // Only check enum types (those with enum_type values)
        switch (ct.base) {
            .enum_type => |values| {
                for (values) |val| {
                    // Check if value contains lowercase characters
                    var has_lower = false;
                    for (val) |c| {
                        if (std.ascii.isLower(c)) {
                            has_lower = true;
                            break;
                        }
                    }
                    if (has_lower) {
                        const msg = try std.fmt.allocPrint(alloc, "enum value '{s}' in type '{s}' should use UPPER_CASE", .{ val, ct.name });
                        try results.append(alloc, .{
                            .rule = "enum-value-naming",
                            .table = ct.name,
                            .message = msg,
                            .severity = .info,
                        });
                    }
                }
            },
            else => {},
        }
    }
}

pub fn checkViewNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.views) |view| {
        // Check if view follows <entity>_view or v_<entity> convention
        const ends_with_view = std.mem.endsWith(u8, view.name, "_view");
        const starts_with_v_ = std.mem.startsWith(u8, view.name, "v_") and view.name.len > 2;

        if (!ends_with_view and !starts_with_v_) {
            const msg = try std.fmt.allocPrint(alloc, "view '{s}' should follow '<entity>_view' or 'v_<entity>' naming convention", .{view.name});
            try results.append(alloc, .{
                .rule = "view-naming",
                .table = view.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkColumnBooleanNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.tables) |table| {
        for (table.fields) |field| {
            if (!field.type_info.isBoolean()) continue;

            // Boolean columns should follow is_/has_/can_/was_/should_ prefix convention
            const valid_prefixes = [_][]const u8{ "is_", "has_", "can_", "was_", "should_", "will_", "did_" };
            var valid = false;
            for (valid_prefixes) |prefix| {
                if (std.mem.startsWith(u8, field.name, prefix)) {
                    valid = true;
                    break;
                }
            }
            if (!valid) {
                const msg = try std.fmt.allocPrint(alloc, "boolean column '{s}' should use 'is_/has_/can_' prefix for clarity", .{field.name});
                try results.append(alloc, .{
                    .rule = "column-boolean-naming",
                    .table = table.name,
                    .message = msg,
                    .severity = .info,
                });
            }
        }
    }
}

// ─── Helpers ──────────────────────────────────────────────────

pub fn isSnakeCase(name: []const u8) bool {
    if (name.len == 0) return false;
    // Must start with a lowercase letter
    if (!std.ascii.isLower(name[0])) return false;
    var prev_underscore = false;
    for (name) |c| {
        if (std.ascii.isUpper(c)) return false;
        if (c == '_') {
            if (prev_underscore) return false; // no consecutive underscores
            prev_underscore = true;
        } else {
            prev_underscore = false;
        }
    }
    // Must not end with underscore
    if (name[name.len - 1] == '_') return false;
    return true;
}

pub fn isUpperSnakeCase(name: []const u8) bool {
    var has_upper = false;
    for (name) |c| {
        if (std.ascii.isUpper(c)) has_upper = true;
        if (std.ascii.isLower(c)) return false;
    }
    return has_upper;
}

/// Check that custom type (`~`) names follow snake_case, symmetric with the
/// table/column snake_case convention enforced by `checkNaming`.
pub fn checkCustomTypeNaming(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    for (ast.custom_types) |ct| {
        if (!isSnakeCase(ct.name)) {
            const msg = try std.fmt.allocPrint(alloc, "custom type name '{s}' should use snake_case", .{ct.name});
            try results.append(alloc, .{
                .rule = "custom-type-naming",
                .table = ct.name,
                .message = msg,
                .severity = .info,
            });
        }
    }
}

pub fn checkCustomTypeNameTooLong(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, cfg: LintConfig) !void {
    for (ast.custom_types) |ct| {
        if (ct.name.len > cfg.column_name_max) {
            const msg = try std.fmt.allocPrint(alloc, "custom type name '{s}' is {d} chars (max: {d})", .{ ct.name, ct.name.len, cfg.column_name_max });
            try results.append(alloc, .{
                .rule = "custom-type-name-too-long",
                .table = ct.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}

/// Check that custom types (`~`) have unique names. Duplicate custom-type
/// definitions would collide in the generated SQL (e.g. two `CREATE TYPE`
/// statements with the same name) and confuse the type resolver, so this
/// closes the duplicate-detection symmetry gap already covered for tables
/// (`duplicate-column`), indexes (`duplicate-index`), and enum values
/// (`enum-value-duplicate`). Uses a StringHashMap to detect name collisions.
pub fn checkCustomTypeDuplicate(alloc: std.mem.Allocator, results: *std.ArrayList(LintResult), ast: ResolvedAst, _: LintConfig) !void {
    var seen = std.StringHashMap(void).init(alloc);
    defer seen.deinit();
    for (ast.custom_types) |ct| {
        const gop = try seen.getOrPut(ct.name);
        if (gop.found_existing) {
            const msg = try std.fmt.allocPrint(alloc, "custom type '{s}' is defined more than once", .{ct.name});
            try results.append(alloc, .{
                .rule = "custom-type-duplicate",
                .table = ct.name,
                .message = msg,
                .severity = .warning,
            });
        }
    }
}
