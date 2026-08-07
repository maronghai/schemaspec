const std = @import("std");
const io_mod = @import("../io.zig");
const dialect_enum = @import("../dialect/enum.zig");

// ─── `rune init` ──────────────────────────────────────────────
// Supports --template flag to choose from preset schemas.

pub const STARTER_SCHEMA =
    \\; Starter schema — edit this file to define your database
    \\
    \\; ── Schema ─────────────────────────────────────────────
    \\
    \\$ mydb
    \\
    \\; ── Tables ─────────────────────────────────────────────
    \\
    \\; Users table
    \\# users
    \\id       n++
    \\email    s128
    \\name     s64
    \\role     e(editor,viewer) =viewer
    \\@ email
    \\
    \\; Posts table
    \\# posts
    \\id         n++
    \\title      s256
    \\body       S
    \\author_id  n              ; FK → users.id (auto-inferred from _id suffix)
    \\status     e(draft,published,archived) =draft
    \\@ author_id
    \\@ status
    \\
    \\; Comments table
    \\# comments
    \\id        n++
    \\post_id   n               ; FK → posts.id
    \\author_id n                ; FK → users.id
    \\body      S
    \\@ post_id
    \\
;

const BLOG_SCHEMA =
    \\; Blog schema — posts, categories, tags, and comments
    \\
    \\$ blog
    \\
    \\; Categories
    \\# categories
    \\id    n++
    \\name  s64
    \\slug  s64
    \\@ slug
    \\
    \\; Tags
    \\# tags
    \\id    n++
    \\name  s32
    \\slug  s32
    \\@ slug
    \\
    \\; Posts
    \\# posts
    \\id            n++
    \\title         s256
    \\slug          s256
    \\body          S
    \\author_id     n              ; FK → users.id
    \\category_id   n              ; FK → categories.id
    \\status        e(draft,published,archived) =draft
    \\published_at  d
    \\@ slug
    \\@ author_id
    \\@ category_id
    \\@ status
    \\
    \\; Post-tag junction
    \\# post_tags
    \\post_id  n                  ; FK → posts.id
    \\tag_id   n                  ; FK → tags.id
    \\@ post_id
    \\@ tag_id
    \\
    \\; Comments
    \\# comments
    \\id          n++
    \\post_id     n               ; FK → posts.id
    \\author_id   n               ; FK → users.id (if users table exists)
    \\parent_id   n?              ; self-referencing FK for nested comments
    \\body        S
    \\@ post_id
    \\
;

const ECOMMERCE_SCHEMA =
    \\; E-commerce schema — products, orders, and customers
    \\
    \\$ store
    \\
    \\; Customers
    \\# customers
    \\id         n++
    \\email      s128
    \\name       s64
    \\phone      s32?
    \\@ email
    \\
    \\; Products
    \\# products
    \\id          n++
    \\name        s128
    \\sku         s64
    \\description S
    \\price       d               ; decimal price
    \\stock       n =0
    \\category    s64?
    \\@ sku
    \\
    \\; Orders
    \\# orders
    \\id           n++
    \\customer_id  n               ; FK → customers.id
    \\status       e(pending,shipped,delivered,cancelled) =pending
    \\total        d
    \\created_at   d
    \\@ customer_id
    \\@ status
    \\
    \\; Order items
    \\# order_items
    \\id         n++
    \\order_id   n               ; FK → orders.id
    \\product_id n               ; FK → products.id
    \\quantity   n =1
    \\unit_price d
    \\@ order_id
    \\@ product_id
    \\
;

const REST_API_SCHEMA =
    \\; REST API schema — resources, endpoints, and API keys
    \\
    \\$ api
    \\
    \\; API consumers
    \\# api_consumers
    \\id         n++
    \\name       s64
    \\email      s128
    \\@ email
    \\
    \\; API keys
    \\# api_keys
    \\id           n++
    \\consumer_id  n               ; FK → api_consumers.id
    \\key_hash     s128
    \\permissions  s256            ; comma-separated scopes
    \\expires_at   d?
    \\@ consumer_id
    \\@ key_hash
    \\
    \\; Resources (CRUD entities)
    \\# resources
    \\id          n++
    \\name        s64
    \\endpoint    s128            ; e.g. /api/v1/users
    \\method      e(GET,POST,PUT,PATCH,DELETE)
    \\auth_required b =true
    \\@ endpoint
    \\@ name
    \\
    \\; Audit log
    \\# audit_log
    \\id            n++
    \\consumer_id   n?              ; FK → api_consumers.id
    \\resource_id   n               ; FK → resources.id
    \\action        s32
    \\status_code   n
    \\created_at    d
    \\@ consumer_id
    \\@ resource_id
    \\
;

/// Get template content by name. Returns null for unknown names.
fn getTemplate(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "default") or std.mem.eql(u8, name, "")) return STARTER_SCHEMA;
    if (std.mem.eql(u8, name, "blog")) return BLOG_SCHEMA;
    if (std.mem.eql(u8, name, "ecommerce")) return ECOMMERCE_SCHEMA;
    if (std.mem.eql(u8, name, "rest-api")) return REST_API_SCHEMA;
    return null;
}

pub fn handleInit(io: std.Io, alloc: std.mem.Allocator, name: ?[]const u8, output: ?[]const u8, output_dir: ?[]const u8, dialect: dialect_enum.Dialect, template: ?[]const u8) !void {
    const filename = name orelse "schema";
    const out_path = output orelse blk: {
        if (output_dir) |dir| {
            // Create directory recursively (like mkdir -p)
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
            break :blk try std.fmt.allocPrint(alloc, "{s}/{s}.ss", .{ dir, filename });
        }
        break :blk try std.fmt.allocPrint(alloc, "{s}.ss", .{filename});
    };

    // Resolve template
    const tpl_name = template orelse "default";
    const schema = getTemplate(tpl_name) orelse {
        std.debug.print("error: unknown template '{s}'. Available: default, blog, ecommerce, rest-api\n", .{tpl_name});
        return error.UnknownTemplate;
    };

    // Prepend dialect hint comment for the user
    const dialect_name = @tagName(dialect);
    const schema_with_hint = try std.fmt.allocPrint(alloc, "; Target dialect: {s}\n{s}", .{ dialect_name, schema });
    try io_mod.writeOutput(io, schema_with_hint, out_path, false);
    std.debug.print("Created {s} (dialect: {s}, template: {s})\n", .{ out_path, dialect_name, tpl_name });
    std.debug.print("Edit this file, then run: rune {s} -d {s}\n", .{ out_path, dialect_name });
}
