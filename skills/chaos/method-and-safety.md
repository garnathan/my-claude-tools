# Method & safety — the experiment loop, blast radius, and the big red button

> The discipline that separates chaos *engineering* from "breaking things in prod". An experiment without a hypothesis is noise; an experiment without an abort condition is an outage generator; an experiment whose fault you forget to revert is a slow incident. This file is the safety spine of the skill — non-negotiable.

---

## The experiment loop (every experiment follows this, in order)

Modelled on the Chaos Toolkit contract (`steady-state-hypothesis → method → rollbacks`) and the Principles of Chaos Engineering.

1. **Hypothesis.** A single falsifiable claim naming the fault, the mechanism, and the bound: *"When dependency X returns 503, success-rate stays ≥ 99.5% and p99 ≤ 800 ms because the circuit breaker trips within 5s and the cached fallback serves."* No hypothesis → don't run.
2. **Baseline gate.** Measure steady state now (`verification.md` §1). If it already fails tolerance, **bail out before injecting** — you can't attribute anything from an unhealthy start.
3. **Blast radius + abort conditions** (see below) — decided and written *before* the fault is armed.
4. **Inject one fault, one edge.** Arm the smallest fault that tests the hypothesis (`fault-catalog.md`). One variable at a time — concurrent faults make attribution impossible.
5. **Measure under fault** — steady state + the mechanism's **fingerprint** (`verification.md` §2), continuously, watching the abort conditions.
6. **Recover & verify-gone.** Disarm the fault and **assert it's actually gone** (the proxy is passing through / the toxic is removed). Then measure **MTTR** — confirm steady state returned and how long it took (`verification.md` §4).
7. **Self-critique & verdict.** Was survival *attributable* to the named mechanism (fingerprint seen), or luck? Record **Resilient (fingerprint confirmed)** / **Weakness (mechanism didn't fire or didn't hold)** / **Unattributable (survived, no fingerprint)**. Never call unattributable "resilient."

---

## Safety machinery (what makes this responsible, not reckless)

**Blast-radius minimisation — start small, widen only on green.**
- Environment ladder: **local/staging first → prod only when the mechanism is already proven and the blast radius is provably small.** Never a fault's first run in production.
- Scope ladder: one fault → one dependency edge → a *fraction* of requests/connections (toxicity < 1.0) or a single test tenant/key → only then broader.
- One experiment at a time. **Never start a second while the first's blast radius is unresolved.**

**Abort conditions / the big red button — defined BEFORE arming.**
- Write the halt threshold first: real user-facing impact (success-rate below floor, p99 above ceiling, error budget burning too fast). When crossed, **disarm immediately** — don't deliberate.
- Prefer an *automatic* halt: a watchdog probe that disarms the fault the moment the abort threshold trips (mirrors AWS FIS stop-conditions). The shipped proxy supports **auto-disarm after N seconds** — always set it, so a forgotten or crashed experiment can't run forever.
- Keep the manual kill obvious and instant (one command/keystroke to flip the proxy to pass-through).

**Always revert — and verify the revert.**
- Disarm is part of the experiment, not an afterthought. After disarming, **prove the fault is gone** (a clean probe through the now-passthrough path). An armed toxic left behind is an incident waiting to be blamed on something else.

**Observability precondition.**
- You can't verify what you can't see. Before arming, confirm you can measure steady state (probes working, and ideally logs/metrics reachable). Chaos without observability teaches nothing.

**Authorisation & windows.**
- Only run against systems you own or are explicitly authorised to test. Adversarial faults against prod need explicit go-ahead and ideally a declared game-day/maintenance window. Carry these limits verbatim into any sub-agent you spawn. Read-only/idempotent load unless writes are authorised.

---

## Game day vs continuous

- **Game day** (facilitated, scheduled, scoped): the right mode for a *novel* or large-scope experiment (region loss, DR, a mechanism's first validation) and for testing the **human/operational** response — does the alert page someone, does the runbook work. Prove it here first.
- **Continuous/automated** (unattended regression): once a hypothesis is proven and the blast radius is provably small, automate it so the resilience mechanism stays proven across deploys (Chaos Monkey-style). Sequence is always **game-day first → automate second.**

---

## Coverage ledger (so you can't claim "resilient" with gaps)

Maintain a `(dependency edge × fault × mechanism)` grid in a scratch file, each cell marked `confirmed-resilient` / `weakness #N` / `unattributable` / `not-run (reason)`. You may not conclude "the service is resilient" with blank cells — you must show the grid and name what wasn't exercised. This is the antidote to "we did some chaos and it was fine." Mirror it to the user in the report.

---

## Regression — turn every weakness into a permanent resilience test

A weakness you found once will come back. For every **Weakness**, emit a reusable experiment artifact (a Chaos Toolkit JSON, a k6+proxy script, or a saved fault-proxy config + assertion) that fails now and passes once the mechanism is fixed — and that can run in CI / continuous chaos thereafter. This compounds: the hunt becomes durable resilience coverage, not a one-off.

---

## Anti-patterns (do none of these)

- **No hypothesis** — randomly breaking things produces noise, not confidence.
- **No abort condition / no auto-disarm** — an experiment that can't halt is an outage generator.
- **Blast radius too large** — straight to fleet-wide / 100% of traffic / prod-first.
- **Leaving the fault armed** — not reverting, or not *verifying* the revert.
- **Chaos without observability** — can't measure steady state = can't learn.
- **Prod before staging** — running an unproven experiment in production first.
- **"It didn't crash" = "it worked"** — the cardinal trap. Assert the mechanism's fingerprint (`verification.md`), or report unattributable.
- **Parallel experiments with overlapping blast radius** — attribution becomes impossible and impacts compound.
