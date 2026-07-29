const std = @import("std");
const typed_ast = @import("../types/typed_ast.zig");
const codegen_mod = @import("../codegen/codegen.zig");
const dialect_enum = @import("../dialect/enum.zig");
const Dialect = dialect_enum.Dialect;

// ─── SQL DDL Generator ───────────────────────────────────────
// Wraps the existing codegen engine to expose SQL DDL as a generator.
// Output: CREATE TABLE / CREATE VIEW DDL for the selected dialect.
//
// Architecture: TypedAst → Codegen.generateFromTypedAst → SQL string

pub fn generate(alloc: std.mem.Allocator, typed: typed_ast.TypedAst, dialect: Dialect) ![]const u8 {
    var cg = codegen_mod.Codegen.init(alloc, dialect);
    return try cg.generateFromTypedAst(typed);
}
