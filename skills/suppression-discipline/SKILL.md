---
name: suppression-discipline
description: The rule for suppressing static-analysis findings in any language — every suppression carries an inline rationale, and bare suppressions are a quality failure to fix. Use when someone adds or proposes a lint/analysis ignore (# skylos: ignore, # noqa, # type: ignore, # fallow-ignore, // eslint-disable, @ts-ignore, #[allow(...)], //nolint, etc.), proposes bypassing hooks with --no-verify / LEFTHOOK=0, or when reviewing code that contains suppressions. Litmus: every ignore in the tree says *why*, or it gets ripped out.
---

# Suppression discipline

Advisory standard — fires on the situation in the description. The standing rule that governs the gate the `quality-stack-setup` skill installs.

## The rule

Every suppression of a static-analysis finding — in **any language** — must carry an **inline rationale on the same line or directly above it**. A bare suppression is a quality failure to fix, not a workaround.

Canonical forms, by ecosystem:

| Directive | Language / tool | Required rationale form |
|---|---|---|
| `# skylos: ignore SKY-XXX` | Python (skylos) | `— <reason>` suffix or `# Why:` line above |
| `# noqa: E501` | Python (ruff/flake8) | `# Why:` line above |
| `# type: ignore[code]` | Python (mypy/pyright) | `— <reason>` on the same line |
| `# fallow-ignore` | TS/JS (fallow) | `// Why:` line above |
| `// eslint-disable-next-line rule` | TS/JS (eslint) | `-- <reason>` after the rule, or `// Why:` above |
| `// @ts-expect-error` / `@ts-ignore` | TypeScript | description text on the same line |
| `#[allow(clippy::x)]` | Rust | `// Why:` line above |
| `//nolint:linter` | Go (golangci-lint) | `// <reason>` after the directive |

The mechanism differs per tool; the rule does not. Example:

```python
# skylos: ignore SKY-D216 — url built from a hardcoded constant; host is not user-controlled
```
```typescript
// Why: third-party type is wrong here; upstream issue #4421 tracks the fix
// @ts-expect-error
```
```rust
// Why: the match is exhaustive by construction; clippy can't see the invariant
#[allow(clippy::match_same_arms)]
```

## Why

It's trivial to silence a finding and never come back. The inline rationale forces the next reader to either **trust** the suppression (specific, defensible reason) or **rip it out** (vague-or-missing reason → the finding was real). A suppression without a reason is indistinguishable from "the linter was in my way," which is exactly the regression this discipline exists to prevent.

This is the same principle the whole quality stack enforces end to end: lefthook blocks the commit/push and the CI required check blocks the merge, and a defensible rationale is the only sanctioned way through. `--no-verify` and `LEFTHOOK=0` are not — they bypass the gate entirely rather than justifying a single finding.

## How to apply

### When you see a bare suppression in code

Either:
- **Restore the rule** — delete the suppression and fix what it flagged, or
- **Add the rationale** — a one-sentence reason why the rule's *application at this site* is wrong (not why the rule shouldn't exist).

Bare suppressions older than this rule are quality debt — sweep them in passing when you touch the file.

### When someone proposes `--no-verify` / `LEFTHOOK=0`

Push back unless there's a documented operator-escape rationale (e.g. a CLAUDE.md that explicitly documents `LEFTHOOK_EXCLUDE=<command>` for a specific missing-token case). Otherwise the hook is firing for a reason — fix the issue or write a defensible per-site suppression.

### When a hook is actively blocking a commit

Triage each finding into one of three outcomes — **fix in code**, **suppress with a required `# Why:`**, or **defer to tracked tech-debt** — and refuse bare suppressions. Cap new suppressions per change (a couple at most); a burst of fresh ignores in one diff is itself the smell. Try-to-fix-first; justify only what you genuinely can't.

## Litmus

Every static-analysis ignore in the tree carries a specific, defensible reason a reviewer can either trust or reject on sight — there are no bare suppressions, and `--no-verify` is never the answer to a finding.

## Related

- `quality-stack-setup` — installs the lefthook hooks + `just verify` gate this discipline governs.
- `quality-verify-hook` — proves those hooks actually fire (so a suppression is the *only* way past a real finding, not a silent skip).
