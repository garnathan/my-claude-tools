---
name: feature-search
description: Query the backlog by structured filters — state, assignee, priority, type, category, epic membership, or dependency — and present the matches as a table (or JSON). Wraps a shipped script that reads docs/features/*/idea.md and applies the filters; tombstones (replaced/abandoned) are excluded unless --archive is passed. Use when the user wants to find features matching criteria: "what's paused", "what is court working on", "show all P0s", "what's in the auth-overhaul epic", "what depends on user-roles". Litmus: the user gets exactly the features matching their filters, and nothing that doesn't.
allowed-tools: Read, Bash
---

# feature-search — query the backlog

Filter features by their `idea.md` frontmatter and present the matches. The shipped script lives at `scripts/search.py` *in this skill's directory*.

## Step 1 — Run the search

Pass `$ARGUMENTS` straight through as flags:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/feature-search/scripts/search.py" . $ARGUMENTS
```

Supported flags (combine freely — they AND together):

| Flag | Matches |
|---|---|
| `--state <active\|paused\|replaced\|abandoned>` | features in that state |
| `--assignee <name>` | features owned by that name |
| `--priority <P0\|P1\|P2>` | features at that priority |
| `--type <Feature\|Enhancement\|Bug Fix\|Tech Debt\|Epic>` | features of that type |
| `--category <name>` | features in that category |
| `--epic <id>` | children of that epic |
| `--depends-on <id>` | features that depend on the given ID |
| `--archive` | include tombstones (replaced + abandoned), which are excluded by default |
| `--format text\|json` | output format (default `text`) |

With no filters, it lists all active features (archive excluded).

## Step 2 — Format the response

- **text** (default): the script prints a markdown table. Render it as-is, with a one-line lead above it: **"N matching features:"**
- **json** (`--format json`): echo the JSON.

## Step 3 — Suggest follow-ups

Based on what came back:

- Paused results → `/feature-state <id> active` to resume
- Active backlog → `/feature-plan <id>`
- In progress → `/feature-implement <id>`

If zero results:
- With a specific filter → suggest loosening it, or add `--archive` to include tombstones.
- Looking for a feature that doesn't exist → suggest `/feature-capture` to add it.

## Examples

| User request | Command |
|---|---|
| "what's paused?" | `/feature-search --state paused` |
| "what is court working on?" | `/feature-search --assignee court` |
| "show all P0s" | `/feature-search --priority P0` |
| "what's in the auth-overhaul epic?" | `/feature-search --epic auth-overhaul` |
| "what depends on user-roles?" | `/feature-search --depends-on user-roles` |
| "show abandoned features" | `/feature-search --state abandoned --archive` |
