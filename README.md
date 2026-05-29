# claude-skills

Personal, reusable [Claude Code](https://claude.com/claude-code) skills — application-agnostic, version-controlled, and loadable from this repo.

## Skills

| Skill | What it does |
|---|---|
| **`/bug-hunt`** | Adversarial, oracle-driven bug hunt for any app (web/API/service/CLI/agent). Recon+threat-model → **manufacture oracles** (invariants, metamorphic relations, differential pairs, state machines, variant-from-history) → parallel fan-out per domain → **prove impact** (Confirmed vs Suspected) → self-critique → regression test per bug. ~180-class taxonomy + detection toolkit + oracle-methods. Litmus: find *new* real bugs in an already-checked app. |
| **`/deai`** | Rewrite AI-generated text so it reads as genuinely human-written in a professional register — strip LLM signatures (flagged vocab, scaffolding, em-dash overuse, uniform cadence, no-stance hedging) while preserving meaning and never fabricating. Litmus: output reads "probably not AI". |
| **`/chaos`** | API-focused chaos engineering. Hypothesis → inject one fault (via a **shipped zero-dependency fault proxy** — no Toxiproxy/Gremlin needed) → **verify the resilience mechanism's fingerprint** (breaker = latency cliff, retry = bounded inbound count + jitter, fallback = degraded body, shed = fast 429+Retry-After) → recover → self-critique. Strict blast-radius + auto-disarm safety; regression experiment per weakness. Litmus: prove a mechanism carries a fault, or find the weakness — never leave a fault armed. |

## Layout

```
claude-skills/
├── .claude-plugin/
│   └── marketplace.json        # lets this repo be added via `/plugin marketplace add`
├── skills/
│   ├── bug-hunt/
│   │   ├── SKILL.md            # orchestration: recon → oracles → fan-out → prove → self-critique → report
│   │   ├── bug-taxonomy.md     # ~180 known bug classes → detection probe
│   │   ├── detection-toolkit.md# how to run each probe
│   │   └── oracle-methods.md   # manufacture-an-oracle techniques + hunt rigor (the expert brain)
│   ├── deai/
│   │   ├── SKILL.md            # de-AI text → human, professional register
│   │   └── ai-tells.md         # AI-writing tells + fixes (two-tier model)
│   └── chaos/
│       ├── SKILL.md            # orchestration: recon → hypothesis → inject → verify fingerprint → recover
│       ├── fault-catalog.md    # API faults + targeting map (which edge tests which mechanism)
│       ├── verification.md     # per-mechanism fingerprints + steady-state/SLO + "didn't crash ≠ worked"
│       ├── method-and-safety.md# experiment loop, blast radius, abort/auto-disarm, ledger, regression
│       └── assets/
│           └── fault-proxy.mjs # shipped zero-dependency fault-injecting reverse proxy
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
