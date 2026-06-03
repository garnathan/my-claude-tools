---
name: feature-status
description: Render the project's feature dashboard on demand — a scannable summary of what's in progress, paused, in the backlog (by priority), grouped into epics, and recently completed. Reads the live state from docs/features/ via the shared dashboard engine; supports category/state/assignee filters and per-feature detail. Use when the user asks "what's the status", "what's in progress", "what should I work on next", "show me the backlog", or "what did we ship recently". Litmus: the user sees an accurate, current snapshot of the backlog without you editing any file.
allowed-tools: Read, Bash
---

# feature-status — render the backlog dashboard

Read-only. Generates the dashboard live from `docs/features/` and presents a scannable summary. Never edit `DASHBOARD.md` directly — it is gitignored and auto-generated, and a PreToolUse hook blocks writes to it.

## Step 1 — Generate the dashboard

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/shared/lib/run_dashboard.py" . --stdout
```

This scans every `docs/features/<id>/` and prints the dashboard to stdout. If the script fails or `docs/features/` doesn't exist, stop and say: "No backlog found. Run `/feature-init` to set up, then `/feature-capture` to add the first feature."

## Step 2 — Apply filters

`$ARGUMENTS` may carry filter tokens. Parse them before rendering; multiple tokens stack with AND logic:

- `cat:<category>` — keep only rows whose Category matches (case-insensitive). Header: **"Filtered by category: <value>"**
- `state:<state>` — keep only rows in that state (`active` · `paused` · `replaced` · `abandoned`). Header: **"Filtered by state: <value>"**
- `assignee:<name>` — keep only rows owned by that name (case-insensitive). Header: **"Filtered by assignee: <value>"**
- `--archive` — include the Archive section (replaced + abandoned); omit it otherwise
- A bare feature ID — skip the dashboard and show that feature's detail instead (Step 4)

For filter combinations richer than the dashboard tables support, hand off to `/feature-search` with the equivalent flags.

## Step 3 — Format the summary

The dashboard may contain any of these sections; render each that is present:

- **In Progress** — features with a `plan.md` but no `shipped.md`
- **Paused** — started but temporarily on hold (`state: paused`, with `pausedReason`)
- **Backlog** — waiting to start, sorted by priority
- **Epics** — multi-feature initiatives grouping related work
- **Completed** — shipped features
- **Archive** — replaced or abandoned (only when `--archive` is set)

Present a scannable view:

1. **Summary counts** — in progress, paused, backlog (by priority), completed
2. **In Progress** — name, priority, when started
3. **Ready to Start** — backlog sorted by priority; highlight P0
4. **Recently Completed** — last 3–5 items

Use tables for lists.

## Step 4 — Per-feature detail

If `$ARGUMENTS` is a single feature ID, read its files instead of the whole dashboard:

```
docs/features/<id>/
├── idea.md      # problem statement + frontmatter (state, priority, deps)
├── plan.md      # implementation plan (if in progress)
└── shipped.md   # completion notes (if completed)
```

Summarize the problem, current lifecycle, state, and (if planned) the plan's key steps.

## Example

**User:** "What's the status?"

```
# Project Status

Summary: 1 in progress, 1 paused, 4 backlog, 3 completed

## In Progress
- Dark Mode Toggle (P1) — started 2024-01-18

## Paused
- Offline Mode (P2) — paused 2024-01-12 (blocked: waiting on design)

## Backlog (ready to start)
| Priority | Name                | Effort |
|----------|---------------------|--------|
| P0       | User Authentication | Medium |
| P1       | API Rate Limiting   | Small  |

## Recently Completed
- Export Feature (2024-01-15)
- Search Improvements (2024-01-10)
```

## Follow-ups

- Deeper dive on one item → the `checking-backlog` skill, or `/feature-status <id>`
- Start a backlog item → `/feature-plan <id>`
- Continue an in-progress item → `/feature-implement <id>`
- Plan or implementation ready for review → `/feature-review-plan <id>` or `/feature-review-impl <id>`
- Reviews passed → `/feature-ship <id>`
