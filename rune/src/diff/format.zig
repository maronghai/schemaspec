// ─── Diff Formatter ──────────────────────────────────────────
//
// Re-exports format sub-modules for backward compatibility.
// Implementations are split into sub-modules by output format.

const text_fmt = @import("format/text.zig");
const json_fmt = @import("format/json.zig");
const sarif_fmt = @import("format/sarif.zig");
const markdown_fmt = @import("format/markdown.zig");

// Re-export text format
pub const writeDiffTo = text_fmt.writeDiffTo;
pub const formatDiff = text_fmt.formatDiff;
pub const formatDiffSummary = text_fmt.formatDiffSummary;
pub const printDiff = text_fmt.printDiff;

// Re-export JSON format
pub const formatDiffJson = json_fmt.formatDiffJson;

// Re-export SARIF format
pub const formatDiffSarif = sarif_fmt.formatDiffSarif;

// Re-export Markdown format
pub const formatDiffMarkdown = markdown_fmt.formatDiffMarkdown;

// Re-export shared format helpers
pub const format_common = @import("format_common.zig");
pub const formatTypeInfo = format_common.formatTypeInfo;
