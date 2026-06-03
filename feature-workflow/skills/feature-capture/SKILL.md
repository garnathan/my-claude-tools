---
name: feature-capture
description: Interactively capture a new backlog item — run a focused interview, then write docs/features/<id>/idea.md with valid frontmatter and Problem Statement / Proposed Solution / Affected Areas sections (the WHAT and WHY, never the HOW). Captures one idea.md only; the feature stays in the Backlog until /feature-plan adds plan.md. Use when the user wants to add a feature, track an idea, file a bug or tech-debt item, or says something belongs "in the backlog". Litmus: a unique kebab-case docs/features/<id>/idea.md exists with required frontmatter and the auto-generated dashboard now lists it under Backlog.
allowed-tools: Read, Write, AskUserQuestion
---

# feature-capture — add an item to the backlog

Run a short interview, validate the ID, and write a single `idea.md`. Writing it triggers the PostToolUse hook, which regenerates `DASHBOARD.md` — **never** write or edit `DASHBOARD.md` yourself (a PreToolUse hook blocks it).

## Step 1 — Check setup, then scan for duplicates

Read `docs/features/DASHBOARD.md`. If `docs/features/` doesn't exist, stop and tell the user: *"Run `/feature-init` first to set up the feature workflow."* Do not create the structure yourself.

If it exists, scan the tables for existing feature IDs so you can reject a duplicate later.

## Step 2 — Interview

Capture the WHAT and WHY, not the HOW (no designs, no architecture — that's `/feature-plan`). Use `AskUserQuestion`, batching related questions. Required:

1. **Type** — `Feature` (new capability) · `Enhancement` (improve existing) · `Tech Debt` · `Bug Fix` · `Epic` (umbrella for child features).
2. **Name** — short descriptive name; you'll kebab-case it into the `id`. *"Dark Mode Toggle" → `dark-mode-toggle`.*
3. **Problem statement** — 1–3 sentences on the pain point and who it affects.
4. **Priority** — `P0` (critical, blocks others) · `P1` (important, soon) · `P2` (nice to have).
5. **Effort** — `Small` (<1 day) · `Medium` (1–3 days) · `Large` (>3 days).
6. **Impact** — `Low` · `Medium` · `High`.
7. **Affected areas** — comma-separated parts of the system (e.g. `frontend/settings, backend/api`), or blank.

Optional (offer, accept blanks):

- **epic** — parent epic ID. If given, check `docs/features/<epic-id>/idea.md` exists with `type: Epic`; if not, accept the value but warn that the epic should be captured first. The hook's `sync_epics` step mirrors this onto the epic's `children:` automatically — no manual edit.
- **dependsOn** — hard blockers (feature IDs). Soft-warn on IDs that don't exist yet (may be pre-capturing). Do **not** write `blockedBy:` on the targets — blocked-by is computed from the graph.
- **relatedTo** — soft "see also" links (feature IDs).
- **assignee** — single name or list.
- **parallelSafe** — default `true`; set `false` if it touches files other in-flight features touch.
- **category** — grouping (e.g. `coding`, `infra`); defaults to `general`.

## Step 3 — Validate the ID

- Kebab-case the name: lowercase, strip punctuation, spaces → hyphens.
- Reject duplicates two ways: an ID match in `DASHBOARD.md` **and** an existing `docs/features/<id>/` directory. On a clash, ask for a different name — do not overwrite.

## Step 4 — Write idea.md (one write, frontmatter included)

Write `docs/features/<id>/idea.md`. Include only fields you captured; omit the rest. Valid frontmatter keys (these only): `id`, `name`, `type`, `priority`, `effort`, `impact`, `category`, `created`, `dependsOn`, `relatedTo`, `parallelSafe`, `assignee`, `epic`, `children`, `state`, `pausedReason`, `replacedBy`, `abandonedReason`, `replaces`, `review`.

```markdown
---
id: dark-mode-toggle
name: Dark Mode Toggle
type: Feature            # Feature | Enhancement | Tech Debt | Bug Fix | Epic
priority: P1             # P0 | P1 | P2
effort: Medium           # Small | Medium | Large
impact: High             # Low | Medium | High
category: frontend
created: 2026-06-03
# optional: dependsOn: [theme-engine]
# optional: relatedTo: [settings-page]
# optional: epic: ui-refresh
# optional: assignee: court
# optional: parallelSafe: false
# optional: review: external   # external | internal | skip — overrides project default
---

# Dark Mode Toggle

## Problem Statement
The WHAT and WHY — the pain point and who it affects.

## Proposed Solution
High-level direction only, if the user offered one. Keep it brief; omit if none.

## Affected Areas
- frontend/settings
- backend/api
```

Notes on optional state/relation fields:
- `state:` defaults to `active` (omit it). For a non-active capture use `paused` + `pausedReason`, `replaced` + `replacedBy`, or `abandoned` + `abandonedReason`.
- `children:` is only for `type: Epic`. `replaces:` (this feature supersedes those IDs) triggers the hook to tombstone them.
- `review:` is a per-feature override; resolution against project config lives in [../shared/config.md](../shared/config.md).

## Step 5 — Confirm

The PostToolUse hook regenerates `DASHBOARD.md` (and runs `sync_epics` / `sync_replaces`) on the idea.md write — do nothing manual. Then show:

```
## Added to Backlog
ID: <id>   Name: <name>
<type> · <priority> · <effort> · <impact>
File: docs/features/<id>/idea.md

Next: /feature-plan <id> when ready to start.
```

Briefly mention the new backlog count if the dashboard shows it.
