const std = @import("std");
const testing = std.testing;
const type_definition = @import("type_definition.zig");
const typed_ast_mod = @import("../types/typed_ast.zig");
const sql_type_mod = @import("../types/sql_type.zig");
const ast_mod = @import("../types/ast.zig");
const protocol = @import("protocol.zig");

test "type definition: custom type field" {
    // This test verifies that getTypeDefinition returns null when
    // there are no custom types in the AST (basic smoke test)
    const typed = typed_ast_mod.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };

    const position = protocol.Position{ .line = 0, .character = 0 };
    const result = type_definition.getTypeDefinition(testing.allocator, typed, "file:///test.ss", position);

    try testing.expect(result == null);
}

test "type definition: no match when cursor not on field" {
    const typed = typed_ast_mod.TypedAst{
        .schema_name = null,
        .schema_charset = null,
        .custom_types = &.{},
        .tables = &.{},
        .views = &.{},
        .sql_comments = &.{},
    };

    // Cursor on line 0 but no table there
    const position = protocol.Position{ .line = 0, .character = 0 };
    const result = type_definition.getTypeDefinition(testing.allocator, typed, "file:///test.ss", position);

    try testing.expect(result == null);
}
