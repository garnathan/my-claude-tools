---
name: feature-ship
description: Complete a feature — run final quality gates, write shipped.md, and merge the PR (GitHub or Bitbucket) or merge locally, then regenerate the dashboard. Use when the implementation review has passed and the feature is ready to land. Litmus: shipped.md exists, the change is merged into the target branch, and the dashboard shows the feature Completed.
allowed-tools: Read, Write, Edit, Bash, Agent
---

# feature-ship — gate, record, merge

Land a reviewed feature. Read [../shared/config.md](../shared/config.md) (branch + `review.provider`) and [../shared/review-channel.md](../shared/review-channel.md) (provider merge op) first. Throughout, substitute `<prefix><id>` and `<target>` from config.

## Arguments

`$ARGUMENTS`: optional `<feature-id>`. If absent, render the dashboard (`python3 "${CLAUDE_PLUGIN_ROOT}/skills/shared/lib/run_dashboard.py" . --stdout`) and help the user pick from In Progress.

## Phase 1 — Pre-flight

1. Read the feature's `idea.md` + `plan.md`; confirm it's **in progress** (has `plan.md`, no `shipped.md`).
2. Resolve `provider` from config. If `provider != none`, find the open PR for `<prefix><id>` (review-channel.md "get PR for branch"). If there's no PR, warn — the user may want `/feature-review-impl <id>` first, or to proceed with a local merge.
3. Be on the feature branch: `git checkout <prefix><id>`.

## Phase 2 — Final quality gates (scaled by effort)

Read `effort` from `idea.md`. **The hard rule applies: unit tests passing is never sufficient — verify user-facing behavior.**

- **Small (< ~8h):** run the project's checks directly — `just verify` if present, else the repo's test + lint + a dependency/security scan (e.g. `npm audit --audit-level=high`).
- **Medium / Large:** the above **plus** a focused review pass — dispatch a `general-purpose` subagent (or use `/verify` / `/ui-verify` / `/bug-hunt` if the change warrants) to confirm the implementation does what the plan said and check security-sensitive paths. Fix anything Blocking before continuing.

Don't ship on red. If a gate fails, stop and surface it.

## Phase 3 — Write shipped.md

Write `docs/features/<id>/shipped.md`:

```markdown
---
shipped: YYYY-MM-DD
---

# Shipped: <Feature Name>

## Summary
What was delivered.

## Key Changes
- …

## Files Changed
- `path/to/file`

## Testing
How it was verified (the real evidence, not just "tests pass").

## Notes
Follow-ups, known limitations, context for maintainers.
```

Populate from `plan.md`, commit messages, and the diff. Commit + push to the feature branch:

```bash
git add docs/features/<id>/shipped.md
git commit -m "docs(<id>): mark feature as shipped"
git push
```

(The PostToolUse hook regenerates `DASHBOARD.md` locally on this write.)

## Phase 4 — Merge

Confirm with the user: **"Merge <prefix><id> into <target>?"** Then:

- **`provider: github` / `bitbucket`** → merge via review-channel.md's "merge the PR" op (mark ready / drop `[WIP]` first if needed), deleting the remote branch. Then locally: `git checkout <target> && git pull && git branch -d <prefix><id>`.
- **`provider: none`** → local merge: `git checkout <target> && git merge --no-ff <prefix><id> && git branch -d <prefix><id>` (and push `<target>` if it has a remote).

## Phase 5 — Finish

Regenerate the dashboard on `<target>` (shipped.md is now merged):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/shared/lib/run_dashboard.py" .
```

Report:

```
## Feature Shipped
Feature: <name>   ID: <id>
Merged into: <target>   Shipped: YYYY-MM-DD
Dashboard updated — feature now Completed.
```

## Fallback — script

If `shipped.md` wasn't written (and you just need the record + dashboard, no merge):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/feature-ship/scripts/ship_feature.py" . <feature-id> "Summary"
```

## Errors

| Error | Resolution |
|---|---|
| Not in progress | Point to `/feature-plan` (backlog) or note it's already shipped |
| No PR (provider ≠ none) | Suggest `/feature-review-impl`, or offer a local merge |
| Not on feature branch | `git checkout <prefix><id>` |
| Quality gate failed | Stop, surface it — don't ship on red |
