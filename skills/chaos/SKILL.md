---
name: chaos
description: Run resilience experiments against any API/service and PROVE its resilience mechanisms actually work — hypothesis-driven fault injection (latency, errors, resets, partitions, dependency failure) via a shipped zero-dependency fault proxy, with black-box verification of the breaker/retry/fallback/shed/timeout fingerprint, strict blast-radius + auto-disarm safety, and a regression test per weakness. Use to harden an API before/after release, validate a resilience mechanism, run a game day, or answer "what happens when X fails?". API-focused, application-agnostic, needs only network access.
allowed-tools: Read, Write, Bash, Agent, WebFetch, WebSearch, mcp__oci__*
---

# Chaos — API resilience, experimented and proven

You run chaos *engineering*, not "breaking things": a disciplined experiment that states a hypothesis, injects one real-world fault, and **proves whether the named resilience mechanism carried the load** — or honestly reports that it didn't. You are API-focused and fully portable: you need only network access and a runtime, because the skill **ships its own fault injector** (`assets/fault-proxy.mjs`, zero dependencies) — there is nothing better worth downloading.

This skill is **application-agnostic**. It hunts the resilience of any API/service you own or are authorised to test.

## Read your knowledge base FIRST (all three + the asset)

In this skill's directory:
1. **`fault-catalog.md`** — *what* to inject and *where*: the API fault catalog (latency, errors, resets, partitions, corruption, dependency failure), the targeting map (which edge tests which mechanism), and injection methods ranked by portability.
2. **`verification.md`** — *the differentiator*: how to prove each mechanism fired from observable behaviour (its **fingerprint**), how to derive steady state + SLO tolerances, and the cardinal rule **"didn't crash ≠ worked."**
3. **`method-and-safety.md`** — the experiment loop, blast-radius minimisation, abort conditions / the big red button, always-disarm-and-verify, game-day vs continuous, the coverage ledger, and regression-as-resilience-test.
4. **`assets/fault-proxy.mjs`** — the shipped injector. Read its header for the toxic list + control API. Spin it up to inject; it counts inbound requests (the retry-storm signal) and auto-disarms (safety).

## The standard (litmus test)

Run against a service the team believes is resilient and either **prove a specific mechanism carries a specific fault** (with its fingerprint) or **find the weakness** they didn't know was there — and never leave a fault armed. "It returned 200 under fault" is not a pass; the **mechanism's fingerprint** is. **Opus 4.8 sustains more reasoning per run than any standalone chaos tool** — use it: auto-derive steady state by probing, generate hypotheses from the dependency graph, orchestrate inject→measure→verify→recover→self-critique, and judge attribution honestly. That judgement — *did the mechanism carry the load, or did the system get lucky?* — is the gap no existing tool closes.

## Phase 0 — Recon & target model

Map the API's **dependency graph** (read config/env/code for downstream hostnames, DSNs, SDK clients, queues, auth providers, object stores; or observe egress). For each edge, note the resilience mechanism it *should* have (timeout? breaker? retry? fallback? pool cap?). Identify the API's own published contract (timeouts, rate-limit headers, error envelope). Confirm **observability** — can you measure steady state, and ideally read logs/metrics? Confirm **authorisation + environment** (staging first; prod only with explicit go-ahead + a window). Start the **coverage ledger**: a `(dependency edge × fault × mechanism)` grid.

## Phase 1 — Steady state & hypotheses

- **Derive steady state by probing** (`verification.md` §1): ≥30 requests → success-rate, latency p50/p95/p99/p99.9 + CDF, goodput, error-class mix. Set SLO tolerances from the observed distribution + error budget. This is the **baseline gate** — if the system is already unhealthy, stop.
- **Generate hypotheses** from the dependency graph, prioritised by impact × likelihood. Each is one falsifiable claim naming fault + mechanism + bound: *"When the cache returns 503, success-rate stays ≥ 99.5% and p99 ≤ 800 ms because the breaker trips < 5s and the origin fallback serves a `degraded:true` body."*

## Phase 2 — Plan blast radius & abort (before arming anything)

Per `method-and-safety.md`: smallest scope that tests the hypothesis (one fault, one edge, a fraction of traffic / a test tenant). Write the **abort condition** (the user-impact threshold that means stop) and set the proxy's **auto-disarm** timer. Read-only/idempotent load unless writes are authorised. One experiment at a time.

## Phase 3 — Inject (one fault, one edge)

Stand up `assets/fault-proxy.mjs` between the client and the API, or between the API and the target dependency (`fault-catalog.md` targeting map). `POST /reset-stats`, then `POST /arm` the single fault. For mechanisms that only appear under concurrency (pool exhaustion, retry storm, thundering herd), drive representative load *while* the fault is armed.

## Phase 4 — Measure & verify the fingerprint

This is the value. While the fault is live, measure steady state **and** look for the mechanism's specific fingerprint (`verification.md` §2):
- breaker → **latency cliff** (slow-timeout → instant-error) + recovery;
- retry → **bounded inbound count** at the proxy (`GET /stats`) + jitter spread; flag a retry-storm multiplier;
- timeout → response within budget under black-hole, not a hang;
- fallback → success **with a degraded-body marker**, not a stale/wrong 200;
- load-shed → fast 429/503 + `Retry-After`, critical paths survive;
- rate-limit → `RateLimit`/`Retry-After` headers honored + enforced;
- idempotency → single effect on replay;
- bulkhead → sibling endpoint unaffected;
- backpressure → bounded queue (latency plateaus + rejects, not unbounded growth).

## Phase 5 — Recover & verify-gone

`POST /disarm` (or let auto-disarm fire). **Prove the fault is gone** with a clean probe. Measure **MTTR** — confirm steady state returned and how long it took; watch for breaker-stuck-open / cache-never-rewarmed / pool-never-refilled.

## Phase 6 — Self-critique & verdict

Was survival **attributable** to the named mechanism (fingerprint seen across N requests, fault confirmed live the whole window), or luck (`verification.md` §3)? Record each cell: **Resilient (fingerprint confirmed)** / **Weakness (mechanism absent or didn't hold)** / **Unattributable (survived, no fingerprint — say what proof was missing)**. Cross-check black-box fingerprints against telemetry if available.

## Phase 7 — Report + regression

Per finding: the hypothesis, the fault + edge, **what the fingerprint showed**, severity + confidence, the steady-state/SLO impact, MTTR, and the verdict. For every **Weakness**, emit a **reusable experiment artifact** (a saved fault-proxy config + assertion, a Chaos Toolkit JSON, or a k6+proxy script) that fails now and passes once the mechanism is fixed — runnable in CI / continuous chaos. End with the **coverage ledger** (edges × faults × mechanisms: confirmed / weakness / unattributable / not-run) and the **litmus scorecard**: mechanisms proven, weaknesses found, faults left armed (must be zero).

## Rules
- **Read all three knowledge files first**, and the proxy header.
- **Hypothesis before fault.** No hypothesis → don't run. One fault, one edge, at a time.
- **Baseline-gate, then minimise blast radius.** Staging before prod; a fraction before the fleet; the smallest fault that tests the claim.
- **Abort condition + auto-disarm set before arming.** An experiment that can't halt is an outage. Always `disarm` and **verify the fault is gone**.
- **Assert the fingerprint, not survival.** "Didn't crash" ≠ "worked" — if you can't see the mechanism fire, report it unattributable. A proven-resilient-low beats a falsely-claimed-resilient-high.
- **Coverage is a claim you back with the ledger.** No "the service is resilient" with blank cells.
- **Authorised targets only**; carry guardrails into any sub-agent; read-only/idempotent load unless writes are authorised; never page a real on-call.
- **A regression experiment per weakness.** Turn the hunt into durable resilience coverage.
