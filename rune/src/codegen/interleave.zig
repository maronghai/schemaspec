const std = @import("std");

// ─── Line-Merge Iterator ───────────────────────────────────────
//
// Generic merge of three sorted-by-line_no sequences.
// Used by codegen and streaming to interleave tables, views, and
// SQL comments in source-file order.
//
// Each call site maintains its own typed iteration state (indices
// into TypedAst or StreamingResult arrays); LineMerger only tracks
// the next line_no from each sequence and yields which one wins.

pub const Kind = enum { table, view, comment };

pub const LineMerger = struct {
    table_line: usize,
    view_line: usize,
    comment_line: usize,
    ti: usize = 0,
    vi: usize = 0,
    ci: usize = 0,

    pub fn init(tables: anytype, views: anytype, comments: anytype) LineMerger {
        return .{
            .table_line = if (tables.len > 0) tables[0].line_no else std.math.maxInt(usize),
            .view_line = if (views.len > 0) views[0].line_no else std.math.maxInt(usize),
            .comment_line = if (comments.len > 0) comments[0].line_no else std.math.maxInt(usize),
        };
    }

    /// Advance to the next item. Returns null when all sequences are exhausted.
    pub fn next(self: *LineMerger) ?Kind {
        const min_line = @min(self.table_line, self.view_line, self.comment_line);
        if (min_line == std.math.maxInt(usize)) return null;

        // Comments first (tie-breaker matches original behavior).
        if (self.comment_line == min_line) {
            self.ci += 1;
            return .comment;
        } else if (self.view_line == min_line) {
            self.vi += 1;
            return .view;
        } else {
            self.ti += 1;
            return .table;
        }
    }

    /// Update table_line after consuming a table. Call when the table
    /// index has advanced (ti incremented) and you need the next line_no.
    pub fn advanceTable(self: *LineMerger, tables: anytype) void {
        self.table_line = if (self.ti < tables.len) tables[self.ti].line_no else std.math.maxInt(usize);
    }

    /// Update view_line after consuming a view.
    pub fn advanceView(self: *LineMerger, views: anytype) void {
        self.view_line = if (self.vi < views.len) views[self.vi].line_no else std.math.maxInt(usize);
    }

    /// Update comment_line after consuming a comment.
    pub fn advanceComment(self: *LineMerger, comments: anytype) void {
        self.comment_line = if (self.ci < comments.len) comments[self.ci].line_no else std.math.maxInt(usize);
    }
};

// ─── Tests ──────────────────────────────────────────────────────

const testing = std.testing;

const TestItem = struct { line_no: usize, id: u8 };

test "LineMerger empty" {
    var m = LineMerger.init(&[_]TestItem{}, &[_]TestItem{}, &[_]TestItem{});
    try testing.expectEqual(@as(?Kind, null), m.next());
}

test "LineMerger single table" {
    const tables = [_]TestItem{.{ .line_no = 1, .id = 0 }};
    var m = LineMerger.init(&tables, &[_]TestItem{}, &[_]TestItem{});
    try testing.expectEqual(@as(?Kind, .table), m.next());
    m.advanceTable(&tables);
    try testing.expectEqual(@as(?Kind, null), m.next());
}

test "LineMerger interleaving order" {
    const tables = [_]TestItem{
        .{ .line_no = 1, .id = 0 },
        .{ .line_no = 5, .id = 1 },
    };
    const views = [_]TestItem{
        .{ .line_no = 3, .id = 0 },
    };
    const comments = [_]TestItem{
        .{ .line_no = 2, .id = 0 },
        .{ .line_no = 4, .id = 1 },
    };
    var m = LineMerger.init(&tables, &views, &comments);

    try testing.expectEqual(@as(?Kind, .table), m.next());
    m.advanceTable(&tables);
    try testing.expectEqual(@as(?Kind, .comment), m.next());
    m.advanceComment(&comments);
    try testing.expectEqual(@as(?Kind, .view), m.next());
    m.advanceView(&views);
    try testing.expectEqual(@as(?Kind, .comment), m.next());
    m.advanceComment(&comments);
    try testing.expectEqual(@as(?Kind, .table), m.next());
    m.advanceTable(&tables);
    try testing.expectEqual(@as(?Kind, null), m.next());
}

test "LineMerger tie-breaker: comment wins over table" {
    const tables = [_]TestItem{.{ .line_no = 1, .id = 0 }};
    const comments = [_]TestItem{.{ .line_no = 1, .id = 0 }};
    var m = LineMerger.init(&tables, &[_]TestItem{}, &comments);
    try testing.expectEqual(@as(?Kind, .comment), m.next());
}

test "LineMerger tie-breaker: view wins over table" {
    const tables = [_]TestItem{.{ .line_no = 1, .id = 0 }};
    const views = [_]TestItem{.{ .line_no = 1, .id = 0 }};
    var m = LineMerger.init(&tables, &views, &[_]TestItem{});
    try testing.expectEqual(@as(?Kind, .view), m.next());
}
