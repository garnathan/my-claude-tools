# Oracle methods & hunt rigor — how to find bugs nobody anticipated

> The taxonomy (`bug-taxonomy.md`) enumerates *known* bug classes. This file is what lets the hunt find **novel, app-specific bugs** — and hold itself to the bar that leading 2026 bug-finding systems (XBOW, Google Big Sleep, OSS-Fuzz-Gen, Antithesis, Jepsen) actually meet. Read it after the taxonomy.
>
> **The one idea behind everything here:** a checklist tests known bug *classes*; the real spec of *this* app is mostly unwritten. So you **manufacture an oracle** — a statement that must be true — and then attack it. Five ways to manufacture one (Part 1), wrapped in the rigor that makes a finding trustworthy and the hunt complete (Part 2). The pre-Opus-4.8 tools couldn't run this much reasoning per dollar. You can. Use it.

---

# Part 1 — Manufacture an oracle, then attack it

## O1. Invariant discovery (the master technique)

Derive statements that must *always* hold, then design one probe to violate each. This is the highest-yield move because it converts "I don't know what's wrong" into a finite list of falsifiable claims.

**Mine invariants three ways:**
- **From code** — read the models/handlers/guards. Every `if (x < 0) throw`, DB `NOT NULL`/`UNIQUE`/foreign key, auth check, enum, and assertion *is* an invariant the author believed. List them.
- **From docs/types/tests** — the README, OpenAPI, type definitions, and test names all *claim* invariants ("idempotent", "filters by tenant", "returns 404 if missing", "admin-only").
- **Dynamically** (Daikon-style) — hit the API ~30–50× with varied valid inputs, log every response field, and note what was *always* true: a field never negative, a count that only rose, an ID always present, a timestamp always increasing, two fields always equal. Those empirical invariants are free oracles.

**Then attack each.** Phrase it "X must ALWAYS be true", and craft the input/sequence that *should* break it:
- "balance never negative" → post a negative/huge amount, a concurrent double-spend.
- "tenant A never sees tenant B's data" → the two-identity parity test on every scoped read.
- "a retried request has exactly one effect" → idempotency replay.
- "this field is always a valid enum" → send a plausible-but-invalid value.
- "the result count never exceeds the page size" → crank the limit.

A surviving invariant is a passed test; a violated one is a bug with a built-in repro.

## O2. Metamorphic relations (when there's no exact oracle)

You often can't know the *exact* right output (search, ranking, aggregation, LLM/ML, recommendations). But you know *relations between* outputs of related inputs. Derive 3–5 per endpoint and test them:
- **Superset:** `search("a OR b")` ≥ `search("a")`. Adding an OR-term never shrinks results.
- **Monotonic:** adding a restrictive filter never *increases* results.
- **Count-preserving:** paginating then concatenating == the unpaginated set (no dupes, no gaps).
- **Idempotent:** `PUT x` twice == once.
- **Order-independent:** the answer must not depend on the order of equivalent inputs (e.g. retrieved-doc order must not flip an LLM verdict).
- **Round-trip:** encode→decode, serialise→parse, translate→back ≈ identity.
A broken relation is a bug even when you can't say what the "right" number was.

## O3. Differential testing (use the second implementation you already have)

Same input → two things that *should* agree; any divergence is a bug. Most apps have free oracles hiding in plain sight:
- **Replica A vs replica B** — same request to each (bypass LB stickiness / hit containers directly). Divergence = per-replica state drift.
- **Old build vs candidate** — replay a corpus against both; diff status/body/timing. Catches regressions a single-build test can't see.
- **API v1 vs v2**, **cached vs uncached path**, **UI-computed value vs API-computed value**, **profile-A output vs profile-B** for the same logical query.
- **Doc/spec vs behaviour** (see O5).
Capture a corpus of real inputs, replay against both targets, structural-diff (ignore known-variant fields like timestamps/request-ids). The diffs are the bugs.

## O4. Stateful sequence exploration (bugs that need a story, not a request)

Single-request probes can't reach lifecycle bugs. Model the app as a state machine — list the operations and the resource they share — then explore *sequences* and assert invariants after each step. The killer sequences:
- **use-after-delete:** create → delete → access (still works? 500s? leaks?).
- **revoke-then-use:** grant → act → revoke → act again (still authorised?).
- **share→unshare→access**, **partial construction** (act on a half-built resource), **double-transition** (drive a status machine through an illegal edge).
For state held across replicas/requests, collect a *history* and check it's consistent (Jepsen-style: would a single correct server have produced this sequence of reads/writes? if not, it's a consistency bug).

## O5. Specification-vs-behaviour diff (every claim is a test)

Extract every *claim* the system makes about itself and verify the running system honours it:
- README/docs ("idempotent", "rate-limited", "filters by X", "returns 404 if missing").
- OpenAPI/types (response shape, enums, required fields, error codes).
- Comments and test names ("admin-only", "must be ≥ 0").
- **Deferred/known-TODO items** in the code or backlog — these are documented gaps; verify the *current* behaviour matches what's claimed, not what's intended.
For each claim, construct the exact call and assert it holds. Every gap is either a code bug or a doc bug — both worth reporting. (Drift bugs hide here: the endpoint that no longer matches its docstring, the error code never thrown, the param silently ignored.)

## O6. Variant analysis (your unfair advantage — seed from history)

Every bug already fixed in this codebase is a *template* for an un-fixed sibling elsewhere. This is how Google Big Sleep found a real 0-day: seed from a known bug's diff, hunt the same class.
- Mine the project's **incident history**: `git log --grep=fix`, CHANGELOG, an incident/memory directory, post-mortems, closed bug tickets.
- For each past bug, extract the *class* ("a filter wasn't tenant-prefixed", "a retried webhook double-fired", "a shared rule got clobbered by a sibling deploy", "an SSE stream wasn't closed on unmount") and **grep/probe for the same class everywhere else** it could occur.
- Bugs cluster. The team's past mistakes predict its present ones. A skill that ignores the repo's own scar tissue is leaving the easiest wins on the table.

---

# Part 2 — Hunt rigor (trustworthy findings, complete coverage)

## R1. Proof-of-exploit gate — Confirmed vs Suspected

A detection is not a bug. Borrowed from XBOW's "validators": every candidate gets one honest attempt at a **runnable proof**, and the report is split on the result:
- **Confirmed** — you demonstrated impact: the IDOR request actually returned another tenant's row; the race actually double-spent; the injected payload actually executed; the leak actually appeared in the response. Quote the proof.
- **Suspected** — code/behaviour looks wrong but you couldn't (or shouldn't, on prod) prove impact. Say so, and say what proof is missing.
Never present Suspected as Confirmed. The single fastest way to destroy the skill's trust is a "critical" that turns out to be a non-issue. A confirmed low beats a suspected critical.

## R2. Coverage ledger — you cannot claim "done" with blank cells

Maintain an explicit grid of **(surface × applicable technique/class)** as you go — write it to a scratch file. Each cell is `covered` / `skipped (reason)` / `finding #N`. Before declaring the hunt complete you must show the ledger; any `uncovered` cell is either probed or explicitly listed as a gap with a reason. This is the antidote to the failure that motivated this whole skill: *claiming "verified" while obvious bugs remained because nobody tracked what was actually checked.* Coverage is a claim you have to back with the grid.

## R3. Parallel fan-out (spend the reasoning the old tools couldn't)

For a non-trivial target, after recon + invariant-derivation, **spawn one sub-agent per domain** (authz/isolation, injection, concurrency/idempotency, resilience/chaos, frontend/streaming, LLM-agent, distributed/networking, observability) against the shared target model + invariant list + ledger. Each returns findings with evidence; you merge, dedupe, and cross-check. This is the capability that pre-Opus-4.8 single-thread tools couldn't afford — use it. Keep each sub-agent's scope tight and its guardrails explicit (same authorisation limits as the parent).

## R4. Dataflow before you cry "injection" (kill hallucinated findings)

Before reporting an injection/SSRF/traversal sink, **trace the actual path** from the attacker-controlled source to the dangerous sink (grep/AST the variable from input to query/exec/fetch/render). If the taint doesn't reach the sink, or it's sanitised on the way, it's not a finding. This both raises precision and is the documented way (LLMxCPG/LLMDFA) to stop an LLM from confidently inventing vulns. A finding that "looks like SQLi" without a traced source→sink path is Suspected at best.

## R5. Self-critique pass — "what did I miss, what's a false positive"

After the hunt, do a deliberate adversarial review *of your own findings*, ideally with fresh context (a sub-agent that didn't run the hunt):
- **Kill false positives:** for each finding, can it actually be reproduced? does the dataflow hold? is it expected behaviour (auth-gate 302, needs-params 400, not-configured envelope)? Demote or drop anything that doesn't survive.
- **Name the gaps:** what attack surface did I *not* probe? what invariant did I assume held without testing? *Mutation-test the hunt:* "if I flipped this `>=` to `>` / removed this auth check, would any probe I ran have caught it?" If not, that's a blind spot — go probe it.

## R6. Severity + confidence on every finding

Score each finding two ways:
- **Severity** (taxonomy rubric: critical/high/medium/low) — impact × reachability.
- **Confidence** (high/medium/low) — how sure you are it's real. A high-severity / low-confidence item is a *lead to verify*, not a headline. Anthropic's own security review ships both; so do you.
Use CVSS-style reasoning for security findings (attack vector, privileges required, impact on C/I/A) when it sharpens the call.

## R7. A regression test (or repro harness) per Confirmed bug

A hunt that finds a bug and moves on leaves the door open for it to come back. For every Confirmed finding, produce an **executable artifact that fails now and passes once fixed** — a unit/integration test, or a saved repro command/script. This turns the hunt into durable coverage and is the deliverable that compounds across runs. (If the user only wants a report, still hand them the repro command per finding.)

---

# The run, in one breath

Recon → derive invariants + metamorphic relations + differential pairs + variant seeds from history → build the coverage ledger → fan out per domain → attack every oracle → prove impact (Confirmed vs Suspected) with traced dataflow → self-critique to kill FPs and name gaps → score severity+confidence → emit findings + a regression test each + the ledger. **Build an oracle, then attack it. Prove it. Track what you covered. Then say what you missed.**
