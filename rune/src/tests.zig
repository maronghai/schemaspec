// Test module index — imports colocated test files so zig build test discovers them.
comptime {
    _ = @import("diff/diff_test.zig");
    _ = @import("diff/fields_test.zig");
    _ = @import("codegen/codegen_test.zig");
}
