# The verification ladder — what to assert, and how

> "Deployed" is not "working." This file is the method: the L0→L3 ladder, the per-level assertions, the anti-flakiness rules, and the evidence artifact. Read alongside `assets/verify.mjs`. Sources: Playwright docs (best-practices, test-assertions, network, locators, accessibility-testing, trace-viewer), MDN Server-Sent Events, the Chrome DevTools Protocol, Node 22 release notes.

---

## The ladder — assert each rung explicitly (a higher rung does NOT imply a lower one)

| Rung | "Pass" means | The classic failure it catches |
|---|---|---|
| **L0 — Loads** | Navigation completes; top-level document is 2xx; `load` reached. | — (this is the floor; most "checks" stop here) |
| **L1 — Renders real content** | Expected domain text/data is in the DOM, counts > 0, no stuck skeleton/spinner, no error boundary, no empty-state where data belongs. | 200 shell over a stuck spinner / error boundary / empty list |
| **L2 — Wired to backend** | The *right* XHR/fetch fired to the *right* endpoint, returned 2xx, and *its* data is what rendered. | `fetch('/api/mesage')` typo silently 404ing; data never reaches the DOM |
| **L3 — Functional end-to-end** | A user flow works (click → state change → persisted effect, durable across reload); streaming completes incrementally without truncation. | "Submit" does nothing; stream dumps all-at-once or truncates mid-answer |

A 200 that paints clears L0 only. **Assert L1–L3 separately.**

---

## What to assert at each level, and how

Use **web-first, auto-retrying assertions** — `await expect(locator).toBeVisible()`, never `expect(await locator.isVisible()).toBe(true)` (the latter checks once and returns). With the shipped harness, the equivalents are `Runtime.evaluate` oracles polled with bounded retry.

**L1 — content oracles (positive AND negative).**
- Positive: a *specific known datum* is visible; a list/table has `count > 0`; the heading/title is the expected one. Prefer user-facing selectors (role/text) over brittle CSS.
- Negative (equally important): the error-boundary node is absent; the loading skeleton/spinner is **gone** (not merely present-then-forever); the empty-state placeholder is absent when data is expected. A spinner that never resolves is the canonical L0-pass / L1-fail.

**Console fail-gate (subscribe BEFORE navigation).** Fail the run on any `console.error` or uncaught `pageerror`/exception. A page can render correctly and still be throwing — that's a fail.

**L2 — network assertion (two checks).**
1. **The right call happened and succeeded:** wait for the response whose URL matches the *real* API path and assert `ok()` (2xx), then assert (via L1) that its payload reached the DOM.
2. **Network fail-gate:** capture *all* requests; fail on any `/api/*` (or your API prefix) returning 4xx/5xx, **and** on a request to a wrong/misspelled endpoint. The misspelled-endpoint 404 is invisible to the eye and structurally invisible to unit tests — this gate is the reason the skill exists.
Don't mock the backend: mocking forfeits L2; you must exercise the deployed call.

**L3 — flow + streaming.**
- Flow: perform the action, assert the *new* state with L1/L2 oracles, then re-navigate/reload and assert the effect persisted.
- **SSE / streaming** (`Content-Type: text/event-stream`, `data:`-prefixed blocks split by `\n\n`): assert (a) **incremental arrival** — the answer container's text length is strictly *monotonic* across ≥2 timed samples (not just non-empty at the end); (b) **clean close** — EventSource `readyState===CLOSED` / fetch reader `done`, no error; (c) **no truncation** — the final content ends with the expected terminal token/sentinel, the response wasn't aborted. A non-streaming fallback that dumps the whole answer at once is an L3 fail even though the content is present.

**Visual (optional, L1/L3).** A *baseline diff* (`toHaveScreenshot` / compare PNG bytes to a stored baseline), not "a PNG was written". Pin viewport + clock + seeded data first or it's noise.

**Accessibility (optional).** axe-core; fail on `impact` of `serious`/`critical`; gate moderate/minor separately.

---

## Anti-flakiness — a pass must MEAN a pass

- **No `sleep` / fixed timeouts.** They couple to wall-clock, not app state — flaky and slow. Use auto-waiting + retrying assertions; for non-DOM conditions use bounded `expect.poll`/`toPass` (e.g. poll an endpoint until 200), never a bare loop.
- **Avoid `networkidle`.** SPAs with analytics beacons / polling / websockets never reach the 500 ms-silence it waits for — it times out or fires against a half-loaded page. Wait on a **content oracle** or a **specific** response instead.
- **Pin nondeterminism** before any visual diff: fixed viewport, frozen clock/`Date.now`, seeded data, stable locale.
- **Isolate state:** fresh storage/cookies per run; don't depend on prior-run residue.
- **Retry-quorum:** run N times (3–5); require a *consistent* pass. 4/5 is a flaky-fail to investigate, not a pass. Record a trace on retry.

---

## The evidence artifact (evidence before claims)

A run emits a **structured per-assertion pass/fail report**, keyed by ladder level, each oracle named — plus attached: the captured **console** + **network** logs, the **screenshot(s)** (and baseline+diff if visual), and a Playwright **trace.zip** when Playwright is the driver (DOM snapshots, film-strip, network, console, sources — open in Trace Viewer). The harness's JSON report is itself the artifact. "Tests pass" / "it loaded" without these is not evidence.

Verdict vocabulary: **VERIFIED** (every applicable rung asserted + passed, evidence attached) · **BROKEN** (rung N failed — name the oracle + attach the proof + repro) · **UNVERIFIED** (could not assert rung N — say which and why; never upgrade to VERIFIED).

---

## Driving headless Chrome with zero npm deps (CDP)

Node 22 ships global `fetch` and global `WebSocket` (Undici, on by default), so the shipped `verify.mjs` drives Chrome with no install:
1. **Launch:** `chrome --headless=new --remote-debugging-port=9222 --no-first-run --user-data-dir=<tmp>` (use `--headless=new`; old headless is a no-op on recent Chrome). Or attach to an already-running instance.
2. **Discover:** `fetch('http://127.0.0.1:9222/json/version')` → browser `webSocketDebuggerUrl`; `GET /json/new?<url>` or `/json` → a page target's `webSocketDebuggerUrl`.
3. **Connect:** `new WebSocket(wsUrl)`; send `{id,method,params}`, receive `{id,result|error}` and unsolicited `{method,params}` events. Match `id`→resolver in a Map; buffer events by method.
4. **Command flow:** `Page.enable`, `Runtime.enable`, `Network.enable`, `Log.enable`/`Runtime` console → subscribe `Network.requestWillBeSent`/`responseReceived` (network log + fail-gate), `Runtime.consoleAPICalled`(level error)/`Runtime.exceptionThrown` (console fail-gate) → `Page.navigate{url}` + await `Page.loadEventFired` (L0) → `Runtime.evaluate{expression,returnByValue:true}` for L1 oracles and the SSE monotonic-length poll (L3) → `Page.captureScreenshot{format:'png'}`.

The **chrome-devtools MCP** exposes the same power with zero code (`navigate_page`/`evaluate_script`/`list_network_requests`/`list_console_messages`/`take_screenshot`). **Playwright** gives web-first `expect` + Trace Viewer + `toHaveScreenshot` for free when an install is acceptable. Same ladder, three drivers.

---

## Sources
Playwright: best-practices, test-assertions, network, locators, accessibility-testing, trace-viewer (playwright.dev). Anti-flakiness: Playwright best-practices + community guidance on `networkidle` misuse. CDP: chromedevtools.github.io/devtools-protocol. Node 22 built-in fetch/WebSocket: nodejs.org v22 release. SSE: MDN "Using server-sent events".
