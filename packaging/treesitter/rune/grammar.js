/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: "rune",

  extras: ($) => [/\s/, $.comment],

  rules: {
    source_file: ($) => repeat($._line),

    _line: ($) =>
      choice(
        $.schema_declaration,
        $.type_definition,
        $.template_declaration,
        $.table_declaration,
        $.view_declaration,
        $.import_directive,
        $.version_directive,
        $.conditional_if,
        $.conditional_end,
        $.doc_directive,
        $.fk_declaration,
        $.index_declaration,
        $.composite_pk,
        $.slot_marker,
        $.field_declaration,
      ),

    // ── Comments ──────────────────────────────────────────────

    comment: ($) =>
      token(
        choice(
          seq("--", /[^\n]*/),
          seq(";", /[^\n]*/),
        ),
      ),

    // ── Schema Declaration ────────────────────────────────────

    schema_declaration: ($) =>
      seq(
        "$",
        optional($.identifier),
        optional($.identifier),
        optional("autofk"),
      ),

    // ── Custom Type Definition ────────────────────────────────

    type_definition: ($) =>
      seq(
        "~",
        field("name", $.identifier),
        field("base_type", $._type_spec),
        repeat($.dialect_override),
      ),

    dialect_override: ($) =>
      seq(field("dialect", $.identifier), "=", field("type", $._type_spec)),

    // ── Template Declaration ──────────────────────────────────

    template_declaration: ($) =>
      seq(
        "%",
        optional(field("name", $.identifier)),
        optional(
          seq(
            ">",
            commaSep1(field("parent", $.identifier)),
          ),
        ),
      ),

    // ── Table Declaration ─────────────────────────────────────

    table_declaration: ($) =>
      prec(
        1,
        seq(
          "#",
          optional(field("template_ref", $.identifier)),
          field("name", $.identifier),
          optional(seq(":", field("comment", $.comment_text))),
          optional(seq("^", optional(field("view", $.identifier)))),
        ),
      ),

    // ── View Declaration ──────────────────────────────────────

    view_declaration: ($) =>
      seq(
        "&",
        field("name", $.identifier),
        "=",
        field("query", $.sql_text),
      ),

    // ── Import Directive ──────────────────────────────────────

    import_directive: ($) =>
      seq("@import", field("path", choice($.string, $.file_path))),

    file_path: ($) => /[^\s"']+/,

    // ── Version Directive ─────────────────────────────────────

    version_directive: ($) =>
      seq(
        "@version",
        field("version", /\d+\.\d+\.\d+/),
      ),

    // ── Conditional Block ────────────────────────────────────

    conditional_if: ($) =>
      seq(
        "@if(",
        "dialect",
        "=",
        field("dialects", commaSep1($.identifier)),
        ")",
      ),

    conditional_end: () => "@endif",

    // ── Documentation Directive ───────────────────────────────

    doc_directive: ($) => seq("+", field("text", /[^\n]*/)),

    // ── Foreign Key Declaration ───────────────────────────────

    fk_declaration: ($) =>
      prec(
        2,
        seq(
          ">",
          field("table", $.identifier),
          field("column", $.identifier),
          optional(seq(".", field("ref_column", $.identifier))),
          optional($.fk_actions),
        ),
      ),

    fk_actions: ($) => repeat1($._fk_action),

    _fk_action: ($) => choice($.fk_delete_cascade, $.fk_delete_null, $.fk_update_cascade, $.fk_update_null),

    fk_delete_cascade: () => "C",
    fk_delete_null: () => "N",
    fk_update_cascade: () => "c",
    fk_update_null: () => "n",

    // ── Index Declaration ─────────────────────────────────────

    index_declaration: ($) =>
      prec(
        2,
        seq(
          "@",
          optional(field("type", choice("u", "f"))),
          optional(field("name", $.identifier)),
          choice(
            seq("(", commaSep1($.identifier), ")"),
            commaSep1($.identifier),
          ),
        ),
      ),

    // ── Composite Primary Key ────────────────────────────────

    composite_pk: ($) => prec(2, seq("!", commaSep1($.identifier))),

    // ── Slot Marker ──────────────────────────────────────────

    slot_marker: () => "...",

    // ── Field Declaration ─────────────────────────────────────

    field_declaration: ($) =>
      prec(
        0,
        seq(
          field("name", $.identifier),
          optional(field("type", $._type_spec)),
          optional(field("modifiers", $.modifiers)),
          optional(field("default", $._default_value)),
          optional(field("check", $._check_constraint)),
          optional(field("inline_fk", $.inline_fk)),
          optional(seq(":", field("comment", $.comment_text))),
        ),
      ),

    inline_fk: ($) =>
      prec(
        3,
        seq(
          optional(">"),
          field("table", $.identifier),
          ".",
          optional(field("ref_column", $.identifier)),
          optional($.fk_actions),
        ),
      ),

    // ── Type Specification ────────────────────────────────────

    _type_spec: ($) =>
      choice(
        $.simple_type,
        $.int_type,
        $.decimal_type,
        $.varchar_type,
        $.enum_type,
        $.passthrough_type,
      ),

    simple_type: () =>
      token(
        choice(
          "n", "N", "i", "m", "M", "s", "S",
          "b", "B", "j", "J", "I",
          "d", "t", "T", "U", "p",
        ),
      ),

    int_type: () => token(/\d+/),

    decimal_type: () => token(/\d+,\d+/),

    varchar_type: () => token(/s\d+/),

    enum_type: ($) =>
      seq("e", "(", commaSep1($.string), ")"),

    passthrough_type: ($) => $.identifier,

    // ── Modifiers ─────────────────────────────────────────────

    modifiers: ($) => repeat1($._modifier),

    _modifier: ($) =>
      choice(
        $.auto_increment_pk,
        $.auto_increment,
        $.primary_key,
        $.nullable,
        $.unique_index,
        $.index,
      ),

    auto_increment_pk: () => token("++"),
    auto_increment: () => token("+"),
    primary_key: () => token("!"),
    nullable: () => token("?"),
    unique_index: () => token("@u"),
    index: () => token(/@(?!u)/),

    // ── Default Value ─────────────────────────────────────────

    _default_value: ($) =>
      prec(1, seq("=", choice($.default_null, $.default_current_timestamp, $.numeric, $.string, $.default_raw))),

    default_null: () => "NULL",
    default_current_timestamp: () => "CURRENT_TIMESTAMP",
    default_raw: () => /[^\s,:;\[\]{}()\n]+/,

    // ── CHECK Constraints ─────────────────────────────────────

    _check_constraint: ($) =>
      choice(
        $.range_check,
        $.in_list_check,
        $.comparison_check,
      ),

    range_check: ($) =>
      seq(
        choice("[", "("),
        $.check_expr,
        ",",
        $.check_expr,
        choice("]", ")"),
      ),

    in_list_check: ($) => seq("{", commaSep1($.check_expr), "}"),

    comparison_check: ($) =>
      seq("{", choice(">=", "<=", ">", "<", "="), $.check_expr, "}"),

    check_expr: () => /[^\],})\n]+/,

    // ── SQL Text ──────────────────────────────────────────────

    sql_text: () => /[^\n]+/,

    // ── Comment Text ──────────────────────────────────────────

    comment_text: () => /[^\n]+/,

    // ── Primitives ────────────────────────────────────────────

    identifier: () => /[a-zA-Z_][a-zA-Z0-9_]*/,

    string: ($) =>
      seq(
        "'",
        repeat(/[^'\n]/),
        "'",
      ),

    numeric: () => token(/-?\d+(\.\d+)?/),
  },
});

/**
 * Helper to create a comma-separated list of at least one element.
 * @param {Rule} rule
 * @returns {SeqRule}
 */
function commaSep1(rule) {
  return seq(rule, repeat(seq(",", rule)));
}
