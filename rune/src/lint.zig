// ─── Lint: Re-export Barrel ─────────────────────────────────────
//
// Split from the original 1017-line monolith into focused modules:
//   lint/rules.zig   — individual lint rule implementations (20 rules)
//   lint/format.zig  — text/JSON/SARIF output formatters
//   lint/config.zig  — LintConfig, TOML config parsing, apply
//   lint/fix.zig     — auto-fix logic (no-pk, no-timestamps)
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
pub const lintFix = fix_mod.fix;
