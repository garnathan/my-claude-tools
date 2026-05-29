# claude-skills

Personal, reusable [Claude Code](https://claude.com/claude-code) skills — application-agnostic, version-controlled, and loadable from this repo.

## Skills

| Skill | What it does |
|---|---|
| **`/bug-hunt`** | Adversarial, expert-level bug hunt for any app (web/API/service/CLI/agent). Recon → static → runtime → adversarial probes → triage, driven by a researched taxonomy of ~180 bug classes (OWASP, Google SRE, AWS, Nygard, Jepsen, PortSwigger, react.dev/web.dev). Litmus test: run it against an already-checked app and find *new* real bugs. |

## Layout

```
claude-skills/
├── .claude-plugin/
│   └── marketplace.json        # lets this repo be added via `/plugin marketplace add`
├── skills/
│   └── bug-hunt/
│       ├── SKILL.md            # the orchestration / workflow
│       ├── bug-taxonomy.md     # the field guide: bug class → detection probe
│       └── detection-toolkit.md# how to run each probe
└── README.md
```

## How Claude loads these

Two supported paths:

**1. Symlink into `~/.claude/skills/` (immediate, no UI).** Each skill dir is symlinked so Claude Code auto-loads it on the next session:

```bash
ln -s "$PWD/skills/bug-hunt" ~/.claude/skills/bug-hunt
```

The source of truth stays in this git repo; the symlink just points Claude at it. Edit here, commit here.

**2. As a plugin marketplace (shareable).** Add the repo as a marketplace, then install:

```
/plugin marketplace add garnathan/claude-skills
/plugin install bug-hunt@claude-skills
```

## Adding a new skill

1. `mkdir -p skills/<name>` and write `skills/<name>/SKILL.md` (frontmatter: `name`, `description`, optional `allowed-tools`).
2. Add any companion reference files alongside it; have `SKILL.md` instruct Claude to read them at the start of a run.
3. Symlink it: `ln -s "$PWD/skills/<name>" ~/.claude/skills/<name>`.
4. Add it to `.claude-plugin/marketplace.json`.
5. Commit.

## Conventions

- Skills are **application-agnostic** — they learn from specific projects but work anywhere.
- Heavy knowledge goes in companion `.md` files the skill reads on demand, keeping `SKILL.md` to orchestration.
- Every skill states its **litmus test** — the concrete bar that proves it works.
