# claude-skills

Personal, reusable [Claude Code](https://claude.com/claude-code) skills — application-agnostic, version-controlled, and loadable from this repo.

## Skills

| Skill | What it does |
|---|---|
| **`/bug-hunt`** | Adversarial, oracle-driven bug hunt for any app (web/API/service/CLI/agent). Recon+threat-model → **manufacture oracles** (invariants, metamorphic relations, differential pairs, state machines, variant-from-history) → parallel fan-out per domain → **prove impact** (Confirmed vs Suspected) → self-critique → regression test per bug. ~180-class taxonomy + detection toolkit + oracle-methods. Litmus: find *new* real bugs in an already-checked app. |
| **`/deai`** | Rewrite AI-generated text so it reads as genuinely human-written in a professional register — strip LLM signatures (flagged vocab, scaffolding, em-dash overuse, uniform cadence, no-stance hedging) while preserving meaning and never fabricating. Litmus: output reads "probably not AI". |
| **`/chaos`** | API-focused chaos engineering. Hypothesis → inject one fault (via a **shipped zero-dependency fault proxy** — no Toxiproxy/Gremlin needed) → **verify the resilience mechanism's fingerprint** (breaker = latency cliff, retry = bounded inbound count + jitter, fallback = degraded body, shed = fast 429+Retry-After) → recover → self-critique. Strict blast-radius + auto-disarm safety; regression experiment per weakness. Litmus: prove a mechanism carries a fault, or find the weakness — never leave a fault armed. |
| **`/pentest`** | Authorized penetration test against any system you own/are permitted to test. **Rules-of-engagement gate** (authorization is non-skippable) → recon → enumeration → threat model + **attack tree** → exploitation (Confirmed vs Suspected, **non-destructive minimum proof**) → **vulnerability chaining** (low+low→critical toward a crown-jewel objective) → post-exploitation/blast-radius → CVSS-scored **professional report** + retest check per finding. Aligned to PTES, NIST SP 800-115, OWASP WSTG/ASVS/API Top 10, MITRE ATT&CK. Litmus: a *demonstrated chain* to an objective, not a CVE list. |
| **`/llm-eval`** | Build/run a rigorous eval of any LLM app or agent — **and make the eval itself trustworthy.** Deterministic-first metrics → **validate every judge against human labels (Cohen's κ)** before trusting its number → claim-decomposition **faithfulness/hallucination** detection → **judge-bias controls** (position-swap/verbosity/self-preference) → **statistical honesty** (paired-difference + confidence intervals + fixed temperature; never a win on noise). Ships a **zero-dependency eval harness** (deterministic + judge scorers, position-swap, κ meta-eval, CI-bound gate) — no promptfoo/DeepEval/RAGAS needed. Litmus: find a flaw in a trusted benchmark (unvalidated judge, biased rubric, an A/B "win" inside the noise) or catch a regression it misses. |
| **`/ui-verify`** | Prove a deployed web UI actually **works**, not just loads — *"deployed ≠ working"*. Asserts a ladder (L0 loads → L1 renders real content → L2 wired to backend → L3 functional/streaming): **semantic content oracles**, **console + network fail-gates** (incl. wrong-endpoint detection), **SSE** streaming verification, visual baseline diff, axe a11y — with deterministic waits + **retry-quorum** so a pass means a pass, and a **structured evidence report**. Ships a **zero-dependency CDP driver** (Node 22 + Chrome, no npm/Playwright); also uses the chrome-devtools MCP or Playwright when present. Litmus: catch a 200-but-broken page an HTTP/screenshot check misses. |
| **`/debug`** | Find the **root cause** of a failure by disciplined hypothesis-and-falsification with shipped instrumentation — never fix before you understand. Distributed-systems-aware (containers/LB/cross-VCN/IAM eventual-consistency/shared resources): reproduce → observe → hypothesize → **falsify by toggling** → bisect → confirm → prove the fix → regression-guard, with a **Confirmed-vs-Suspected gate** (correlation ≠ cause) + a localization **decision tree**. Ships a **zero-dependency boundary tracer** (DNS/TCP/TLS/HTTP/auth/content probes + **working-vs-failing differential**). Litmus: localize a failure to its first divergent boundary + confirm by toggling, without shotgun-changing anything. |

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
│   ├── chaos/
│   │   ├── SKILL.md            # orchestration: recon → hypothesis → inject → verify fingerprint → recover
│   │   ├── fault-catalog.md    # API faults + targeting map (which edge tests which mechanism)
│   │   ├── verification.md     # per-mechanism fingerprints + steady-state/SLO + "didn't crash ≠ worked"
│   │   ├── method-and-safety.md# experiment loop, blast radius, abort/auto-disarm, ledger, regression
│   │   └── assets/
│   │       └── fault-proxy.mjs # shipped zero-dependency fault-injecting reverse proxy
│   ├── pentest/
│   │   ├── SKILL.md                    # orchestration: RoE gate → recon → threat model → exploit → chain → report
│   │   ├── methodology.md              # PTES/NIST lifecycle, WSTG/API Top 10/cloud/auth test flow, attack trees, ATT&CK
│   │   ├── exploitation.md             # proof-of-exploit standard (Confirmed/Suspected) + chaining catalog + technique
│   │   └── engagement-and-reporting.md # RoE/authorization gate, CVSS v4.0, report anatomy, disclosure, retest loop
│   ├── llm-eval/
│   │   ├── SKILL.md                  # orchestration: recon → eval set → metrics → validate judge → run → faithfulness → report
│   │   ├── methodology.md            # lifecycle, eval-set construction, metric taxonomy, statistical rigor, agentic eval, pitfalls
│   │   ├── faithfulness-and-judges.md# claim-decomposition faithfulness, RAGAS quartet, judge done-well + biases + meta-eval (κ)
│   │   └── assets/
│   │       └── eval-harness.mjs      # shipped zero-dependency eval runner (deterministic+judge scorers, swap, κ, CI gate)
│   ├── ui-verify/
│   │   ├── SKILL.md                  # orchestration: recon → drive → assert L0→L3 ladder → anti-flakiness → evidence
│   │   ├── verification-ladder.md    # the ladder, per-level assertions, console/network fail-gates, SSE, anti-flakiness, CDP
│   │   └── assets/
│   │       └── verify.mjs            # shipped zero-dependency CDP verification harness (content oracles, fail-gates, report)
│   └── debug/
│       ├── SKILL.md                  # orchestration: reproduce → observe → hypothesize → falsify → bisect → confirm → guard
│       ├── method-and-decision-tree.md # Agans×scientific-method×SRE loop, anti-patterns, distributed localization tree, Confirmed/Suspected
│       └── assets/
│           └── boundary-tracer.mjs   # shipped zero-dependency DNS/TCP/TLS/HTTP/auth/content probe + working-vs-failing differential
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
