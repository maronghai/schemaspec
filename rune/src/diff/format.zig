const std = @import("std");
const diff_types = @import("../diff/types.zig");
const dialect_mod = @import("../dialect/dialect.zig");
const utils = @import("../utils.zig");
const SchemaDiff = diff_types.SchemaDiff;
const TableDiff = diff_types.TableDiff;
const Dialect = @import("../dialect/enum.zig").Dialect;

const optionalStrEq = utils.optionalStrEq;
const jsonEscapeString = utils.jsonEscapeString;

// ─── Diff Formatter ──────────────────────────────────────────
//
// Renders SchemaDiff as human-readable text for `rune diff`.
// Separated from diff.zig to allow alternative output formats
// (JSON, machine-readable) without modifying the diff engine.
//
// Implementations are split into sub-modules by output format.
// This file re-exports the public API for backward compatibility.

const text_fmt = @import("format/text.zig");
const json_fmt = @import("format/json.zig");
const sarif_fmt = @import("format/sarif.zig");

// Re-export text format
pub const writeDiffTo = text_fmt.writeDiffTo;
pub const formatDiff = text_fmt.formatDiff;
pub const printDiff = text_fmt.printDiff;

// Re-export JSON format
pub const formatDiffJson = json_fmt.formatDiffJson;

// Re-export SARIF format
pub const formatDiffSarif = sarif_fmt.formatDiffSarif;
