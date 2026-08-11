const ast_mod = @import("ast.zig");
const FkDecl = ast_mod.FkDecl;
const IndexDecl = ast_mod.IndexDecl;
const CustomType = ast_mod.CustomType;
const View = ast_mod.View;
const SqlComment = ast_mod.SqlComment;
const ir_version = @import("ir_version.zig");

// ─── Resolved AST: Semantic analysis output ─────────────────
// These types represent the output of template resolution + semantic passes.
// They live here (not in ast.zig) to separate parser output from semantic output.

pub const ResolvedTable = struct {
    name: []const u8,
    comment: ?[]const u8,
    /// Inline documentation from `+` directive lines.
    doc: ?[]const u8 = null,
    engine: ?[]const u8,
    fields: []ast_mod.Field,
    fks: []const FkDecl,
    indexes: []const IndexDecl,
    /// Conditional blocks: fields between @if and @endif that are dialect-specific.
    conditional_blocks: []const ast_mod.ConditionalBlock = &.{},
    line_no: usize,
    /// Template reference: the name of the template applied to this table (if any).
    template_ref: ?[]const u8 = null,
};

pub const ResolvedAst = struct {
    /// IR format version for forward/backward compatibility detection.
    ir_version: u32 = ir_version.CURRENT_IR_VERSION,
    schema_name: ?[]const u8,
    schema_charset: ?[]const u8,
    /// Custom type definitions from ~ directives
    custom_types: []const CustomType,
    /// Schema version from @version directive
    schema_version: ?[]const u8 = null,
    tables: []const ResolvedTable,
    views: []const View,
    sql_comments: []const SqlComment,
};
