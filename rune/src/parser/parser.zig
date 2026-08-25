const std = @import("std");
const tk = @import("tokenizer.zig");
const diag = @import("../diagnostic.zig");
const ast_mod = @import("../types/ast.zig");
const parse_fk = @import("parse_fk.zig");
const parse_index = @import("parse_index.zig");
const parse_check = @import("parse_check.zig");
const parse_field = @import("parse_field.zig");
const parse_typedef = @import("parse_typedef.zig");
const parse_template = @import("parse_template.zig");
const parse_table = @import("parse_table.zig");
const parse_trace = @import("parse_trace.zig");
const parse_recovery = @import("parse_recovery.zig");
const Ast = ast_mod.Ast;
const Table = ast_mod.Table;
const Field = ast_mod.Field;
const Template = ast_mod.Template;
const TypeInfo = ast_mod.TypeInfo;
const Modifier = ast_mod.Modifier;
const ModifierType = ast_mod.ModifierType;
const DefaultVal = ast_mod.DefaultVal;
const CheckConstraint = ast_mod.CheckConstraint;
const CheckKind = ast_mod.CheckKind;
const FkDecl = ast_mod.FkDecl;
const FkAction = ast_mod.FkAction;
const FkActionType = ast_mod.FkActionType;
const IndexDecl = ast_mod.IndexDecl;
const IndexType = ast_mod.IndexType;
const Schema = ast_mod.Schema;
const SqlComment = ast_mod.SqlComment;
const SourceLocation = ast_mod.SourceLocation;

// ─── Parser ──────────────────────────────────────────────────

pub const Parser = struct {
    alloc: std.mem.Allocator,
    diagnostics: ?*diag.DiagnosticCollector,
    /// Pending documentation from `+` doc lines (attached to next construct).
    pending_doc: ?[]const u8 = null,

    pub fn init(alloc: std.mem.Allocator) Parser {
        return .{ .alloc = alloc, .diagnostics = null };
    }

    pub fn initWithDiagnostics(alloc: std.mem.Allocator, diagnostics: *diag.DiagnosticCollector) Parser {
        return .{ .alloc = alloc, .diagnostics = diagnostics };
    }

    /// Record a parse error via DiagnosticCollector, or signal caller to propagate.
    /// Returns true if error was recorded (caller should continue), false to propagate.
    fn handleParseError(self: *Parser, err: anyerror, line: tk.Line, comptime message: []const u8) bool {
        return parse_recovery.handleParseError(self.diagnostics, err, line, message);
    }

    /// Compute SourceLocation from a tokenized line and a token within it.
    fn locFromLine(line: tk.Line, tok: []const u8) SourceLocation {
        return parse_recovery.locFromLine(line, tok);
    }

    // ─── Block State ─────────────────────────────────────────────

    const BlockMode = enum { none, template, table, composite };

    const BlockState = struct {
        name: ?[]const u8 = null,
        comment: ?[]const u8 = null,
        doc: ?[]const u8 = null,
        template_ref: ?[]const u8 = null,
        /// Fixed-size buffer for parent template names (max 4 parents via mixin syntax).
        /// Uses a slice pointing to the fixed array for compatibility with flushTemplate.
        parents_buf_storage: [4][]const u8 = .{ "", "", "", "" },
        parents_buf: [][]const u8 = &.{},
        parents_len: usize = 0,
        fields: std.ArrayList(Field),
        fks: std.ArrayList(FkDecl),
        indexes: std.ArrayList(IndexDecl),
        conditional_blocks: std.ArrayList(ast_mod.ConditionalBlock),
        /// Composite embeds (`*name` lines) collected inside a table body, in source order.
        embeds: std.ArrayList(ast_mod.CompositeEmbed),
        /// Currently open @if block dialects (null if not inside @if).
        pending_if_dialects: ?[]const []const u8 = null,
        /// Start field index of the current @if block.
        pending_if_start: usize = 0,
        line_no: usize = 0,
        loc: ?SourceLocation = null,
        engine: ?[]const u8 = null,
        mode: BlockMode = .none,

        fn init(alloc: std.mem.Allocator) !BlockState {
            var bs = BlockState{
                .fields = try std.ArrayList(Field).initCapacity(alloc, 16),
                .fks = try std.ArrayList(FkDecl).initCapacity(alloc, 4),
                .indexes = try std.ArrayList(IndexDecl).initCapacity(alloc, 4),
                .conditional_blocks = try std.ArrayList(ast_mod.ConditionalBlock).initCapacity(alloc, 4),
                .embeds = try std.ArrayList(ast_mod.CompositeEmbed).initCapacity(alloc, 4),
            };
            bs.parents_buf = &bs.parents_buf_storage;
            return bs;
        }

        fn reset(self: *BlockState) void {
            self.name = null;
            self.comment = null;
            self.doc = null;
            self.template_ref = null;
            // Reset the fixed-size buffer (no allocation needed).
            // Previously flushed templates reference slices of this buffer,
            // but those slices are valid until the next reset() overwrites them.
            // The arena allocator ensures the original data remains valid.
            self.parents_buf = &self.parents_buf_storage;
            self.parents_len = 0;
            self.fields.clearRetainingCapacity();
            self.fks.clearRetainingCapacity();
            self.indexes.clearRetainingCapacity();
            self.conditional_blocks.clearRetainingCapacity();
            self.embeds.clearRetainingCapacity();
            self.pending_if_dialects = null;
            self.pending_if_start = 0;
            self.line_no = 0;
            self.loc = null;
            self.engine = null;
        }

        fn deinit(self: *BlockState, alloc: std.mem.Allocator) void {
            self.fields.deinit(alloc);
            self.fks.deinit(alloc);
            self.indexes.deinit(alloc);
            self.conditional_blocks.deinit(alloc);
            self.embeds.deinit(alloc);
            // Note: parents_buf uses fixed storage, no deallocation needed.
        }
    };

    // ─── Parse ──────────────────────────────────────────────────

    pub fn parse(self: *Parser, lines: []const tk.Line) !Ast {
        var schema: ?Schema = null;
        var version: ?[]const u8 = null;
        var templates = try std.ArrayList(Template).initCapacity(self.alloc, 8);
        var tables = try std.ArrayList(Table).initCapacity(self.alloc, 8);
        var views = try std.ArrayList(ast_mod.View).initCapacity(self.alloc, 8);
        var sql_comments = try std.ArrayList(SqlComment).initCapacity(self.alloc, 8);
        var custom_types = try std.ArrayList(ast_mod.CustomType).initCapacity(self.alloc, 8);
        var composites = try std.ArrayList(ast_mod.Composite).initCapacity(self.alloc, 4);

        var block = try BlockState.init(self.alloc);
        // Fatal parse errors return early (when no DiagnosticCollector is
        // attached); the success path deinits explicitly below.
        errdefer block.deinit(self.alloc);

        var line_idx: usize = 0;
        while (line_idx < lines.len) : (line_idx += 1) {
            const line = lines[line_idx];
            switch (line.line_type) {
                .Empty, .SpecComment => {},
                .Doc => {
                    // Collect `+` doc lines; attach to the next construct.
                    const text = if (line.trimmed.len > 1) std.mem.trim(u8, line.trimmed[1..], " ") else "";
                    if (text.len > 0) {
                        if (self.pending_doc) |existing| {
                            self.pending_doc = try std.fmt.allocPrint(self.alloc, "{s}\n{s}", .{ existing, text });
                        } else {
                            self.pending_doc = try self.alloc.dupe(u8, text);
                        }
                    }
                },
                .Schema => {
                    if (line.tokens.len >= 2) {
                        var charset: ?[]const u8 = null;
                        var autofk = false;
                        var si: usize = 2;
                        while (si < line.tokens.len) : (si += 1) {
                            if (std.mem.eql(u8, line.tokens[si], "autofk")) {
                                autofk = true;
                            } else if (charset == null) {
                                charset = try self.alloc.dupe(u8, line.tokens[si]);
                            }
                        }
                        schema = .{
                            .name = try self.alloc.dupe(u8, line.tokens[1]),
                            .charset = charset,
                            .autofk = autofk,
                            .custom_types = &.{},
                            .line_no = line.line_no,
                            .loc = Parser.locFromLine(line, line.tokens[0]),
                        };
                    }
                },
                .TypeDef => {
                    if (schema != null and line.tokens.len >= 3) {
                        const ct = parse_typedef.parseTypeDef(self.alloc, line) catch |err| {
                            if (!self.handleParseError(err, line, "failed to parse ~ (custom type) directive")) return err;
                            continue;
                        };
                        try custom_types.append(self.alloc, ct);
                    }
                },
                .Template => {
                    if (block.mode == .template) {
                        try self.flushCurrentTemplate(&templates, &block);
                    } else if (block.mode == .table) {
                        try self.flushCurrentTable(&tables, &block);
                    } else if (block.mode == .composite) {
                        self.flushCurrentComposite(&composites, &block);
                    }

                    // Parse new template header
                    const tmpl = parse_template.parseTemplateHeader(self.alloc, line) catch |err| {
                        if (!self.handleParseError(err, line, "failed to parse template declaration")) return err;
                        block.mode = .none;
                        // Sync to next block boundary to avoid orphaned field warnings
                        if (parse_recovery.findNextBlockBoundary(lines, line_idx + 1)) |next| {
                            line_idx = next - 1; // -1 because while loop increments
                        }
                        continue;
                    };
                    defer self.alloc.free(tmpl.parents);
                    block.reset();
                    const captured_doc = self.pending_doc;
                    self.pending_doc = null;
                    block.name = tmpl.name;
                    block.doc = captured_doc;
                    for (tmpl.parents) |p| {
                        if (block.parents_len < block.parents_buf.len) {
                            block.parents_buf[block.parents_len] = p;
                            block.parents_len += 1;
                        }
                    }
                    block.line_no = tmpl.line_no;
                    block.loc = tmpl.loc;
                    block.mode = .template;
                },
                .Table => {
                    if (block.mode == .template) {
                        try self.flushCurrentTemplate(&templates, &block);
                    } else if (block.mode == .table) {
                        try self.flushCurrentTable(&tables, &block);
                    } else if (block.mode == .composite) {
                        self.flushCurrentComposite(&composites, &block);
                    }

                    const pending_engine = block.engine;
                    const result = try parse_table.stripEngineTokens(self.alloc, line.tokens);
                    block.reset();
                    const captured_doc = self.pending_doc;
                    self.pending_doc = null;
                    block.engine = if (result.engine) |e| e else pending_engine;
                    const stripped_line = tk.Line{
                        .line_type = line.line_type,
                        .tokens = result.stripped,
                        .raw = line.raw,
                        .trimmed = line.trimmed,
                        .line_no = line.line_no,
                    };

                    const hdr = parse_table.parseTableHeader(self.alloc, stripped_line) catch |err| {
                        if (!self.handleParseError(err, line, "failed to parse table declaration")) return err;
                        block.mode = .none;
                        // Sync to next block boundary to avoid orphaned field warnings
                        if (parse_recovery.findNextBlockBoundary(lines, line_idx + 1)) |next| {
                            line_idx = next - 1; // -1 because while loop increments
                        }
                        continue;
                    };
                    block.name = hdr.name;
                    block.comment = hdr.comment;
                    block.doc = captured_doc;
                    block.template_ref = hdr.template_ref;
                    block.line_no = hdr.line_no;
                    block.loc = hdr.loc;
                    block.mode = .table;
                },
                .View => {
                    if (block.mode == .template) {
                        try self.flushCurrentTemplate(&templates, &block);
                    } else if (block.mode == .table) {
                        try self.flushCurrentTable(&tables, &block);
                    }
                    block.mode = .none;
                    if (line.tokens.len >= 2) {
                        var view = parse_table.processViewLine(self.alloc, line.tokens, line.line_no) catch continue;
                        if (self.pending_doc) |d| {
                            view.doc = d;
                            self.pending_doc = null;
                        }
                        views.append(self.alloc, view) catch continue;
                    }
                },
                .Composite => {
                    // `*name` — composite type declaration (top level) or embed (inside table)
                    if (line.tokens.len < 2 or line.tokens[1].len == 0) {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .@"error",
                            .line_no = line.line_no,
                            .message = "composite declaration requires a name: * name",
                            .source_line = line.raw,
                        });
                        continue;
                    }
                    const comp_name = try self.alloc.dupe(u8, line.tokens[1]);
                    // `*name` (no space) inside a table body is an embed.
                    // `* name` (space) is a NEW top-level declaration: close
                    // the current table and start collecting the composite —
                    // same rule as `#` closing a table. Without this a
                    // declaration after a brace-free table became an embed
                    // of an undefined name (two cascading errors).
                    const is_embed = block.mode == .table and
                        line.raw.len > 1 and line.raw[1] != ' ' and line.raw[1] != '\t';
                    if (is_embed) {
                        // Embed site inside a table body — record position for in-place expansion.
                        // If the embed line sits inside an @if block, carry its dialects:
                        // embed lines add no field, so conditional-block ranges can't cover them.
                        try block.embeds.append(self.alloc, .{
                            .name = comp_name,
                            .insert_pos = block.fields.items.len,
                            .line_no = line.line_no,
                            .dialects = if (block.pending_if_dialects) |ds| ds else null,
                        });
                        continue;
                    }
                    if (block.mode == .template) {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .@"error",
                            .line_no = line.line_no,
                            .message = "composite embed inside template is not supported — declare the field group directly",
                            .source_line = line.raw,
                        });
                        continue;
                    }
                    // Top-level: consecutive `*name` lines are sequential declarations.
                    // Composite bodies have no explicit terminator, so a new `*name`
                    // simply closes the previous composite (same rule as templates).
                    // Top-level declaration: close any open block, start collecting fields.
                    if (block.mode == .template) {
                        try self.flushCurrentTemplate(&templates, &block);
                    } else if (block.mode == .table) {
                        try self.flushCurrentTable(&tables, &block);
                    } else if (block.mode == .composite) {
                        self.flushCurrentComposite(&composites, &block);
                    }
                    block.reset();
                    const captured_doc = self.pending_doc;
                    self.pending_doc = null;
                    block.name = comp_name;
                    block.doc = captured_doc;
                    block.line_no = line.line_no;
                    block.loc = Parser.locFromLine(line, line.tokens[0]);
                    block.mode = .composite;
                },
                .Field => {
                    // Brace-form table body terminator: a line that is just `}`.
                    // Real field names can never be `}` (name_char excludes it),
                    // so this is unambiguous structural syntax.
                    if (line.tokens.len == 1 and std.mem.eql(u8, line.tokens[0], "}")) {
                        if (block.mode == .table) {
                            try self.flushCurrentTable(&tables, &block);
                            block.mode = .none;
                        } else if (block.mode == .template) {
                            try self.flushCurrentTemplate(&templates, &block);
                            block.mode = .none;
                        } else if (block.mode == .composite) {
                            self.flushCurrentComposite(&composites, &block);
                            block.mode = .none;
                        } else {
                            diag.printDiagnostic(self.alloc, .{
                                .severity = .warning,
                                .line_no = line.line_no,
                                .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                                .message = "unexpected closing brace '}' outside any block — ignored",
                                .source_line = line.raw,
                            });
                        }
                        continue;
                    }
                    if (block.mode != .none) {
                        var fld = parse_field.parseField(self.alloc, line) catch |err| {
                            if (!self.handleParseError(err, line, "failed to parse field")) return err;
                            continue;
                        };
                        if (self.pending_doc) |d| {
                            fld.doc = d;
                            self.pending_doc = null;
                        }
                        try block.fields.append(self.alloc, fld);
                    } else {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "field declaration outside table or template — ignored",
                            .source_line = line.raw,
                        });
                    }
                },
                .Slot => {
                    if (block.mode != .none) {
                        const slot_doc = self.pending_doc;
                        self.pending_doc = null;
                        try block.fields.append(self.alloc, .{
                            .name = "...",
                            .doc = slot_doc,
                            .type_info = .none,
                            .modifiers = &.{},
                            .default_val = null,
                            .check = null,
                            .fk = null,
                            .comment = null,
                            .line_no = line.line_no,
                            .loc = if (line.tokens.len > 0) Parser.locFromLine(line, line.tokens[0]) else null,
                        });
                    } else {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "slot declaration outside template — ignored",
                            .source_line = line.raw,
                        });
                    }
                },
                .FK => {
                    if (block.mode == .table) {
                        const fk = parse_fk.parseFk(self.alloc, line) catch |err| {
                            if (!self.handleParseError(err, line, "failed to parse foreign key")) return err;
                            continue;
                        };
                        try block.fks.append(self.alloc, fk);
                    } else if (block.mode == .template) {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "FOREIGN KEY ignored inside template — declare in table instead",
                            .source_line = line.raw,
                        });
                    }
                },
                .Index => {
                    if (block.mode == .table) {
                        const idx = parse_index.parseIndex(self.alloc, line) catch |err| {
                            if (!self.handleParseError(err, line, "failed to parse index")) return err;
                            continue;
                        };
                        try block.indexes.append(self.alloc, idx);
                    } else if (block.mode == .template) {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "INDEX ignored inside template — declare in table instead",
                            .source_line = line.raw,
                        });
                    }
                },
                .CompositePK => {
                    if (block.mode == .table) {
                        const idx = parse_index.parseCompositePk(self.alloc, line) catch |err| {
                            if (!self.handleParseError(err, line, "failed to parse composite primary key")) return err;
                            continue;
                        };
                        try block.indexes.append(self.alloc, idx);
                    } else if (block.mode == .template) {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "composite PRIMARY KEY ignored inside template — declare in table instead",
                            .source_line = line.raw,
                        });
                    }
                },
                .Engine => {
                    if (line.tokens.len >= 2) {
                        block.engine = try self.alloc.dupe(u8, line.tokens[1]);
                    } else {
                        block.engine = "InnoDB";
                    }
                },
                .SQLComment => {
                    if (block.mode == .none) {
                        try sql_comments.append(self.alloc, .{
                            .text = line.raw,
                            .line_no = line.line_no,
                        });
                    }
                },
                .Import => {
                    // @import lines are handled at the pipeline level, not here
                },
                .ConditionalIf => {
                    // @if(dialect=pg|sqlite) — start a conditional block within a table
                    if (block.mode == .table) {
                        if (block.pending_if_dialects != null) {
                            diag.printDiagnostic(self.alloc, .{
                                .severity = .@"error",
                                .line_no = line.line_no,
                                .message = "nested @if blocks are not supported",
                                .source_line = line.raw,
                            });
                            continue;
                        }
                        // Parse @if(dialect=pg|sqlite) or @if(dialect=pg)
                        const dialects = self.parseIfDialects(line) catch |err| {
                            if (!self.handleParseError(err, line, "failed to parse @if dialect list")) continue;
                            continue;
                        };
                        block.pending_if_dialects = dialects;
                        block.pending_if_start = block.fields.items.len;
                    } else {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "@if conditional block outside table — ignored",
                            .source_line = line.raw,
                        });
                    }
                },
                .ConditionalEnd => {
                    // @endif — close the current conditional block
                    if (block.mode == .table and block.pending_if_dialects != null) {
                        const dialects = block.pending_if_dialects.?;
                        const start = block.pending_if_start;
                        const end = block.fields.items.len;
                        try block.conditional_blocks.append(self.alloc, .{
                            .dialects = dialects,
                            .start_field = start,
                            .end_field = end,
                            .line_no = line.line_no,
                        });
                        block.pending_if_dialects = null;
                        block.pending_if_start = 0;
                    } else {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "@endif without matching @if — ignored",
                            .source_line = line.raw,
                        });
                    }
                },
                .Version => {
                    // @version X.Y.Z — schema version metadata
                    // The tokenizer splits @version into @ and version, so we need to extract
                    // the version string from the raw line after the @version prefix.
                    const raw = line.trimmed;
                    if (raw.len > 8) { // "@version" is 8 chars
                        const ver_str = std.mem.trim(u8, raw[8..], " \t");
                        if (ver_str.len > 0) {
                            version = try self.alloc.dupe(u8, ver_str);
                        } else {
                            diag.printDiagnostic(self.alloc, .{
                                .severity = .warning,
                                .line_no = line.line_no,
                                .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                                .message = "@version requires a version string — ignored",
                                .source_line = line.raw,
                            });
                        }
                    } else {
                        diag.printDiagnostic(self.alloc, .{
                            .severity = .warning,
                            .line_no = line.line_no,
                            .col = if (line.tokens.len > 0) diag.tokenColumn(line.tokens[0], line.raw) else null,
                            .message = "@version requires a version string — ignored",
                            .source_line = line.raw,
                        });
                    }
                },
            }
        }

        // Flush last block — catch allocation errors gracefully
        if (block.mode == .template) {
            self.flushCurrentTemplate(&templates, &block) catch |err| {
                diag.printDiagnostic(self.alloc, .{
                    .severity = .@"error",
                    .line_no = block.line_no,
                    .message = "failed to flush template block",
                    .actual = @errorName(err),
                });
            };
        } else if (block.mode == .table) {
            self.flushCurrentTable(&tables, &block) catch |err| {
                diag.printDiagnostic(self.alloc, .{
                    .severity = .@"error",
                    .line_no = block.line_no,
                    .message = "failed to flush table block",
                    .actual = @errorName(err),
                });
            };
        } else if (block.mode == .composite) {
            self.flushCurrentComposite(&composites, &block);
        }

        // Merge custom_types into schema
        const final_schema = if (schema) |s| blk: {
            if (custom_types.items.len > 0) {
                break :blk ast_mod.Schema{
                    .name = s.name,
                    .charset = s.charset,
                    .autofk = s.autofk,
                    .custom_types = try custom_types.toOwnedSlice(self.alloc),
                    .version = version,
                    .line_no = s.line_no,
                    .loc = s.loc,
                };
            }
            break :blk ast_mod.Schema{
                .name = s.name,
                .charset = s.charset,
                .autofk = s.autofk,
                .custom_types = &.{},
                .version = version,
                .line_no = s.line_no,
                .loc = s.loc,
            };
        } else null;

        // Clean up block state (frees ArrayList internal buffers)
        block.deinit(self.alloc);

        // Convert ArrayLists to owned slices
        const templates_slice = try templates.toOwnedSlice(self.alloc);
        const tables_slice = try tables.toOwnedSlice(self.alloc);
        const views_slice = try views.toOwnedSlice(self.alloc);
        const sql_comments_slice = try sql_comments.toOwnedSlice(self.alloc);
        const composites_slice = try composites.toOwnedSlice(self.alloc);

        // Free ArrayList internal buffers (toOwnedSlice transfers ownership of items)
        templates.deinit(self.alloc);
        tables.deinit(self.alloc);
        views.deinit(self.alloc);
        sql_comments.deinit(self.alloc);
        custom_types.deinit(self.alloc);
        composites.deinit(self.alloc);

        return .{
            .schema = final_schema,
            .templates = templates_slice,
            .tables = tables_slice,
            .views = views_slice,
            .sql_comments = sql_comments_slice,
            .composites = composites_slice,
        };
    }

    /// Parse @if(dialect=pg|sqlite) → list of dialect names.
    fn parseIfDialects(self: *Parser, line: tk.Line) ![]const []const u8 {
        // line.raw should be something like "@if(dialect=pg|sqlite)"
        const raw = line.raw;
        // Find the opening paren
        const paren_start = std.mem.indexOf(u8, raw, "(") orelse return error.MissingParen;
        // Find the closing paren
        const paren_end = std.mem.indexOf(u8, raw[paren_start..], ")") orelse return error.MissingParen;
        const inner = raw[paren_start + 1 .. paren_start + paren_end];
        // Parse "dialect=pg|sqlite" or "dialect=pg"
        if (!std.mem.startsWith(u8, inner, "dialect=")) return error.InvalidCondition;
        const dialect_str = inner[8..]; // skip "dialect="
        if (dialect_str.len == 0) return error.EmptyDialectList;
        // Split by |
        var dialects = try std.ArrayList([]const u8).initCapacity(self.alloc, 4);
        var it = std.mem.splitScalar(u8, dialect_str, '|');
        while (it.next()) |d| {
            if (d.len > 0) {
                try dialects.append(self.alloc, try self.alloc.dupe(u8, d));
            }
        }
        if (dialects.items.len == 0) return error.EmptyDialectList;
        return try dialects.toOwnedSlice(self.alloc);
    }

    fn flushCurrentTable(
        self: *Parser,
        tables: *std.ArrayList(Table),
        block: *BlockState,
    ) !void {
        // If there's an unclosed @if block, close it with a warning
        if (block.pending_if_dialects != null) {
            diag.printDiagnostic(self.alloc, .{
                .severity = .warning,
                .line_no = block.line_no,
                .message = "unclosed @if block at end of table — fields included unconditionally",
            });
            block.pending_if_dialects = null;
        }
        try tables.append(self.alloc, .{
            .template_ref = block.template_ref,
            .name = block.name orelse "",
            .comment = block.comment,
            .doc = block.doc,
            .engine = block.engine,
            .fields = try block.fields.toOwnedSlice(self.alloc),
            .fks = try block.fks.toOwnedSlice(self.alloc),
            .indexes = try block.indexes.toOwnedSlice(self.alloc),
            .conditional_blocks = try block.conditional_blocks.toOwnedSlice(self.alloc),
            .embeds = try block.embeds.toOwnedSlice(self.alloc),
            .line_no = block.line_no,
            .loc = block.loc,
        });
    }

    fn flushCurrentComposite(
        self: *Parser,
        composites: *std.ArrayList(ast_mod.Composite),
        block: *BlockState,
    ) void {
        if (block.fields.items.len == 0) {
            diag.printDiagnostic(self.alloc, .{
                .severity = .@"error",
                .line_no = block.line_no,
                .message = std.fmt.allocPrint(self.alloc, "composite '{s}' has no fields", .{block.name orelse ""}) catch "composite has no fields",
            });
            return;
        }
        composites.append(self.alloc, .{
            .name = block.name orelse "",
            .fields = block.fields.toOwnedSlice(self.alloc) catch &.{},
            .line_no = block.line_no,
            .loc = block.loc,
        }) catch {};
    }

    fn flushCurrentTemplate(
        self: *Parser,
        templates: *std.ArrayList(Template),
        block: *BlockState,
    ) !void {
        try parse_template.flushTemplate(self.alloc, templates, block.name, block.parents_buf, block.parents_len, &block.fields, block.doc, block.line_no, block.loc);
    }

    // ─── Public API: delegated functions ────────────────────

    /// Public API: parse type token. Delegates to parse_field module.
    pub fn tryParseType(tok: []const u8) ?TypeInfo {
        return parse_field.tryParseType(tok);
    }

    /// Public API: classify CHECK constraint. Delegates to parse_check module.
    pub fn classifyCheck(expr: []const u8, open_bracket: u8, close_bracket: u8) CheckKind {
        return parse_check.classifyCheck(expr, open_bracket, close_bracket);
    }
};

// ─── Diagnostic Trace ────────────────────────────────────────

pub const diagnosticTrace = parse_trace.diagnosticTrace;
