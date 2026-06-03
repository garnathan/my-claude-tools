# feature-workflow

Directory-based feature lifecycle management for Claude Code. Capture an idea, plan it, implement it, review it, and ship it — all as plain markdown files in your repo, with an auto-generated dashboard and a review step that works on GitHub, Bitbucket, or no remote at all.

> **Provenance.** Adapted from [Court Schuett's feature-workflow plugin](https://github.com/schuettc/claude-code-plugins). The file model + dashboard engine are ported intact (and still pass the original test suite). The GitHub-Actions / Gemini / Codex review path is replaced by a **provider-agnostic review channel** that defaults to a local review subagent — no CI, no API keys. The specialized planning agents, runtime-audit / troubleshoot skills, autopilot/epic-dispatcher, and migration tooling from upstream are intentionally **not** carried over (use `/debug`, `/verify`, `/ui-verify`, `/bug-hunt` for the audit/troubleshoot side).

## The model

Each feature is a directory under `docs/features/<id>/`. **Status is determined by which files exist:**

| Files present | Status |
|---|---|
| `idea.md` | Backlog |
| `idea.md` + `plan.md` | In Progress |
| `idea.md` + `plan.md` + `shipped.md` | Completed |

An orthogonal **state** overlay lives in `idea.md` frontmatter — `active` (default), `paused`, `replaced`, `abandoned` — plus epics (`type: Epic` + `children:`), a dependency graph (`dependsOn`/`relatedTo`), and ownership (`assignee`). A PostToolUse hook regenerates `docs/features/DASHBOARD.md` on every feature-file write and keeps `epic↔children` and `replaces↔replacedBy` in sync; a PreToolUse hook blocks direct edits to the generated dashboard.

## Skills

| Skill | Purpose |
|---|---|
| `/feature-init` | One-time setup: `docs/features/`, `.feature-workflow.yml` (branch + review config), gitignore the dashboard |
| `/feature-capture` | Interview → write `idea.md` |
| `/feature-plan <id>` | Requirements → design → implementation breakdown → `plan.md` |
| `/feature-implement <id>` | Implement the plan, tracking progress and guarding scope |
| `/feature-review-plan <id>` | Open a PR + review the plan (or `--respond` to feedback) |
| `/feature-review-impl <id>` | Push the implementation + review it (or `--respond`) |
| `/feature-ship <id>` | Final quality gates → `shipped.md` → merge |
| `/feature-status` | Render the dashboard on demand |
| `/feature-state <id> <state>` | Manage the state overlay (pause/replace/abandon/resume) |
| `/feature-search <filters>` | Query features by state/assignee/epic/dependency |

Plus three advisory skills that fire on the situation: **guarding-scope**, **tracking-progress**, **checking-backlog**.

## The review channel — provider-agnostic

Configured in `.feature-workflow.yml` along the two axes that used to be hard-coded to GitHub CI:

```yaml
branch:
  prefix: "feature/"
  target: "dev"
review:
  mode: "internal"     # internal | external | skip   (WHO reviews — default: a local subagent)
  provider: "github"   # github | bitbucket | none    (WHERE the PR + comments live)
```

- **mode `internal`** (default) — a local Claude subagent runs the same review rubric (`templates/review-prompt-{plan,impl}.md`) and posts the verdict. No CI, no API keys, works anywhere.
- **mode `external`** — an external CI bot reviews (GitHub Actions / Bitbucket Pipelines / OCI DevOps). A documented extension point — see [`skills/shared/review-channel.md`](skills/shared/review-channel.md); until you wire it, it falls back to a local review rather than silently skipping.
- **provider `none`** — no PR; the verdict is recorded only in the feature's `reviews/` side-channel, and `/feature-ship` merges locally.

A feature can override the mode in its `idea.md` (`review: internal | external | skip`). Resolution is in [`skills/shared/lib/review_resolve.py`](skills/shared/lib/review_resolve.py); the provider command mapping (GitHub `gh` / Bitbucket MCP+REST) is in [`skills/shared/review-channel.md`](skills/shared/review-channel.md).

## Layout

```
feature-workflow/
├── .claude-plugin/plugin.json     # plugin manifest + PreToolUse/PostToolUse hook wiring
├── hooks/                         # pre_tool_use (block dashboard edits) + post_tool_use (regen + sync)
├── templates/                     # review-prompt-{plan,impl}.md (the review rubric)
└── skills/
    ├── feature-*/                 # the lifecycle + diagnostic skills
    ├── guarding-scope/ tracking-progress/ checking-backlog/   # advisory
    └── shared/
        ├── config.md              # .feature-workflow.yml contract
        ├── review-channel.md      # the provider-agnostic reviewer seam
        ├── respond.md             # shared review-response flow
        ├── lib/                   # the dashboard engine (frontmatter/models/deps/run_dashboard/sync_*) + review_resolve
        └── tests/                 # 146 tests over the engine + resolver
```

## Requirements

- **Python 3** for the hooks + engine (stdlib only — no pip installs).
- **git**, and the CLI/MCP for your chosen provider (`gh` for GitHub; the Bitbucket MCP or REST for Bitbucket). `provider: none` needs neither.

## Tests

```bash
cd feature-workflow && python3 -m pytest -q     # 146 passing
```
