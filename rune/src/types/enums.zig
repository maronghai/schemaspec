const color_mod = @import("../color.zig");

// ─── Shared Enums ──────────────────────────────────────────────
// Enums used by both CLI and pipeline layers.
// Lives in types/ to avoid pipeline → CLI coupling.

pub const Target = enum { sql, json_schema };

pub const DiffFormat = enum { text, json, sarif, markdown };

pub const StatsFormat = enum { text, json, markdown };

pub const ColorMode = color_mod.ColorMode;
