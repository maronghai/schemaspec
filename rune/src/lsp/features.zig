const std = @import("std");
const protocol = @import("protocol.zig");
const Dialect = @import("../dialect/enum.zig").Dialect;

// ─── LSP Features ───────────────────────────────────────────
// Facade module that re-exports LSP feature implementations.
// Each feature lives in its own sub-module for maintainability.

pub const makeRange = @import("helpers.zig").makeRange;

// Re-export all feature modules
pub const document_symbols = @import("document_symbols.zig");
pub const completions_mod = @import("completions.zig");
pub const hover_mod = @import("hover.zig");
pub const go_to_definition = @import("go_to_definition.zig");
pub const code_actions = @import("code_actions.zig");
pub const rename_mod = @import("rename.zig");
pub const references_mod = @import("references.zig");
pub const highlights_mod = @import("highlights.zig");
pub const folding_range_mod = @import("folding_range.zig");
pub const type_definition_mod = @import("type_definition.zig");

// Convenience re-exports for callers that import features.zig directly
pub const getDocumentSymbols = document_symbols.getDocumentSymbols;
pub const getCompletions = completions_mod.getCompletions;
pub const getHover = hover_mod.getHover;
pub const getDefinition = go_to_definition.getDefinition;
pub const getCodeActions = code_actions.getCodeActions;
pub const prepareRename = rename_mod.prepareRename;
pub const getRenameLinks = rename_mod.getRenameLinks;
pub const RenameResult = rename_mod.RenameResult;
pub const getReferences = references_mod.getReferences;
pub const getDocumentHighlights = highlights_mod.getDocumentHighlights;
pub const getFoldingRanges = folding_range_mod.getFoldingRanges;
pub const getTypeDefinition = type_definition_mod.getTypeDefinition;

pub const getFormatting = @import("formatting.zig").getFormatting;
