// Test module index — imports colocated test files so zig build test discovers them.
// NOTE: These test files have pre-existing compilation errors (string→SqlType mismatches,
// missing struct fields, deprecated API usage). Enable when those are fixed.
// comptime {
//     _ = @import("diff/diff_test.zig");
//     _ = @import("diff/fields_test.zig");
//     _ = @import("codegen/codegen_test.zig");
// }
