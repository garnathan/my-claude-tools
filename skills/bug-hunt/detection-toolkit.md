# Detection Toolkit — how to actually run the probes

> Concrete, copy-adaptable techniques for each detection method the taxonomy references. Tool-agnostic where possible; notes the common stacks. The `bug-hunt` skill reads this when it needs the *how* behind a probe.

---

## 1. HTTP probing (curl)

The workhorse. Notes that save time:

- **Use an explicit binary path if a shell alias shadows `curl`** (some dev environments alias it). `/usr/bin/curl` on macOS/Linux.
- **Status-only sweep:** `curl -s -o /dev/null -w "%{http_code} %{time_total}s\n" -H "Authorization: Bearer $TOKEN" "$URL"`
- **Headers:** `curl -sD - -o /dev/null "$URL"` — inspect `Set-Cookie` flags, CORS, cache, security headers.
- **Verb tampering:** `-X POST/PUT/DELETE/PATCH` on the same route; compare authz.
- **Content-type confusion:** swap `-H 'Content-Type: application/json'` ↔ `x-www-form-urlencoded` ↔ `text/plain`.
- **Auth-bypass headers:** `-H 'X-Forwarded-For: 127.0.0.1' -H 'X-Original-URL: /admin'`.
- **Two-identity parity (P1):** run the same request with `TOKEN_A` then `TOKEN_B`; `diff` the bodies; assert disjoint.
- **Follow vs not:** default doesn't follow redirects — a `302 → /login` is an auth gate, not a failure. Use `-L` only when you mean to.
- **Self-signed internal TLS:** `-k` to test reachability, but separately assert the cert *should* validate with the proper CA (don't let `-k` hide a real trust bug).

**Route discovery:** look for a live route registry (`/api/_routes`, `/api/tools/v1/system/routes`), an OpenAPI/Swagger doc (`/openapi.json`, `/swagger.json`, `/api-docs`), or the router source files. Sweep every no-param GET; bucket the codes (2xx/3xx pass; 400 = often needs-params, confirm; 404 `not_found` envelope = not-configured, confirm; 404-routing / 5xx = real).

**Parsing gotcha:** API payloads (route registries, log dumps) sometimes contain embedded control characters that break a strict JSON parse. In Python use `json.loads(s, strict=False)`. In `jq`, if it errors, fall back to Python.

---

## 2. Concurrency / race-condition probing (P4)

To hit a true race you must remove request jitter:

- **Parallel burst (bash):** fire N in the background, wait:
  ```bash
  for i in $(seq 20); do curl -s -X POST "$URL" -H "$AUTH" -d "$BODY" & done; wait
  ```
- **Tighter window:** HTTP/2 single-packet attack (Burp Repeater "send group in parallel") or last-byte-sync for HTTP/1.1 drops ~20–30 requests into <1ms.
- **What to assert:** a single-use/limited action executed more than once (double-spend, limit overrun, duplicate create). Count successful effects, not just 200s.
- **Idempotency replay:** send the same mutation twice with the same idempotency key (and again to a *different* replica) → assert exactly one effect + identical response.

---

## 3. Browser-driven SPA hunting (chrome-devtools MCP or Playwright)

Per page, in order (cheapest first):

1. **Navigate + snapshot** the a11y tree to see structure (`take_snapshot`).
2. **Console errors/warnings** (`list_console_messages` filtered to `error`,`warn`) — every red error or framework warning (keys, hooks, controlled/uncontrolled, `act()`) is a lead.
3. **Network 4xx/5xx** (`list_network_requests` filtered to fetch/xhr) — flag every non-auth-gate failure. A 404 the frontend fires on a profile that lacks the feature is a bug, not a non-issue.
4. **Visual scan** of the snapshot for: stale/empty/error-state confusion, wrong-tenant data, `NaN`/`undefined`/`Invalid Date`/`[object Object]` in the DOM, controls that should be hidden for this role.

SPA-specific techniques:
- **SSE/stream leak:** filter Network to `eventsource`/`fetch`, navigate away+back N times, watch "pending" stream rows accumulate.
- **Memory leak:** Memory panel → heap snapshot before/after repeating an action (open+close a panel, run+navigate) ×3 → comparison view shows objects that grow each cycle; "Detached" filter for orphaned DOM.
- **Cosmetic authz:** as a low-priv user, open console and `fetch()` an admin endpoint directly (or "copy as fetch" an admin request from the Network tab) → 200 instead of 403 = client-only gate.
- **Tamper client-side role:** edit the tier/role value in localStorage/sessionStorage/a JWT claim → does admin UI unlock? does the API still reject?
- **Timezone bug:** DevTools → Sensors → set a different timezone → reload → does a date's *day* change?
- **Lighthouse** (`lighthouse_audit` / DevTools): a11y, best-practices, CLS, LCP per route.
- **Throttle/offline:** Slow 3G or Offline mid-action to surface missing loading/error states and mid-stream-disconnect handling.

If the app is behind SSO and a page redirects to a login provider, ask the human to complete sign-in once — don't try to defeat auth programmatically.

---

## 4. Container / server log triage

- Pull logs via the platform's API/CLI. **They often exceed an inline token cap** — save to a file and parse.
- Common shape: a wrapper object whose field is itself a JSON string whose field is the multi-line log → parse defensively (`json.loads(..., strict=False)`, or regex-extract the inner string).
- Count log levels; **quote every error/fatal verbatim with its component**. A clean window is stated as "of N entries, 0 at level ≥ error".
- **Pull a window that straddles process start** to confirm the boot/"listening" signal; a window from steady-state won't show it.
- Cross-check: a level-50 every few minutes on a schedule = a failing cron (see taxonomy §95).

---

## 5. Static / code analysis

- **Typecheck for unused + dead code:** the compiler is the authoritative source for unused imports/locals (e.g. `tsc --noEmit --noUnusedLocals`) — far more accurate than heuristic scanners that over-report.
- **Static-analysis taint sweep (Semgrep / CodeQL) — a recon multiplier, not the verdict.** Run interprocedural taint analysis to surface *candidate* source→sink flows your eyes miss across files, then feed every hit into the prove-impact gate (R1): a scanner hit is **Suspected** until you trace source→sink (R4) and demonstrate impact. Do it with discipline (the Trail of Bits playbook):
  - **Semgrep (no build needed):** `semgrep --config auto --metrics=off` for the baseline, then layer third-party taint rulesets (Trail of Bits `semgrep-rules`, 0xdea, Decurity) for your stack. `--metrics=off` for audit hygiene. OSS Semgrep taint is single-function — pair it with the LLM dataflow trace (R4) for interprocedural flows; Semgrep Pro adds cross-file/cross-function taint, use it where available.
  - **CodeQL (where a build exists):** the strongest interprocedural taint. **A database that *builds* is not automatically *good*** — verify it captured the code you care about (expected files/row counts) before trusting results. Run **explicit query suites** (`.qls`) so queries aren't silently dropped. For custom wrappers/sinks the default models miss (your own `db.query`, an auth helper, an OCS/object-store client), add **data-extension models** so taint flows through them — otherwise you get false *negatives*, the dangerous kind.
  - **Zero findings is a signal to investigate, not celebrate** — usually the DB missed the code, the suite was wrong, or your sinks aren't modelled. Confirm the tool *can* see a known issue first.
  - **Parallel scanning:** for a large repo, fan scans out (per package / per ruleset) across sub-agents (R3) and merge.
  - **Triage hard** — these over-report on polyglot repos. Strip noise first: vendored deps, lockfile hashes flagged as "secrets", test/bench fixtures, generated code, agent-worktree clones. Then separate real signal (taint reaching a query/exec/render, swallowed exceptions, broken test mocks) from FPs (SSRF on a local stdio client, "hallucinated dep" on a local import). **Authorisation:** these run external tooling over the codebase — only on a repo you're cleared to scan.
  Static analysis finds *candidates fast and across files*; bug-hunt's job is to **prove** them (R1) and feed the confirmed *classes* back into variant analysis (O6 abstraction ladder).
- **Grep for footguns:** empty `catch {}` blocks; `dangerouslySetInnerHTML` / `innerHTML` fed by data; network clients with no timeout; `new require(`/dynamic import of a devDependency; secrets in source; `TODO`/`FIXME`/`XXX` near security or money code; `eval`/`Function(`; broad `except Exception: pass`.
- **Dependency audit:** `npm audit` / `osv-scanner` / `pip-audit` for known CVEs; check versions are pinned, not floating.
- **Run the test suite + coverage** — but remember unit-tests-passing is *not* evidence of working behaviour (a recurring lesson: tests passed while the deployed UI had obvious bugs). Behavioural validation against the running app is mandatory.

---

## 6. Fault injection / chaos (P5)

- **Black-hole a dependency:** point it at an unresponsive IP / blocked port, or use a proxy that drops/delays → assert the caller times out within budget and the breaker trips.
- **Inject errors:** a fault-proxy (toxiproxy) or app-level chaos hook returning 429/503/timeout/garbage for the next N calls → verify fallback fires, breaker trips *and recovers*, degraded mode engages.
- **Kill a replica:** confirm the LB pulls it (readiness), in-flight requests drain, no 502s, and any singleton job keeps running on exactly one survivor.
- **SIGTERM mid-request:** confirm graceful drain, no dropped connections.

---

## 7. Soak / leak watch (P6)

- Drive sustained representative load for hours (k6/artillery, or a read-only prod-safe probe).
- Graph over the run: RSS/heap, open FD count, connection-pool in-use, event-loop lag, p99 latency.
- **Assert each plateaus.** A steady upward slope = leak. A sawtooth that doesn't return to baseline = leak. Rising event-loop lag = a sync hotspot under load.

---

## 8. Triage discipline (turn findings into a report)

For every candidate finding produce:
- **Severity** (per the rubric in the taxonomy): critical / high / medium / low.
- **Evidence anchor:** the exact request+response / console line / log entry / heap delta / trace excerpt. Quote it.
- **Reproduction:** the precise steps or command.
- **Blast radius:** who/what is affected, how often.
- **Real vs expected vs needs-eyeball:** explicitly separate true bugs from expected behaviour (auth-gate 302s, needs-params 400s, not-configured envelopes) and from low-confidence leads. **Crying wolf destroys the skill's value.**
- **Fix sketch:** one line on the likely fix and the file:line if you can trace it.

Group the report: **Critical / High / Medium / Low**, then a separate **Expected (not bugs)** appendix so the reader trusts you did the triage.
