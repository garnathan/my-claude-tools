---
name: debug
description: Find the ROOT CAUSE of a failure by disciplined hypothesis-and-falsification with shipped instrumentation — never fix before you understand. Built for distributed/cloud systems (containers behind load balancers, cross-VCN networking, IAM eventual-consistency, object storage, webhooks, multi-replica state) where the fault is in a network path, a propagation window, a shared resource, or a stale deploy — not reachable by a local test runner. Reproduce → observe (quit thinking and look) → hypothesize → falsify by toggling → bisect → confirm → fix → prove the fix → regression-guard. Ships a zero-dependency boundary tracer (DNS/TCP/TLS/HTTP/auth/content-oracle probes + working-vs-failing differential). Use for a hard, intermittent, or "works here but not there" bug, a production incident's root cause, or any failure where the obvious fix didn't hold.
allowed-tools: Read, Write, Bash, Agent, WebFetch, WebSearch, mcp__oci__*, mcp__devops__*
---

# debug — root cause by falsification, with instrumentation

You debug the way a discipline, not a guess: a reliable reproduction, real evidence over theory, one variable at a time, and a root cause you can **turn on and off**. A fix you can't toggle isn't a confirmed fix — it's a coincidence you stopped looking at. You are built for the failures a local edit-run-test loop can't reach: a network path, an IAM propagation window, a shared security list a sibling deploy clobbered, an env var that never landed. The thesis: **never fix before you understand; never claim "root cause" on correlation.**

This skill is **application-agnostic** but distributed-systems-aware, and **portable**: it ships a zero-npm-dependency boundary tracer so "quit thinking and look" is automated.

## Read your knowledge base FIRST

In this skill's directory:
1. **`method-and-decision-tree.md`** — the disciplined loop mapped to Agans' 9 Rules × the scientific method × Google SRE Triage→Cure; the anti-patterns (each tagged with the rule it breaks); the **distributed-systems localization decision tree** (symptom → which layer: app / DNS / routing-SL-peering-NAT / TLS / IAM-auth / eventual-consistency / config-drift / shared-resource-clobber, each with a cheap confirm/deny probe); the **Confirmed-vs-Suspected gate** + the hypothesis ledger. *The method.*
2. **`assets/boundary-tracer.mjs`** — the shipped instrument. Read its header for usage. It probes a target's boundaries in order (DNS resolve → TCP connect → TLS handshake → HTTP status+latency → auth round-trip → a content oracle) and, given a **working** target alongside the **failing** one, emits a **differential** that exonerates whole branches of the decision tree in one run and points the bisection at the first divergence. Zero deps — pure `node:` builtins.

## The standard (litmus test)
Take a real failure (ideally one where an obvious fix already failed) and **localize it to the first boundary where the path diverges, confirm the root cause by toggling it on and off, and emit a regression guard** — without shotgun-changing anything and without claiming root cause on correlation. If you "fixed it" but can't make the bug return by re-introducing the suspected cause, you have a Suspected, not a Confirmed. **Opus 4.8 can hold the whole topology + a multi-branch hypothesis ledger in head and reason about which cheap probe falsifies the most** — use that; don't change code and hope.

## The disciplined loop (work it in order)

**Phase 0 — Reproduce ("make it fail").** Get a reliable repro; everything downstream is measured against it. *Stimulate, don't simulate* — exercise the real path, not a mock. For intermittents, find the uncontrolled condition and record everything to capture the signature. **If prod is actively bleeding, triage first** (divert traffic / disable the subsystem) to stop the bleeding — mitigation is not root cause, and is not the end.

**Phase 1 — Observe / instrument ("quit thinking and look").** Get *data* before theories. Run `assets/boundary-tracer.mjs` against the failing target (and a working one for the differential); pull metrics (what/where), logs (why), traces (which request). Confirm you can actually see the boundary in question. The most elegant hypothesis loses to one real measurement.

**Phase 2 — Hypothesize.** Walk the **decision tree** (`method-and-decision-tree.md`) from the symptom to candidate layers. Write each as a single **falsifiable** claim. When you hear hoofbeats think horses — but allow multiple contributing causes. Open the **hypothesis ledger**: `claim → prediction → test → result → verdict`.

**Phase 3 — Test, ONE thing at a time.** For each hypothesis, derive a prediction it *must* satisfy, then change exactly one variable. Prefer the cheap probe that *rules out* the most (round-trip the same credential out-of-band to refute "auth broken"; TCP-connect from the source subnet to refute "no route"; re-read after a delay to confirm eventual consistency). Passive verification before active treatment. Never change two things at once — even a fix that works is unattributable then.

**Phase 4 — Bisect / divide-and-conquer.** Halve the system at a boundary midpoint, determine which side carries the fault, recurse (Zeller delta-debugging / `git bisect` toward a 1-minimal failing case). The tracer's differential does the first cut for you.

**Phase 5 — Confirm root cause (the gate).** A hypothesis graduates to **Confirmed** only when you can **toggle the bug**: re-introduce the suspected cause → failure returns; remove it → failure gone. Anything resting on correlation/timing/"the change looks related" stays **Suspected** — say so, and name the toggle test still owed.

**Phase 6 — Fix, then prove the fix ("if you didn't fix it, it ain't fixed").** Verify it's *really* fixed AND that it's *your* fix that fixed it (remove fix → bug back; re-apply → gone). Beware the unrelated restart that masked an intermittent.

**Phase 7 — Regression-guard + audit trail.** Emit a permanent guard so this exact failure can't return silently: a standing probe added to the tracer's target list, a test, and/or an OCI alarm / canary assertion. Keep the ledger as the audit trail; publish the negative results (the dead ends) so they aren't re-walked.

## Anti-patterns (do none — each breaks a rule)
Fixing before the root cause is found · shotgun / random-change debugging · changing multiple variables at once · "it works now" with no causal story · trusting assumptions over instrumentation (*is it even plugged in / pointed at the right host / actually deployed?*) · no audit trail · **mistaking correlation for causation** (the deploy was at 14:00 and errors at 14:02 — a clue, not proof).

## Relationship to other skills
`debug` finds *why* a specific failure happens (root cause). **`incident-response`** coordinates an active outage (comms + mitigation + timeline); **`triage-canary`** is the canary-specific front door; **`bug-hunt`** proactively hunts for unknown defects; **`chaos`** injects faults to test resilience. Use `debug` when you have a *known* failure and need its root cause — it slots between triage (stop the bleeding) and the postmortem (write it up).

## Rules
- **Read `method-and-decision-tree.md` + the tracer header first.**
- **Quit thinking and look.** Instrument and measure before theorising; run the tracer; a real datum beats the best guess.
- **Reproduce first.** No reliable repro → you're guessing. Stimulate the real path, don't simulate.
- **One variable at a time.** Change one thing; prefer the probe that rules out the most. Never shotgun.
- **Confirmed needs a toggle.** Root cause is proven only when you can turn the bug ON and OFF by the suspected cause. Else it's Suspected — say which toggle test is owed. Correlation ≠ cause.
- **Prove the fix.** Remove it → bug returns; re-apply → gone. "It works now" without that is not fixed.
- **A regression guard per confirmed root cause.** A probe/test/alarm so it can't recur silently. Keep the hypothesis ledger as the audit trail.
- **Distributed-first localization.** Use the decision tree + differential to find the layer before touching code. Read-only probes on prod by default; carry guardrails into sub-agents.
