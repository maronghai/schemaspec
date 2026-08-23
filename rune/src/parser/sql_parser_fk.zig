const std = @import("std");
const sp = @import("sql_parser.zig");
const common = @import("sql_parser_common.zig");
const FkAction = common.FkAction;
const FkActionTrigger = common.FkActionTrigger;
const FkActionType = common.FkActionType;
const SqlForeignKey = common.SqlForeignKey;

// ─── FOREIGN KEY Parsing ──────────────────────────────────────

pub fn parseForeignKey(self: *sp.SqlParser) !SqlForeignKey {
    self.expectKeyword("FOREIGN");
    self.skipSpacesAndNewlines();
    self.expectKeyword("KEY");
    self.skipSpacesAndNewlines();
    const fk_fl = try self.parseParenFieldList();
    self.alloc.free(fk_fl.descending);
    const fk_fields = fk_fl.fields;
    self.skipSpacesAndNewlines();
    self.expectKeyword("REFERENCES");
    self.skipSpacesAndNewlines();
    const ref_table = try self.parseIdentifier();
    self.skipSpacesAndNewlines();
    const fk_ref_fl = try self.parseParenFieldList();
    self.alloc.free(fk_ref_fl.descending);
    const fk_ref_fields = fk_ref_fl.fields;

    var actions = try std.ArrayList(FkAction).initCapacity(self.alloc, 4);
    while (true) {
        self.skipSpacesAndNewlines();
        if (self.matchKeyword("ON")) {
            self.skipSpaces();
            const trigger: FkActionTrigger = blk: {
                if (self.matchKeyword("DELETE")) break :blk .on_delete;
                if (self.matchKeyword("UPDATE")) break :blk .on_update;
                self.reportError("expected DELETE or UPDATE after ON in foreign key action", .{});
                return error.ExpectedDeleteOrUpdate;
            };
            self.skipSpaces();
            const act: FkActionType = blk: {
                if (self.matchKeyword("CASCADE")) break :blk .cascade;
                if (self.matchKeyword("RESTRICT")) break :blk .restrict;
                if (self.matchKeyword("NO")) {
                    self.skipSpaces();
                    if (self.matchKeyword("ACTION")) break :blk .no_action;
                }
                if (self.matchKeyword("SET")) {
                    self.skipSpaces();
                    if (self.matchKeyword("NULL")) break :blk .set_null;
                    if (self.matchKeyword("DEFAULT")) break :blk .set_default;
                }
                self.reportError("expected CASCADE, RESTRICT, NO ACTION, SET NULL, or SET DEFAULT in foreign key action", .{});
                return error.ExpectedFkAction;
            };
            try actions.append(self.alloc, .{ .trigger = trigger, .action = act });
        } else {
            break;
        }
    }

    return .{
        .fields = fk_fields,
        .ref_table = ref_table,
        .ref_fields = fk_ref_fields,
        .actions = try actions.toOwnedSlice(self.alloc),
    };
}

/// Parse an inline column-level `REFERENCES table [(col[, ...])] [actions]`.
/// Used by the column-definition parser; the local field is the column itself.
/// Returns null-safe: callers treat parse failure as "no inline FK" (the
/// tokens are then consumed by the outer loop as before).
pub fn parseInlineReferences(self: *sp.SqlParser) !SqlForeignKey {
    self.skipSpacesAndNewlines();
    const ref_table = try self.parseIdentifier();
    self.skipSpacesAndNewlines();

    var ref_fields: []const []const u8 = &.{};
    if (self.pos < self.src.len and self.peek() == '(') {
        const fl = try self.parseParenFieldList();
        self.alloc.free(fl.descending);
        ref_fields = fl.fields;
    }

    var actions = try std.ArrayList(FkAction).initCapacity(self.alloc, 2);
    while (true) {
        self.skipSpacesAndNewlines();
        if (self.matchKeyword("ON")) {
            self.skipSpaces();
            var trigger: ?FkActionTrigger = null;
            if (self.matchKeyword("DELETE")) {
                trigger = .on_delete;
            } else if (self.matchKeyword("UPDATE")) {
                trigger = .on_update;
            }
            if (trigger == null) break;
            self.skipSpaces();
            var act: ?FkActionType = null;
            if (self.matchKeyword("CASCADE")) {
                act = .cascade;
            } else if (self.matchKeyword("RESTRICT")) {
                act = .restrict;
            } else if (self.matchKeyword("NO")) {
                self.skipSpaces();
                if (self.matchKeyword("ACTION")) act = .no_action;
            } else if (self.matchKeyword("SET")) {
                self.skipSpaces();
                if (self.matchKeyword("NULL")) {
                    act = .set_null;
                } else if (self.matchKeyword("DEFAULT")) {
                    act = .set_default;
                }
            }
            if (act == null) break;
            try actions.append(self.alloc, .{ .trigger = trigger.?, .action = act.? });
        } else {
            break;
        }
    }

    return .{
        .fields = &.{}, // the local field is the declaring column
        .ref_table = ref_table,
        .ref_fields = ref_fields,
        .actions = try actions.toOwnedSlice(self.alloc),
    };
}
