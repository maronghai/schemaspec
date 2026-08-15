// ─── Lint: Re-export Barrel ─────────────────────────────────────
//
// Split from the original 1017-line monolith into focused modules:
//   lint/rules.zig        — individual lint rule implementations (80 rules)
//   lint/format.zig       — text/JSON/SARIF output formatters
//   lint/config.zig       — LintConfig, TOML config parsing, apply
//   lint/fix.zig          — auto-fix orchestrator (line-by-line dispatch)
//   lint/fix_helpers.zig  — shared types and helpers (LintFix, buildFixMaps)
//   lint/fix_structural.zig — no-pk, no-timestamps, empty-table handlers
//   lint/fix_modifier.zig — serial-type, bool-default, nullable-default, column-default
//   lint/fix_index.zig    — duplicate-index, no-index-fk, duplicate-column handlers
//   lint/handlers/        — category-based rule handlers (structural, naming, validation, etc.)
//
// This barrel re-exports everything so existing callers keep working.

const rules = @import("lint/rules.zig");
const config = @import("lint/config.zig");
const fmt = @import("lint/format.zig");
const fix_mod = @import("lint/fix.zig");

// Types — shared across all sub-modules
pub const LintSeverity = config.LintSeverity;
pub const LintResult = config.LintResult;
pub const LintConfig = config.LintConfig;
pub const RuleSet = config.RuleSet;
pub const LintDiffResult = config.LintDiffResult;
pub const LintFix = fix_mod.LintFix;
pub const LintRulesConfig = config.LintRulesConfig;

// Functions — re-export from sub-modules
pub const lintSchema = rules.runAll;
pub const lintDiff = config.lintDiff;
pub const parseLintRules = config.parseLintRules;
pub const applyLintRules = config.applyLintRules;
pub const formatLintResults = fmt.formatText;
pub const formatLintJson = fmt.formatJson;
pub const formatLintSarif = fmt.formatSarif;
pub const formatLintSummary = fmt.formatSummary;
pub const lintFix = fix_mod.fix;
