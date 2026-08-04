// ─── CLI: Re-export Barrel ──────────────────────────────────────
//
// Split from the original 792-line monolith into three focused modules:
//   cli/types.zig  — type definitions (Command, ParsedArgs, enums)
//   cli/parse.zig  — argument parsing and flag detection
//   cli/help.zig   — help text and usage printing
//
// This barrel re-exports everything so existing callers keep working.

const types = @import("cli/types.zig");
const parse = @import("cli/parse.zig");
const help = @import("cli/help.zig");

// Re-export all public symbols from sub-modules.
pub const Target = types.Target;
pub const DiffFormat = types.DiffFormat;
pub const StatsFormat = types.StatsFormat;
pub const Command = types.Command;
pub const ParsedArgs = types.ParsedArgs;
pub const ColorMode = types.ColorMode;
pub const ArgError = types.ArgError;
pub const GlobalFlags = types.GlobalFlags;
pub const CommandInfo = types.CommandInfo;
pub const COMMAND_REGISTRY = types.COMMAND_REGISTRY;
pub const KNOWN_FLAGS = types.KNOWN_FLAGS;

pub const parseArgs = parse.parseArgs;
pub const parseDialect = parse.parseDialect;
pub const findUnknownFlag = parse.findUnknownFlag;
pub const suggestSimilarFlag = parse.suggestSimilarFlag;

pub const printUsage = help.printUsage;
pub const printSubcommandHelp = help.printSubcommandHelp;
