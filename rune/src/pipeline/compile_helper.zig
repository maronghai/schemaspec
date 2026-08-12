const std = @import("std");
const forward = @import("forward.zig");
const compilePipeline = forward.compilePipeline;
const dialect_enum = @import("../dialect/enum.zig");
const TypeResolver = @import("../types/type_resolver.zig").TypeResolver;
const TypedAst = @import("../types/typed_ast.zig").TypedAst;

// ─── Shared Compile Helper ─────────────────────────────────────
// Compile schema text to a TypedAst. Used by both generate.zig and handlers.zig.

/// Compile schema text to a TypedAst for use by generators.
/// Single entry point for the compile → resolve pattern used by
/// generateFromSchema, generateFromSchemaBatch, and handleDocs.
pub fn compileToTypedAst(alloc: std.mem.Allocator, file_data: []const u8, dialect: dialect_enum.Dialect) !TypedAst {
    const pipeline = try compilePipeline(alloc, file_data, .{});
    return TypeResolver.resolve(alloc, pipeline.resolved, dialect);
}
