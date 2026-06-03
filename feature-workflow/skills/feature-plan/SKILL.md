---
name: feature-plan
description: Turn a backlog idea.md into an approved implementation plan — read the idea, do requirements → design → implementation-breakdown directly in-session (scaled to effort), then write docs/features/<id>/plan.md with requirements, design, a step checklist, a testing strategy, and a Progress Log. Writing plan.md moves the feature to In Progress. Use when the user wants to start work on a backlog item, plan a feature before coding, or names a feature ID to plan. Litmus: docs/features/<id>/plan.md exists with `started:` frontmatter and the four required sections, and the auto-generated dashboard now lists the feature under In Progress.
allowed-tools: Read, Write, Edit, Bash, Agent
---

# feature-plan — plan a backlog feature before coding

Never code without a plan. This skill produces `plan.md` from an `idea.md`; it does the analysis itself in-session and writes one document. Writing `plan.md` triggers the PostToolUse hook, which moves the feature to In Progress and regenerates `DASHBOARD.md` — **never** write or edit `DASHBOARD.md` yourself (a PreToolUse hook blocks it).

`$ARGUMENTS` is the target feature ID (optionally `cat:<category>` to filter the backlog).

## Step 1 — Select the feature

Show the live backlog (this is a read, not a dashboard write):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/shared/lib/run_dashboard.py" . --stdout
```

If `docs/features/` doesn't exist, stop: *"Run `/feature-init` first."*

- **ID given** — find it in Backlog. If it's already In Progress (`plan.md` exists) or Completed (`shipped.md` exists), ask whether to continue/redo or pick another. With `cat:<category>`, list only matching features (P0 first) and ask the user to pick.
- **No ID** — list Backlog features (P0 first, category shown) and ask the user to pick.

Read the selected `docs/features/<id>/idea.md` for the full problem statement, type, priority, effort, impact, affected areas, and any proposed solution.

## Step 2 — State and dependency guard

Check the `state:` field in `idea.md`. Do **not** write `plan.md` in any stop case:

| State | Action |
|---|---|
| `active` (or absent) | Proceed. |
| `paused` | Stop: *"`<id>` is paused (waiting on: `<pausedReason>`). Revive it before planning."* |
| `replaced` | Stop: *"`<id>` was replaced by `<replacedBy>`. Plan that one, or revive this."* |
| `abandoned` | Stop: *"`<id>` was abandoned (`<abandonedReason>`). Revive it to plan."* |

Then read `dependsOn:`. For each ID, check it exists and is Completed. If any are unmet, warn (advisory only) and offer to continue, plan a dependency first, or cancel.

## Step 3 — Requirements, design, implementation breakdown (in-session)

Do this work directly. Scale depth to the feature's `effort`:

| Effort | Depth |
|---|---|
| Small (<1 day) | Essentials only — 2–3 acceptance criteria, key risks, skip a separate design narrative if trivial. |
| Medium (1–3 days) | Standard requirements + design + full step breakdown. |
| Large (>3 days) | Comprehensive — fuller acceptance criteria, design alternatives, finer-grained steps. |

1. **Requirements** — concrete acceptance criteria, technical constraints, prerequisites, success signals. If the feature touches existing/undocumented code, first map the affected files, data flows, and hidden dependencies (read `affectedAreas`).
2. **Design** — the approach: components/files added or changed, data flow, and the key decisions with their trade-offs. For a trivial change, one paragraph ("no architecture changes required") is fine.
3. **Implementation breakdown** — split into concrete, testable steps, each referencing specific files/components and sized to roughly 1–4 hours.

For a large, self-contained sub-investigation (e.g. surveying an unfamiliar subsystem), you **may** dispatch a `general-purpose` subagent via the Agent tool and fold its findings into the plan. Keep the plan authoring itself in this session.

## Step 4 — Write plan.md

Write `docs/features/<id>/plan.md`. Frontmatter is exactly `started:` (today's date). All other metadata stays in `idea.md`.

```markdown
---
started: 2026-06-03
---

# Implementation Plan: <Feature Name>

## Overview
What we're building and why, in a few sentences.

## Requirements
- Acceptance criteria (testable)
- Constraints, prerequisites, success signals

## Design
The approach: components/files touched, data flow, key decisions + trade-offs.
("No architecture changes required" for trivial work.)

## Implementation Steps
- [ ] Step 1: <concrete, testable task with file references>
- [ ] Step 2: <…>
- [ ] Step 3: <…>

## Testing Strategy
- Unit: what to cover
- Integration: scenarios
- Manual verification: the user-facing behavior to check by hand (passing unit tests is never sufficient evidence on its own)

## Risks & Mitigations
- Risk → mitigation

## Progress Log
### 2026-06-03
- Created implementation plan.
- Next: <first implementation step>
```

## Step 5 — Confirm and hand off

The hook moves the feature to In Progress and regenerates `DASHBOARD.md` on the write — do nothing manual.

Review (open the PR / run the reviewer) is its own lifecycle step driven by [../shared/config.md](../shared/config.md) and [../shared/review-channel.md](../shared/review-channel.md); resolve the channel there rather than restating it here.

Summarize: feature name/ID, step count, and the immediate next step:

```
## Plan ready — <name> (<id>)
docs/features/<id>/plan.md · <N> implementation steps · now In Progress

Next: /feature-implement <id>  (ideally from a fresh context)
```
