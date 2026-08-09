const std = @import("std");
const pass_manager = @import("../pass_manager.zig");
const PassContext = pass_manager.PassContext;
const ResolvedTable = @import("../../types/resolved_ast.zig").ResolvedTable;
const Field = @import("../../types/ast.zig").Field;

// ─── Resolve Conditional Blocks ───────────────────────────────
// Filters fields in @if(dialect=...) blocks based on the target dialect.
// Fields within a conditional block are only included when the target dialect
// matches one of the block's dialects. Fields outside conditional blocks
// are always included.

pub fn run(ctx: *PassContext) !void {
    const target_dialect = ctx.dialect;
    const target_name = @tagName(target_dialect);

    var i: usize = 0;
    while (i < ctx.tables.items.len) : (i += 1) {
        const table = &ctx.tables.items[i];
        if (table.conditional_blocks.len == 0) continue;

        // Collect fields to keep (non-conditional + matching conditional)
        var kept = try std.ArrayList(Field).initCapacity(ctx.alloc, table.fields.len);

        var field_idx: usize = 0;
        while (field_idx < table.fields.len) {
            // Check if this field is inside a conditional block
            var in_conditional = false;
            var should_keep = true;
            for (table.conditional_blocks) |block| {
                if (field_idx >= block.start_field and field_idx < block.end_field) {
                    in_conditional = true;
                    // Check if any of the block's dialects match the target
                    should_keep = false;
                    for (block.dialects) |dialect_name| {
                        if (std.mem.eql(u8, dialect_name, target_name)) {
                            should_keep = true;
                            break;
                        }
                    }
                    break;
                }
            }

            if (!in_conditional or should_keep) {
                try kept.append(ctx.alloc, table.fields[field_idx]);
            }
            field_idx += 1;
        }

        // Replace fields with filtered version
        table.fields = try kept.toOwnedSlice(ctx.alloc);
    }
}
