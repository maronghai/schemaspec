# RFC-0001: RFC Process

- **RFC:** RFC-0001
- **Title:** Establish RFC Process for Language Changes
- **Author:** Rune Team
- **Status:** Accepted
- **Created:** 2026-08-11
- **Updated:** 2026-08-11

## Summary

Establish a formal Request for Comments (RFC) process for proposing and discussing changes to the `.ss` language, pipeline behavior, and generator system.

## Motivation

As Rune matures, language changes and architectural decisions need structured discussion before implementation. An RFC process ensures:
- Changes are well-documented before coding begins
- Community input is gathered early
- Design decisions are recorded for future reference
- Breaking changes receive appropriate review

## Detailed Design

### Process

1. **Proposal** — Author creates `rfcs/NNNN-title.md` from the template
2. **Discussion** — RFC is reviewed via GitHub Issues or PR comments
3. **Decision** — Status changes to Accepted, Rejected, or Superseded
4. **Implementation** — Accepted RFCs are implemented with version tags

### Scope

RFCs are required for:
- New language keywords or syntax changes
- Breaking changes to existing behavior
- New generator types or significant generator changes
- Pipeline architecture changes
- New CLI commands or flags that change UX

RFCs are NOT required for:
- Bug fixes
- Performance improvements (unless they change API)
- Documentation updates
- Test coverage additions
- Refactoring (no behavior change)

### Numbering

RFCs are numbered sequentially: RFC-0001, RFC-0002, etc. The number is assigned when the RFC is first committed.

## Alternatives Considered

- **GitHub Discussions only** — Less structured, harder to track decisions
- **Issue-based proposals** — Lack formal structure for complex changes
- **No process** — Works for small projects but doesn't scale

## Impact

- Backward compatibility: None (process-only change)
- Performance: None
- Testing: None

## Decision

Accepted. The RFC process is now the standard mechanism for proposing language and architectural changes to Rune.
