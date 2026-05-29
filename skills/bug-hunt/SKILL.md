---
name: bug-hunt
description: Adversarial, expert-level bug hunt for ANY application (web app, API, service, CLI, agent). Goes past a checklist — recon + threat-model, derive the app's invariants and manufacture oracles, fan out per domain, attack each oracle, prove impact (Confirmed vs Suspected), self-critique for false-positives and gaps, and emit a regression test per bug. Use before/after a release, when asked to "find bugs / find broken things / make it rock solid / audit this", or to harden an app you didn't write.
allowed-tools: Read, Grep, Glob, Bash, Agent, WebFetch, WebSearch, mcp__chrome-devtools__*, mcp__oci__*, mcp__devops__*
---

# Bug Hunt — adversarial, oracle-driven

You hunt bugs the way a world-class red-teamer, SRE, and senior reviewer combined would — finding the failures that static review and unit tests miss, including classes the author never considered. You are not reviewing a diff; you are interrogating a whole system for how it breaks, and you hold yourself to the bar that the leading 2026 bug-finding systems actually meet.

This skill is **application-agnostic**. It learned from real production incidents but hunts *any* app. Recon first, apply only what fits.

## Read your knowledge base FIRST (all three)

In this skill's directory:
1. **`bug-taxonomy.md`** — ~180 known bug classes across 14 domains, each with a detection probe (OWASP, Google SRE, AWS, Nygard, Jepsen, PortSwigger, react.dev/web.dev). *What* to hunt.
2. **`detection-toolkit.md`** — *how* to run each probe (curl, race bursts, browser-driven, log triage, static/dataflow, fault injection, soak, triage).
3. **`oracle-methods.md`** — *how to find what nobody anticipated*: manufacture an oracle (invariant / metamorphic relation / differential pair / state machine / spec-diff / variant-from-history) then attack it, plus the rigor machinery (proof-of-exploit gate, coverage ledger, parallel fan-out, dataflow precision, self-critique, severity+confidence, regression tests). Read this one carefully — it is the difference between a checklist and an expert.

## The standard (the litmus test)

Run against an app the team already checked and **find NEW, real bugs they missed**. A surface sweep is not a bug hunt. If you only re-find the known issues, you ran it too shallow. The bar: every domain probed (ledger proves it), every derived invariant attacked, every Confirmed finding carries a runnable proof and a regression test. **Opus 4.8 can sustain far more reasoning per run than the tools that set today's bar — use it: derive more oracles, fan out wider, self-critique harder.**

## Phase 0 — Recon + threat model

Map before you hunt (taxonomy §A). Establish: **stack, full surface** (routes via registry/OpenAPI/router files; pages; jobs/crons; webhooks; external deps), **auth model**, **data model & tenancy** (isolation boundary?), **deploy topology** (replicas/LB/regions/cloud), **trust boundaries** (what data is attacker-influenced). Draw the data-flow; run **STRIDE per trust boundary** to surface the abuse cases that matter for *this* app. Output a short target model and select the applicable taxonomy domains.

**Then start the coverage ledger** (oracle-methods R2): a `(surface × technique/domain)` grid in a scratch file. You will not be allowed to claim "done" with blank cells.

**Scope & authorisation:** only hunt what you own or are authorised to test. Adversarial probes (injection/race/SSRF/auth-bypass) are fine against your own app/staging. On production default to read-only/observational; run active/mutating probes only with explicit go-ahead, and never one that could corrupt prod data or page an on-call. Carry the user's guardrails verbatim into every sub-agent.

## Phase 1 — Manufacture oracles (the heart)

Per `oracle-methods.md` Part 1, derive — and write down — the things that must be true:
- **Invariants** (O1): mine from code + docs/types + ~30 dynamic runs. 10–20 "X must ALWAYS hold" statements.
- **Metamorphic relations** (O2): 3–5 per non-deterministic endpoint (search/rank/aggregate/LLM).
- **Differential pairs** (O3): replica A/B, old/new build, v1/v2, cached/uncached, UI/API, profile/profile, doc/behaviour.
- **State-machine sequences** (O4): the lifecycle operations and their illegal edges.
- **Variant seeds** (O6): mine the project's own incident history (`git log --grep=fix`, CHANGELOG, memory/post-mortems, closed bugs) → each past bug is a template to hunt elsewhere. **This is the highest-yield, most-skipped step.**

## Phase 2 — Cheap broad sweep

Highest yield per minute, so early signal shapes the deep dive: console+network sweep of every page; typecheck + lint + dependency/CVE audit; static footgun grep (empty catches, unsafe render, no-timeout clients, devDep imports, secrets, broad excepts); health + "deployed ≠ working" content probe; security/quality scanner (triaged hard). Mark the ledger as you go.

## Phase 3 — Static + dataflow

Walk the code for the applicable classes you can see without running anything (missing tenant predicates, swallowed errors, missing timeouts, CAS-less RMW, per-replica state, unsafe rendering, excessive agency). For any injection/SSRF/traversal candidate, **trace source→sink** (oracle-methods R4) before it counts — untraced = Suspected at best.

## Phase 4 — Runtime / behavioural

Drive the live app (browser for SPAs per toolkit §3; curl for APIs §1). Exercise every surface; apply the frontend/streaming/API-contract classes against real behaviour (stream leaks, memory growth, out-of-order races, empty-vs-error, pagination edges, stale cache, double-submit).

## Phase 5 — Attack the oracles, in parallel (where the new bugs are)

This is the phase a normal check skips. For a non-trivial target, **fan out one sub-agent per domain** (oracle-methods R3) — authz/isolation, injection, concurrency/idempotency, resilience/chaos, frontend/streaming, LLM-agent, distributed/networking, observability — each handed the target model + invariant list + ledger + guardrails. Each sub-agent:
- attacks its assigned invariants and metamorphic/differential relations,
- runs its taxonomy probes (the two-tenant parity test, IDOR/BFLA/verb-tampering, injection, JWT/session, race + idempotency replay via single-packet/parallel-burst, fault injection asserting breakers trip *and recover*, direct-from-container egress, SSE leak/backpressure, prompt-injection via untrusted-data paths, tool-loop inspection),
- explores state-machine sequences,
- returns findings with evidence.
Merge, dedupe, cross-check.

## Phase 6 — Prove impact (Confirmed vs Suspected)

Per oracle-methods R1: every candidate gets one honest attempt at a runnable proof. Split findings into **Confirmed** (impact demonstrated — quote the proof) and **Suspected** (looks wrong, impact unproven — say what's missing). On prod, where proving impact would be destructive, mark Suspected and describe the safe proof for staging. Never dress a Suspected up as Confirmed.

## Phase 7 — Self-critique (kill FPs, name gaps)

Per oracle-methods R5, with fresh context where possible: re-examine every finding (reproducible? dataflow holds? actually expected behaviour?) and demote/drop what doesn't survive. Then **mutation-test the hunt** — "if I flipped this comparison / removed this guard, would any probe I ran have caught it?" — and probe the blind spots that exposes. Reconcile against the ledger; every blank cell is probed or listed as a gap with a reason.

## Phase 8 — Report + regression

Per toolkit §8 + oracle-methods R6/R7. Each finding: **severity + confidence**, **evidence anchor** (quoted request/response, console line, log entry, trace, heap delta), **reproduction**, **blast radius**, **fix sketch** (file:line if traceable), and — for every Confirmed bug — a **regression test or repro command that fails now and passes once fixed**. Group **Confirmed (Critical→Low)**, then **Suspected**, then **Expected (not bugs)** proving you triaged. If the user asked you to fix and is away, fix shallow high-confidence ones and flag the rest; else report and let them choose.

End with the **litmus scorecard**: *N new Confirmed bugs not previously known* + what you re-confirmed vs found new + the coverage ledger (what was probed, what was skipped and why).

## Relationship to /pentest

`/bug-hunt` hunts **defects of all classes** (correctness, resilience, concurrency, frontend, observability, security) to **fix** — oracle-driven, output is bugs + regression tests, no authorization gate beyond "test what you own". `/pentest` is **adversary emulation against an authorized target toward a crown-jewel objective** — RoE-gated, with deeper exploitation, vulnerability *chaining* (low+low→critical), post-exploitation, CVSS scoring, and a professional report. They share the Confirmed-vs-Suspected discipline and the regression/retest-per-finding habit. A security finding from a bug-hunt is an ideal **seed** for a pentest exploitation/chaining pass — hand it to `/pentest` to prove what an attacker actually does with it.

## Rules
- **Read all three knowledge files first** — taxonomy, toolkit, oracle-methods.
- **Manufacture an oracle, then attack it.** Don't just walk a checklist — derive what must be true for *this* app and try to break it. Mine the repo's own incident history for variant seeds.
- **Coverage is a claim you back with the ledger.** No "done" with blank cells. This is the rule that exists because "verified" was once claimed while obvious bugs remained.
- **Confirmed needs a proof; trace dataflow before crying injection.** A confirmed low beats a suspected critical. Crying wolf destroys the skill.
- **Fan out.** Spend the reasoning the older tools couldn't — parallel sub-agents per domain.
- **Authorised targets only**; carry guardrails into every sub-agent; default read-only on prod.
- **A regression test per Confirmed bug.** Turn the hunt into durable coverage.
- **Unit-tests-passing is not evidence.** Validate behaviour against the running system.
