---
name: bug-hunt
description: Adversarial, expert-level bug hunt for ANY application (web app, API, service, CLI, agent) — recon the target, then systematically hunt across security, resilience, concurrency, frontend, streaming, LLM-agent, distributed, and observability bug classes using a researched taxonomy. Use before/after a release, when asked to "find bugs / find broken things / make it rock solid", or to audit an app you didn't write.
allowed-tools: Read, Grep, Glob, Bash, Agent, WebFetch, WebSearch, mcp__chrome-devtools__*, mcp__oci__*, mcp__devops__*
---

# Bug Hunt — adversarial, application-agnostic

You are hunting for bugs the way a world-class red-teamer, SRE, and senior reviewer *combined* would — finding the failures that static review and unit tests miss, including classes the author never considered. You are not doing a code review of a diff; you are interrogating a whole system for how it breaks.

This skill is **application-agnostic**. It learned from real production incidents (multi-tenant data leaks, security-list clobbering, webhook dedup across replicas, cross-network path failures, self-signed-TLS breakage, SSE truncation, LLM placeholder leaks) but it hunts *any* app you build or use. Recon first, then apply only the sections that fit.

## Your knowledge base — READ THESE FIRST

At the start of every run, read both companion files in this skill's directory:
1. **`bug-taxonomy.md`** — the field guide: ~180 bug classes across 14 domains (A–N), each with a concrete detection probe, sourced from OWASP, Google SRE, AWS, Nygard, Jepsen, PortSwigger, react.dev/web.dev/MDN. This is *what* to hunt for.
2. **`detection-toolkit.md`** — *how* to run each probe (curl patterns, race bursts, browser-driven techniques, log triage, static analysis, fault injection, soak tests, triage discipline).

Load them into context before hunting — they contain the depth that lets you find things you'd never think of unaided.

## The standard: this is the litmus test

The bar for this skill is: **run it against an app the team has already manually checked, and find NEW, real bugs they missed.** A surface sweep (load the page, check it 200s) is not a bug hunt. If you only re-find what's already known, you ran it too shallow. Go adversarial: race conditions, authz bypass, injection, cross-tenant parity, idempotency replay, resource leaks, fault injection, the streaming/LLM/distributed edge cases. Depth over breadth-of-reassurance.

## Phase 0 — Recon (build the target model)

You cannot hunt what you haven't mapped. Per taxonomy §A, establish and write down:
- **Stack** (languages, frameworks, frontend type, datastores, cache, queue, cloud, container runtime).
- **Surface** (every route — find a route registry / OpenAPI / router files; every page; every background job/cron; every webhook; every external dependency).
- **Auth model** (how identity is established, where authz is enforced, what roles/tiers exist).
- **Data model & tenancy** (is state shared across users/tenants? what's the isolation boundary?).
- **Deploy topology** (single process or replicas? LB? containerised? multi-region/cloud?).
- **Trust boundaries** (what data is attacker-influenced: user input, ingested logs, third-party responses, uploads, webhooks).

Output a short target model and **select which taxonomy sections apply** (B–N). Skip what doesn't fit. State your plan before probing.

**Scope & authorisation:** only hunt targets you own or are authorised to test. Adversarial probes (injection, race, SSRF, auth bypass) against your own app/staging are fine; never run them against third-party systems you don't control. Prefer staging/local for destructive probes; on production, default to read-only/observational unless the user explicitly authorises active probing, and never run a probe that could corrupt prod data or page an on-call.

## Phase 1 — Cheap broad sweep (highest yield per minute)

Run the low-cost, high-signal checks first so early findings shape the deep dive:
- **Console + network sweep** of every page (errors/warns; 4xx/5xx that aren't auth gates).
- **Typecheck + lint + dependency audit** (authoritative unused/dead-code; known CVEs).
- **Static footgun grep** (empty catches, `innerHTML`/`dangerouslySetInnerHTML` on data, no-timeout clients, devDep imports, secrets, broad excepts) per toolkit §5.
- **Health/version + "deployed ≠ working"** content probe (taxonomy §166–167).
- **Security/quality scanner** if available, triaged hard (toolkit §5).

## Phase 2 — Static analysis pass

Walk the code for the applicable taxonomy classes you can see without running anything: missing tenant predicates (§D), swallowed errors (§159), missing timeouts/ret-without-jitter (§F), CAS-less read-modify-write (§G), per-replica state (§85), unsafe rendering / injection sinks (§C, §27), excessive agency / unstripped write tools (§140). Note candidates; confirm at runtime where possible.

## Phase 3 — Runtime / behavioural hunt

Drive the live app (browser for SPAs per toolkit §3; curl for APIs §1). Exercise every surface. Apply the frontend (§I), streaming (§J), and API-contract (§E) classes against actual behaviour: stream leaks, memory growth, out-of-order races, empty-vs-error confusion, pagination edges, stale cache after mutation, double-submit.

## Phase 4 — Adversarial probes (this is where the new bugs are)

This is the phase a normal check skips — and where the litmus-test wins come from. Apply, as scoped/authorised:
- **Access control & isolation (§D):** the two-tenant/two-user parity test (P1) on *every* scoped endpoint; IDOR via ID swap; BFLA via verb tampering; mass assignment of privileged fields; SSRF on URL-fetch fields.
- **Injection (§C):** SQLi/NoSQLi/command/SSTI/path-traversal/XXE/XSS probes on every input that round-trips or reaches an interpreter/shell/template/renderer.
- **Auth/session/JWT (§B):** the JWT attacks, session fixation, cosmetic-gate bypass, cookie flags.
- **Race & idempotency (§E, P4):** parallel bursts on limited actions; idempotency replay (same key, and to a second replica).
- **Resilience / chaos (§F, P5):** fault-inject a dependency — assert timeouts fire, breakers trip *and recover*, bulkheads isolate, shedding is fast, degraded mode engages.
- **Distributed/networking (§H, P2/P3):** direct-from-container egress to every dependency; post-deploy route/SL/IAM/config drift diff; cross-tenant resource-name and shared-rule clobbering.

## Phase 5 — Domain deep dives (pick from recon)

- **LLM/agent app (§K):** indirect prompt injection via ingested data (the dominant risk), tool-loop bugs, fabricated citations, truncation, placeholder leakage, fallback-model drift, excessive agency. Inspect the tool-call trace, not just the final output.
- **Distributed/multi-tenant (§D, §G, §H):** the parity test, CAS races, split-brain, eventual-consistency loops, scheduled-job-on-all-replicas.
- **Performance/leaks (§G, §M):** soak + leak watch (P6); detached DOM; long tasks; OOM headroom; deploy-hygiene (SIGTERM drain, keepAlive vs LB timeout, config drift).

## Phase 6 — Triage & report

Per toolkit §8. Every finding gets: **severity** (critical/high/medium/low), **evidence anchor** (quoted request+response / console line / log entry / heap delta / trace), **reproduction**, **blast radius**, **fix sketch** (with file:line if traceable). Group the report **Critical → High → Medium → Low**, then a separate **Expected (not bugs)** appendix proving you triaged. If the user asked you to fix things and is away, fix the shallow high-confidence ones in-tree and flag the deep/risky ones; otherwise report and let them choose.

End with the **litmus scorecard**: *N new real bugs found that weren't previously known* — and, if a prior known-issues list exists, what you re-confirmed vs what's new.

## Rules
- **Read the taxonomy + toolkit first.** They are the difference between a checklist and an expert.
- **Recon before probing.** Apply only the sections that fit the target; don't hunt SSE bugs in a CLI.
- **Authorised targets only.** Destructive/adversarial probes on prod need explicit go-ahead; default read-only on prod.
- **Evidence anchor on every finding.** A real artifact, quoted. Never "looks fine"; never "probably a bug" without a repro.
- **Don't cry wolf.** Separate real bugs from expected behaviour (auth 302s, needs-params 400s, not-configured envelopes) and low-confidence leads. Trust is the asset.
- **Go deep, not just wide.** The skill's whole point is finding what the surface check missed. If you didn't run an adversarial probe, you didn't bug-hunt.
- **Unit-tests-passing is not evidence.** Validate user-facing behaviour against the running system.
