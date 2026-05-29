# Verification — proving the resilience mechanism actually carried the load

> Injecting a fault is trivial; **proving the named mechanism survived it is the entire value.** This file is the differentiator. The governing rule, from which everything follows:
>
> ## "Didn't crash" ≠ "worked."
> A 200 under fault is not proof of resilience — it may be luck (the request dodged the fault, hit a healthy replica, or the threshold to trip the mechanism was never reached) or, worse, a *stale/wrong* fallback that looks healthy and serves lies. **Assert the mechanism's observable fingerprint, not survival.** If you can't see the fingerprint, honestly report **"survived but unattributable"** — never upgrade it to "resilient."

---

## 1. Steady state — define "normal" observably, before you break anything

Probe the target N times (≥30, more for tail) **before** injecting and capture four families. This is a hard gate: if steady state already fails tolerance, **bail out before injecting** (you can't learn from an unknown baseline).

- **Success-rate** = good / total, per error class.
- **Latency as a distribution, never a mean.** Record p50/p95/p99/**p99.9** and keep the CDF. Means hide the tail — a 50 ms-typical service can have 5% of requests 20× slower. Track p99.9 because high-percentile stability is what users actually feel. Beware **coordinated omission**: a load generator that stalls while a request hangs records the slow call once and silently drops the requests it *would* have sent, deflating the tail — correct for it (back-fill expected samples) or use a tool that does.
- **Throughput** (req/s) and separately **goodput** — the subset served without errors and fast enough to be useful. Overload keeps throughput high while goodput collapses; **only goodput proves health.**
- **Error-class mix** — baseline 2xx/4xx/5xx/timeout ratio so a shift is detectable.

**Tolerance / error-budget math.** The SLO is the target (e.g. 99% < 400 ms, 99.9% < 1 s). The **error budget** = 1 − SLO over the window = how much the experiment is *allowed* to consume. Set the experiment's pass bound to the budget: the fault window may spend budget, but the post-experiment SLI must not breach the SLO. Encode each tolerance mechanically (a range `[min,max]`, a status/regex/JSONPath expectation, or a probe returning bool) so pass/fail isn't a judgement call.

**Auto-derivation (the Opus-4.8 edge):** don't hand-wait for thresholds — *probe to derive them.* Hit the API ~30–50× to compute its real p99/success-rate, set tolerances from that, and read the dependency timeout / breaker config from code or telemetry so you know what fingerprint to expect.

---

## 2. Per-mechanism fingerprints — fired vs. got-lucky

For each mechanism: the **externally observable signal that proves it fired**, and the signal that proves it *didn't* (and the system merely survived).

### Circuit breaker
- **Fired:** a **latency cliff.** Pre-trip, failing calls are *slow* (≈ the dependency timeout — the API waits then fails). Once OPEN, the breaker rejects without calling downstream → responses become **near-instant errors**. Assert: error-latency drops by orders of magnitude at the trip point. Then **recovery**: after the cool-down, a few probe calls are admitted (half-open) and, on dependency health, latency returns to baseline (closed).
- **Got-lucky / didn't fire:** errors stay **slow** the whole window — no cliff ⇒ the breaker never tripped (often because the minimum-call-count or failure-rate threshold wasn't reached). Drive enough volume to cross the threshold, or absence-of-trip proves nothing.

### Retry + backoff + jitter
- **Fired (client side):** total latency of a succeed-after-fault call ≈ Σ(attempt + backoff), bounded, with growing gaps.
- **Fired (dependency side — the decisive measurement):** put the **counting fault-proxy** in front of the dependency and **count inbound requests per single logical client call.** Assert: count ≤ configured max attempts; inter-arrival gaps increase (backoff); gaps are **not identical across concurrent clients** (jitter present).
- **Got-lucky / dangerous — retry storm:** inbound count ≫ outbound client calls = retries amplifying, not protecting. The canonical figure: a 5-deep call stack × 3 retries/layer = **3⁵ = 243× load** on the bottom dependency. A retry budget / token-bucket should cap it; if the multiplier is unbounded, that's a finding.

### Timeout / deadline
- Inject a **black-hole** (drop, no RST). **Fired:** every response returns within the budget ceiling. **Failed:** the call hangs to the socket default (or forever). The budget should be set from the dependency tail (e.g. p99.9 for a 0.1% false-timeout rate) — observed max under black-hole should sit just above that, not at 30 s/∞.

### Fallback
- **Fired:** success under dependency-down **AND the body proves degradation** — a `degraded:true` / `source:"cache"` marker, missing optional fields, a different shape, a stale-but-flagged timestamp.
- **Got-lucky / wrong:** a 200 whose body is **indistinguishable from live but is actually stale/incorrect** — the most dangerous outcome (looks healthy, serves lies). **Never accept status alone**; assert the degraded signature. No signature ⇒ unattributable.

### Load shedding
- **Fired:** **fast 429/503 with `Retry-After`** — rejection latency ≪ accepted-request latency — and **critical paths survive while low-priority paths shed first.**
- **Got-lucky:** slow 500s/timeouts under overload, goodput collapsing = no shedding.

### Rate-limit correctness
- Assert the headers are present and honored: modern IETF form is the structured `RateLimit` field (`r`=remaining, `t`=reset delta-seconds, `q`/`w` in `RateLimit-Policy`); many services still emit the older `RateLimit-Limit`/`-Remaining`/`-Reset` — **accept both.** `remaining` decrements per request; on exhaustion a **429** with `Retry-After`; **`Retry-After` takes precedence** if both present (normative); request N+1 over quota is actually **rejected** (not served); after the window, quota **resets** and requests succeed. Caveat: a positive `remaining` is *not* a guarantee of service — assert enforcement, don't assume capacity.

### Idempotency under retry
- Replay the same `Idempotency-Key` / duplicate the POST → assert a **single effect** via a read-back or a side-effect counter (one record, one charge). A second 200 with no second side effect = pass; a second resource created = fail. For money flows, duplicate records MUST NOT occur.

### Graceful degradation
- Core endpoint returns **reduced-but-valid** — the response still validates against the contract/schema while non-critical enrichments are absent. Not a 500, not a hang.

### Bulkhead / isolation
- While dependency A's calls fail, assert endpoint B's **success-rate and latency stay within baseline tolerance.** A shared pool would let A's hung calls inflate B's p99 — movement in B's distribution = isolation failure.

### Backpressure
- Under sustained overload the API **slows or sheds rather than accepting unbounded work.** Assert latency **plateaus + rejections appear** (bounded queue) instead of latency growing without limit (unbounded-backlog signature) and a recovery time that scales with the backlog.

---

## 3. Ruling out luck — make survival attributable

Survival is evidence only when it's tied to the mechanism. Rule out the confounders every time:
- **Was the fault actually live for the whole assertion window?** Run a continuous probe through the fault and correlate timelines. A fault that wasn't active proves nothing.
- **Did the request dodge it (healthy replica, sub-fraction toxicity)?** Require the assertion across **N requests**, not one.
- **Was the trip threshold reached?** Breakers/limiters need volume — sub-threshold load that "survives" is not resilience.
- **Is the 200 a real success or a stale/wrong fallback?** Assert the body, not the status.

The discipline: assert the **fingerprint** (latency cliff / bounded inbound count + jitter / fast-reject + `Retry-After` / degraded body marker). No fingerprint → report **"survived, mechanism unattributable"** and say what proof was missing.

---

## 4. Recovery / MTTR (black-box)

Remove the fault, resume steady-state probing, and measure **MTTR = time until the SLIs re-enter tolerance.** Detect failure-to-recover, each with its own signature:
- **Breaker stuck open** — errors stay *instant* long after the dependency is healthy (the cliff persists past the cool-down).
- **Cache never re-warmed** — latency stays elevated / fallback markers persist.
- **Pool never refilled** — throughput plateaus below baseline.
Record both *that* steady state returned and *how long* it took. (A system that survives the fault but never recovers is still a finding.)

---

## 5. Telemetry-assisted confirmation (when you have logs/metrics)

Black-box first (portable, no privileged access); white-box raises confidence. Cross-check the external fingerprint against internal signals: breaker `state` gauge + `calls_total{kind="not_permitted"}` and CLOSED→OPEN→HALF_OPEN state-change logs timestamped to the observed cliff; retry counters matching the proxy's inbound count; pool-utilisation for bulkhead isolation; shed counters / goodput-vs-throughput for load shedding. **Agreement** between external timing and internal state = high-confidence pass. **Divergence** (200s but the breaker never logged OPEN) = the survival was luck — report it as such.
