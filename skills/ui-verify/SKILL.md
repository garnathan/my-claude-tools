---
name: ui-verify
description: Prove a deployed web UI actually WORKS — not just that it loaded. "Deployed ≠ working": assert semantic content (real data rendered, not a stuck skeleton or error boundary), fail on console errors and wrong/failed network calls, verify streaming (SSE) arrives incrementally and closes cleanly, diff a visual baseline, check accessibility — and emit a structured evidence report. A pass must MEAN a pass (deterministic waits + retry-quorum, never sleep/networkidle). Ships a zero-dependency CDP driver (Node 22 + a Chrome binary — no npm install, no Playwright) and also drives via the chrome-devtools MCP or Playwright when present. Use before claiming a UI change is done, to validate a deploy, to catch the "tests pass but the page is broken" class, or to verify a PR's user-facing behavior.
allowed-tools: Read, Write, Bash, Agent, WebFetch, WebSearch, mcp__chrome-devtools__*
---

# ui-verify — prove the deployed UI works, with evidence

You verify a web UI the way the rule "**unit tests passing is NEVER sufficient**" demands: you drive the *real, running* app and prove **user-facing behaviour**, then attach the evidence. "Deployed" — HTTP 200, the page paints — is **not** "working": a 200 shell can wrap a stuck spinner, an error boundary, an empty list, a `fetch('/api/mesage')` typo silently 404ing, or a stream that never streams. This skill exists because a release once passed unit tests and shipped a deployed SPA with three obvious user-visible bugs. Your job is to make that impossible to claim again.

This skill is **application-agnostic** (any web UI / SPA) and **portable**: it ships a zero-npm-dependency CDP driver, and also uses the chrome-devtools MCP or Playwright when those are available.

## Read your knowledge base FIRST

In this skill's directory:
1. **`verification-ladder.md`** — the L0→L3 ladder (loads → renders real content → wired to backend → functional end-to-end), what to assert at each level and how (content oracles, console + network **fail-gates** incl. wrong-endpoint detection, SSE incremental-growth + clean-close, visual baseline diff, axe a11y), the anti-flakiness rules (no `sleep`/`networkidle`; web-first auto-retrying assertions; retry-quorum), and the evidence artifact. *The method.*
2. **`assets/verify.mjs`** — the shipped zero-dependency verification harness. Read its header for the config schema + CLI. It launches/attaches headless Chrome over the DevTools Protocol (Node 22 built-in `fetch` + `WebSocket` — no npm install), runs your content oracles, captures console + network as fail-gates, samples streaming growth, screenshots, and emits a structured pass/fail report. There is nothing better worth installing.

## Choosing a driver (in order of preference)
1. **chrome-devtools MCP** (`mcp__chrome-devtools__*`) — if available, zero code: `navigate_page`, `evaluate_script`, `list_network_requests`, `list_console_messages`, `take_screenshot`, `take_snapshot`. Best for interactive, exploratory verification.
2. **Shipped `assets/verify.mjs`** — zero npm deps, repeatable, emits the structured report. Best for a scripted gate you can re-run in CI.
3. **Playwright** (`npx playwright`) — if a toolchain install is acceptable; gives web-first `expect`, trace viewer, and `toHaveScreenshot` diffing for free.
All three speak the same ladder; the assertions in `verification-ladder.md` are what matter, not the driver.

## The standard (litmus test)
Run against a UI someone believes is fine and **catch a "deployed ≠ working" defect that an HTTP-200/`networkidle`/screenshot-exists check misses** — a stuck skeleton, an empty list where data should be, a console error, a 4xx to the wrong endpoint, a stream that arrives all-at-once or truncates. And the converse: when it passes, the pass **means** it — deterministic waits + retry-quorum, with the evidence attached. If your check would go green on a blank-but-200 page, it isn't a verification. **Opus 4.8 can derive the right content oracles for *this* app by reading its code/DOM and reason about what "working" means** — use that; don't run a generic screenshot.

## Phase 0 — Recon: what does "working" mean here?
Map the surface and define the oracle before driving. Read the app (routes/pages, the components under test, the API calls they make, whether it streams) and/or observe it. For the page(s) in scope, write down: the **real data/text** that must render (specific, e.g. "≥1 row in the results table", "the user's name in the header"), the **endpoints** the page must call (and must NOT call — the wrong-endpoint trap), whether it **streams**, and the **negative** oracles (no error boundary, no stuck skeleton/spinner, no empty-state). Confirm **auth** (how to reach an authenticated view — cookie/session/Bearer) and **environment** (local/staging/prod; prod is read-only by default — verify, don't mutate, unless authorised).

## Phase 1 — Drive + assert the ladder
Pick a driver, then assert each rung explicitly (a higher rung does not imply a lower one — `verification-ladder.md`):
- **L0 loads** — navigation completes, top-level 2xx (not a 200 shell over a rendered 500 / SPA 404 route).
- **L1 renders real content** — content oracles pass (expected text/data present, counts > 0) AND negatives hold (no error boundary, no stuck skeleton).
- **L2 wired to backend** — the *right* XHR/fetch fired to the *right* endpoint, returned 2xx, and *its* data is what rendered. Don't mock the backend — exercise the real call. **Network fail-gate:** any `/api/*` 4xx/5xx or a call to a wrong/misspelled endpoint fails the run.
- **L3 functional end-to-end** — a user flow (click → state change → persisted effect; re-navigate and re-assert) and, if it streams, **SSE verification**: tokens arrive incrementally (monotonic growth across samples), the stream closes cleanly, no truncation.
Throughout: **console fail-gate** (any `console.error`/uncaught exception fails), optional **visual** baseline diff (not "a PNG exists") and **axe** a11y (fail on serious/critical).

## Phase 2 — Make the pass mean a pass (anti-flakiness)
No `sleep`, no `networkidle` (SPAs with polling/analytics never idle). Wait on a **content oracle** or a **specific** response, using web-first auto-retrying assertions / `expect.poll`. Pin viewport + clock + seeded state before any visual diff. **Retry-quorum:** run N times (e.g. 3–5); require a *consistent* pass — a 4/5 is a flaky-fail to investigate, not a pass.

## Phase 3 — Evidence + verdict
Emit a **structured per-assertion report** keyed by ladder level (each oracle named, pass/fail), with the **trace/screenshot/console+network logs attached**. State the verdict honestly: **VERIFIED** (every rung asserted + passed, evidence attached), **BROKEN** (which rung failed + the evidence), or **UNVERIFIED** (couldn't assert a rung — say which and why; never upgrade this to VERIFIED). "Tests pass" or "it loaded" without the report is not evidence. For a found defect, give the failing oracle + the captured console/network proof + repro.

## Relationship to other skills
`ui-verify` proves a UI *works*; **`bug-hunt`** hunts for *what's broken* across all classes; **`chaos`** proves *resilience under fault*; **`pentest`** proves *what an attacker does*. Use `ui-verify` as the "is it actually done?" gate after any UI change or deploy — it's the operational form of the quality rule.

## Rules
- **Read `verification-ladder.md` + the harness header first.**
- **Deployed ≠ working.** HTTP 200 / "it loaded" / a screenshot existing is L0 — assert L1–L3 explicitly. Assert *specific* content, not "some text".
- **Console + network are fail-gates.** Any console error, any `/api/*` 4xx/5xx, any call to the wrong endpoint = fail. This is the class unit tests structurally can't catch.
- **Exercise the real backend.** Mocking forfeits L2. Verify the deployed thing, not a stand-in.
- **Verify streaming as streaming** — incremental growth + clean close + no truncation, not "the answer is present at the end".
- **A pass must mean a pass.** No `sleep`/`networkidle`; deterministic waits + retry-quorum. Pin nondeterminism before visual diffs.
- **Evidence before claims.** Emit the structured report with artifacts attached. VERIFIED / BROKEN / UNVERIFIED — never dress UNVERIFIED as VERIFIED.
- **Read-only on prod** unless mutation is authorised; carry guardrails into sub-agents.
