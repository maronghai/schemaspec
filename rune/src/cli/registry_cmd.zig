const std = @import("std");
const io_mod = @import("../io.zig");
const fmt = @import("../diagnostic/format.zig");
const time_epoch = std.time.epoch;
fn getCurrentDateString(io: std.Io) ![]const u8 {
    const ts = std.Io.Clock.real.now(io);
    const seconds = ts.toSeconds();
    const epoch_secs = time_epoch.EpochSeconds{ .secs = @intCast(seconds) };
    const epoch_day = epoch_secs.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const year = year_day.year;
    const month = month_day.month.numeric();
    const day = month_day.day_index + 1; // day_index is 0-based
    const alloc = std.heap.page_allocator;
    return try std.fmt.allocPrint(alloc, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, day });
}



// Registry directory: ~/.rune/registry/
// Structure:
//   ~/.rune/registry/
//     meta.json          # Registry metadata (version, updated)
//     templates/
//       <name>/
//         template.ss    # Template content
//         meta.json      # Template metadata

const TemplateMeta = struct {
    name: []const u8,
    description: []const u8,
    version: []const u8,
    author: ?[]const u8,
    tags: []const []const u8,
    dependencies: []const []const u8,
    min_rune_version: ?[]const u8,
    created_at: []const u8,
    updated_at: []const u8,
};

const RegistryMeta = struct {
    version: u32 = 1,
    updated_at: []const u8,
};

fn getRegistryPath(alloc: std.mem.Allocator, home_dir: []const u8) ![]const u8 {
    const path = try std.fs.path.join(alloc, &.{ home_dir, ".rune", "registry" });
    return path;
}

fn getTemplatesPath(alloc: std.mem.Allocator, home_dir: []const u8) ![]const u8 {
    const path = try std.fs.path.join(alloc, &.{ home_dir, ".rune", "registry", "templates" });
    return path;
}

fn getTemplatePath(alloc: std.mem.Allocator, home_dir: []const u8, name: []const u8) ![]const u8 {
    const templates_dir = try getTemplatesPath(alloc, home_dir);
    const path = try std.fs.path.join(alloc, &.{ templates_dir, name });
    return path;
}

fn getTemplateFilePath(alloc: std.mem.Allocator, home_dir: []const u8, name: []const u8) ![]const u8 {
    const template_dir = try getTemplatePath(alloc, home_dir, name);
    const path = try std.fs.path.join(alloc, &.{ template_dir, "template.ss" });
    return path;
}

fn getTemplateMetaPath(alloc: std.mem.Allocator, home_dir: []const u8, name: []const u8) ![]const u8 {
    const template_dir = try getTemplatePath(alloc, home_dir, name);
    const path = try std.fs.path.join(alloc, &.{ template_dir, "meta.json" });
    return path;
}

fn getRegistryMetaPath(alloc: std.mem.Allocator, home_dir: []const u8) ![]const u8 {
    const path = try std.fs.path.join(alloc, &.{ home_dir, ".rune", "registry", "meta.json" });
    return path;
}

fn ensureRegistryDirs(io: std.Io, alloc: std.mem.Allocator, home_dir: []const u8) !void {
    const registry_dir = try getRegistryPath(alloc, home_dir);
    const templates_dir = try getTemplatesPath(alloc, home_dir);
    const cwd = std.Io.Dir.cwd();
    try std.Io.Dir.createDirPath(cwd, io, registry_dir);
    try std.Io.Dir.createDirPath(cwd, io, templates_dir);
}

fn writeRegistryMeta(io: std.Io, alloc: std.mem.Allocator, home_dir: []const u8) !void {
    const meta_path = try getRegistryMetaPath(alloc, home_dir);
    const date_str = try getCurrentDateString(io);
    const meta = RegistryMeta{
        .version = 1,
        .updated_at = date_str,
    };
    const json = try std.json.Stringify.valueAlloc(alloc, meta, .{ .whitespace = .indent_2 });
    defer alloc.free(json);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = meta_path,
        .data = json,
    });
}

fn readRegistryMeta(io: std.Io, alloc: std.mem.Allocator, home_dir: []const u8) !RegistryMeta {
    const meta_path = try getRegistryMetaPath(alloc, home_dir);
    const content = try std.Io.Dir.cwd().readFileAlloc(io, meta_path, alloc, .unlimited);
    const parsed = try std.json.parseFromSlice(RegistryMeta, alloc, content, .{});
    return parsed.value;
}

fn writeTemplateMeta(io: std.Io, alloc: std.mem.Allocator, home_dir: []const u8, name: []const u8, meta: TemplateMeta) !void {
    const meta_path = try getTemplateMetaPath(alloc, home_dir, name);
    const json = try std.json.Stringify.valueAlloc(alloc, meta, .{ .whitespace = .indent_2 });
    defer alloc.free(json);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = meta_path,
        .data = json,
    });
}

fn readTemplateMeta(io: std.Io, alloc: std.mem.Allocator, home_dir: []const u8, name: []const u8) !TemplateMeta {
    const meta_path = try getTemplateMetaPath(alloc, home_dir, name);
    const content = try std.Io.Dir.cwd().readFileAlloc(io, meta_path, alloc, .unlimited);
    const parsed = try std.json.parseFromSlice(TemplateMeta, alloc, content, .{});
    return parsed.value;
}

fn readTemplateContent(io: std.Io, alloc: std.mem.Allocator, home_dir: []const u8, name: []const u8) ![]const u8 {
    const template_path = try getTemplateFilePath(alloc, home_dir, name);
    return try std.Io.Dir.cwd().readFileAlloc(io, template_path, alloc, .unlimited);
}

pub fn handleRegistry(io: std.Io, alloc: std.mem.Allocator, cmd: anytype, home_dir: []const u8) !void {
    const subcmd = cmd.subcmd;

    // Handle init subcommand
    if (std.mem.eql(u8, subcmd, "init")) {
        try ensureRegistryDirs(io, alloc, home_dir);
        try writeRegistryMeta(io, alloc, home_dir);
        fmt.printOk("Initialized registry at ~/.rune/registry/");
        return;
    }

    // For other commands, ensure registry exists
    const registry_dir = try getRegistryPath(alloc, home_dir);
        if (std.Io.Dir.cwd().statFile(io, registry_dir, .{})) |_| {
        // Registry exists
    } else |err| switch (err) {
        error.FileNotFound => {
            fmt.printError("registry", "Registry not initialized. Run 'rune registry init' first.");
            return error.RegistryNotInitialized;
        },
        else => |e| return e,
    }

    // Handle add subcommand
    if (std.mem.eql(u8, subcmd, "add")) {
        const name = cmd.name orelse {
            fmt.printError("registry", "Missing template name. Usage: rune registry add <name> <path>");
            return error.RegistryMissingName;
        };
        const path = cmd.path orelse {
            fmt.printError("registry", "Missing template file path. Usage: rune registry add <name> <path>");
            return error.RegistryMissingPath;
        };

        // Read template content
        const content = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);

        // Create template directory
        const template_dir = try getTemplatePath(alloc, home_dir, name);
        try std.Io.Dir.createDirPath(std.Io.Dir.cwd(), io, template_dir);

        // Write template content
        const template_file = try getTemplateFilePath(alloc, home_dir, name);
        try std.Io.Dir.cwd().writeFile(io, .{
            .sub_path = template_file,
            .data = content,
        });

        // Create metadata
        const date_str = try getCurrentDateString(io);
        defer alloc.free(date_str);

        // Extract description from template (first comment line)
        var description: []const u8 = "No description";
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |l| {
            const trimmed = std.mem.trim(u8, l, " \t");
            if (std.mem.startsWith(u8, trimmed, "//")) {
                description = std.mem.trim(u8, trimmed[2..], " \t");
                break;
            } else if (trimmed.len > 0) {
                break;
            }
            
        }

        const meta = TemplateMeta{
            .name = try alloc.dupe(u8, name),
            .description = try alloc.dupe(u8, description),
            .version = try alloc.dupe(u8, "0.1.0"),
            .author = null,
            .tags = &.{},
            .dependencies = &.{},
            .min_rune_version = null,
            .created_at = date_str,
            .updated_at = date_str,
        };

        try writeTemplateMeta(io, alloc, home_dir, name, meta);
        try writeRegistryMeta(io, alloc, home_dir);

        const msg = try std.fmt.allocPrint(alloc, "Added template '{s}'", .{name});
        defer alloc.free(msg);
        fmt.printOk(msg);
        return;
    }

    // Handle list subcommand
    if (std.mem.eql(u8, subcmd, "list")) {
        const templates_dir = try getTemplatesPath(alloc, home_dir);
        const dir = std.Io.Dir.cwd().openDir(io, templates_dir, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                try io_mod.writeOutput(io, "No templates in registry. Use 'rune registry add' to add one.\n", null, false);
                return;
            },
            else => |e| return e,
        };
        defer dir.close(io);

        // Collect directory names first
        var names = try std.ArrayList([]const u8).initCapacity(alloc, 16);
        defer names.deinit(alloc);

        var iter = dir.iterate();
        while (try iter.next(io)) |entry| {
            if (entry.kind == .directory) {
                try names.append(alloc, try alloc.dupe(u8, entry.name));
            }
        }

        var first = true;
        for (names.items) |name| {
            const meta = readTemplateMeta(io, alloc, home_dir, name) catch continue;

            if (first) {
                try io_mod.writeOutput(io, "Available templates:\n", null, false);
                first = false;
            }
            const line = try std.fmt.allocPrint(alloc, "  {s}  v{s}  - {s}\n", .{ name, meta.version, meta.description });
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }

        if (first) {
            try io_mod.writeOutput(io, "No templates in registry. Use 'rune registry add' to add one.\n", null, false);
        }
        return;
    }

    // Handle show subcommand
    if (std.mem.eql(u8, subcmd, "show")) {
        const name = cmd.name orelse {
            fmt.printError("registry", "Missing template name. Usage: rune registry show <name>");
            return;
        };

        const meta = readTemplateMeta(io, alloc, home_dir, name) catch {
            const msg = try std.fmt.allocPrint(alloc, "Template not found: {s}", .{name});
        defer alloc.free(msg);
        fmt.printError("registry", msg);
            return error.RegistryTemplateNotFound;
        };

        const content = readTemplateContent(io, alloc, home_dir, name) catch {
            const msg = try std.fmt.allocPrint(alloc, "Failed to read template content: {s}", .{name});
        defer alloc.free(msg);
        fmt.printError("registry", msg);
            return error.RegistryTemplateNotFound;
        };

        {
            const line = try std.fmt.allocPrint(alloc, "Template: {s}\n", .{name});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        {
            const line = try std.fmt.allocPrint(alloc, "Version:  {s}\n", .{meta.version});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        {
            const line = try std.fmt.allocPrint(alloc, "Description: {s}\n", .{meta.description});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        if (meta.author) |a| {
            const line = try std.fmt.allocPrint(alloc, "Author:   {s}\n", .{a});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        if (meta.tags.len > 0) {
            const joined = try std.mem.join(alloc, ", ", meta.tags);
            defer alloc.free(joined);
            const line = try std.fmt.allocPrint(alloc, "Tags:     {s}\n", .{joined});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        if (meta.dependencies.len > 0) {
            const joined = try std.mem.join(alloc, ", ", meta.dependencies);
            defer alloc.free(joined);
            const line = try std.fmt.allocPrint(alloc, "Dependencies: {s}\n", .{joined});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        if (meta.min_rune_version) |v| {
            const line = try std.fmt.allocPrint(alloc, "Min Rune: {s}\n", .{v});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        {
            const line = try std.fmt.allocPrint(alloc, "Created:  {s}\n", .{meta.created_at});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        {
            const line = try std.fmt.allocPrint(alloc, "Updated:  {s}\n", .{meta.updated_at});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        try io_mod.writeOutput(io, "\n--- Content ---\n", null, false);
        {
            const line = try std.fmt.allocPrint(alloc, "{s}\n", .{content});
            defer alloc.free(line);
            try io_mod.writeOutput(io, line, null, false);
        }
        return;
    }

    // Handle remove subcommand
    if (std.mem.eql(u8, subcmd, "remove")) {
        const name = cmd.name orelse {
            fmt.printError("registry", "Missing template name. Usage: rune registry remove <name>");
            return;
        };

        const template_dir = try getTemplatePath(alloc, home_dir, name);
        if (std.Io.Dir.cwd().statFile(io, template_dir, .{})) |_| {
            // Template exists, proceed with removal
        } else |err| switch (err) {
            error.FileNotFound => {
                fmt.printError("registry", "Template not found");
                return error.RegistryTemplateNotFound;
            },
            else => |e| return e,
        }

        // Remove template directory recursively
        try std.Io.Dir.deleteTree(std.Io.Dir.cwd(), io, template_dir);
        try writeRegistryMeta(io, alloc, home_dir);

        fmt.printOk("Removed template");
        return;
    }

    // Unknown subcommand
    fmt.printError("registry", "Unknown subcommand");
    return error.RegistryUnknownSubcommand;
}
