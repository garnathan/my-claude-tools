# Fault catalog — what to inject, how, and which mechanism it tests

> The faults a chaos experiment injects against an **API/service**, organised so each maps to a real-world failure *and* to the resilience mechanism it exercises. Read this with `verification.md` (how to prove the mechanism held) and `method-and-safety.md` (the experiment loop + blast-radius rules).
>
> **Generic + portable principle:** the most powerful, dependency-free way to fault an API is a **fault-injecting proxy** on the wire — you need only a listen socket and a scripting runtime, no Kubernetes/cloud/agent access. This skill ships one (`assets/fault-proxy.mjs`, zero deps) so you never need Toxiproxy/Gremlin/FIS. Use the platform tools (below) when you already have them; fall back to the shipped proxy everywhere else.

---

## Where to inject (targeting) — the decision that matters most

An API is a node in a dependency graph. Pick the **edge**, and the edge picks the mechanism you're testing:

| Inject at edge | Tests (the API's…) |
|---|---|
| **client → API** (proxy in front of the API) | *published contract*: clean error codes, server-side request timeout, no caller hang, graceful 429 + `Retry-After` under load |
| **API → another API** | outbound timeout, retry+backoff, **circuit breaker**, fallback/degraded response |
| **API → database** | query timeout, **connection-pool** sizing/exhaustion, read-replica failover |
| **API → cache** | cache-miss / stampede handling, origin fallback, stale-while-error |
| **API → queue/broker** | producer backpressure, at-least-once retry, dead-letter, ordering |
| **API → auth / IdP** | token-refresh retry, auth-cache TTL, **fail-open vs fail-closed** (a security-critical choice) |
| **API → object store** | multipart resume, large-payload timeout, partial-read handling |

**The dependency edge is where most value lives** — it exercises the API's *internal* resilience (breakers, retries, fallbacks, pools). The client edge validates the *contract you publish*. Enumerate dependencies first (read config/env/code for hostnames, DSNs, SDK clients; or observe egress), then put an injector at each edge, one at a time.

Fault → mechanism quick map: **latency/slow** → timeouts + pool limits; **5xx/abort** → retry + breaker + fallback; **reset/refuse** → reconnect + breaker; **partition/black-hole** → timeout-not-hang + breaker trip; **429** → backoff + quota handling; **truncate/corrupt** → validation + idempotent retry; **DNS/TLS fail** → connection-error handling + alerting.

---

## The fault catalog (fault → real-world event → how to inject)

### A. Latency & slowness — tests timeouts, pools, breakers, backpressure
- **Fixed + jittered latency** → slow/overloaded dependency, GC pause. Inject: proxy `latency` toxic (`latency` ms ± `jitter`); `tc qdisc add dev eth0 root netem delay 200ms 40ms 25%`; Envoy/Istio `delay.fixedDelay` + `percentage`; shipped proxy `latencyMs`+`jitterMs`.
- **Slow-loris / slow body** (drip bytes) → byte-by-byte stalls that exhaust server read threads. Inject: proxy `bandwidth rate=1` + `slicer`; shipped proxy `bandwidthKBps` low + `sliceBytes`.
- **Bandwidth throttle** → congested link, large-payload timeout. Inject: proxy `bandwidth`; `tc netem rate 256kbit`.

### B. Errors & malformed responses — tests retry, breaker, fallback, validation
- **5xx / 502 / 503 / 429 / 418** → backend error, proxy failure, overload, teapot. Inject: proxy rewrites response status (`abortStatus`+`errorPct`); Envoy/Istio `abort.httpStatus`; stub.
- **Malformed / truncated body, wrong content-type, wrong content-length** → broken serializer, half-written response, content-negotiation bug. Inject: proxy `truncateAt` bytes (kills conn mid-body); WireMock `MALFORMED_RESPONSE_CHUNK` / `RANDOM_DATA_THEN_CLOSE`.

### C. Connection-level — tests reconnect, breaker, timeout-not-hang
- **RST / connection reset mid-flight** → peer crash, LB drop. Inject: proxy `resetPeer`; WireMock `CONNECTION_RESET_BY_PEER`; `iptables --reject-with tcp-reset`.
- **Connection refused** → service down, wrong port. Inject: kill upstream; point at a dead port.
- **Black-hole / hang (timeout)** → silent network drop, the nastiest. Inject: proxy `blackhole` (accept, never respond, close after T); `iptables -j DROP`; Toxiproxy `timeout 0`.
- **TLS handshake failure / expired cert** → cert-rotation miss, MITM box. Inject: terminate TLS at the proxy with a bad/expired cert.
- **DNS failure (NXDOMAIN / slow resolver)** → DNS outage. Inject: point the client's resolver / `/etc/hosts` at a dead IP.

### D. Partition — tests split-brain, quorum, timeout, breaker trip
- **Full partition** (drop all traffic to a dependency) → network island. Inject: proxy `down`; `iptables -j DROP` on the dep CIDR.
- **Asymmetric / one-way partition** (requests leave, responses never return) → the cruellest real partition; exposes hang-not-timeout bugs. Inject: drop a single direction with `netem`/`iptables`.

### E. Data integrity — tests checksum/validation, idempotent retry
- **Bit-flip / corruption / duplicate / reorder** → flaky NIC, checksum bug, idempotency failure. Inject: `tc netem corrupt 0.1% duplicate 1% reorder 25% 50%`; proxy byte-mangle.

### F. Dependency-side behaviours — tests retry/cursor/partial-result handling
- **Downstream API 5xx / slow / 429** → cascading upstream failure. Inject: proxy in front of the *downstream* rewrites status / adds latency.
- **Paginated endpoint stalls mid-cursor** (serve pages 1–2, hang/500 on page 3) → partial-result / resume handling. Inject: stateful stub or proxy counter that faults the Nth call.
- **Rate-limit / quota exhaustion** → you've hit the provider's cap. Inject: proxy returns `429` + `Retry-After` after N reqs/window.

### G. Resource & infrastructure (when you have host/orchestrator access)
- **CPU / memory / disk / FD / IO exhaustion** → noisy neighbour, leak, runaway logs. Inject: `stress-ng`, Chaos Mesh `StressChaos`, Gremlin resource attacks.
- **Instance / replica / AZ / region kill, container OOM, process kill** → host loss, zone outage. Inject: Chaos Monkey, AWS FIS, Chaos Mesh `PodChaos`, `kill -9`.
- **Clock skew, disk full, reboot** → NTP drift, log fill. Inject: Gremlin "time travel", FIS, `date`-set in a sandbox.

> These (G) need privileged access and are platform-specific. The portable A–F set (HTTP/network layer, proxy-injectable) is where the generic skill spends most of its time.

---

## Injection methods, ranked by portability

1. **Shipped fault proxy** (`assets/fault-proxy.mjs`, zero-dep Node) — works anywhere you have a runtime + network. Reverse-proxies to an upstream; arms toxics live via a control endpoint; **counts inbound requests per logical call** (the signal for retry-storm detection); supports auto-disarm. Use this by default. See its header for the full toxic list + control API.
2. **App-level fault hook** (when you can touch the target) — feature-flagged injection à la Netflix FIT: a middleware reads `X-Chaos: latency=500,abort=503,p=0.1` (or an env toggle / `/chaos/arm` endpoint) and self-injects latency/error for a fraction of requests by header. Pros: header-scoped blast radius, reaches deep internal calls a proxy can't see, no TLS re-termination. Cons: needs code/deploy access. If the target lacks a hook and you own it, adding a tiny per-request one is often the cleanest path to deep, precisely-scoped chaos.
3. **Platform fault injectors** — Toxiproxy (toxics: latency/down/bandwidth/slicer/timeout/slow_close/reset_peer/limit_data), Envoy/Istio fault filter (`delay`/`abort` + `percentage`), Chaos Mesh / LitmusChaos (K8s CRDs), AWS FIS (managed + stop-conditions), `tc`/`netem` (kernel-level network faults), WireMock/Hoverfly (stub faults). Use when already present — but the skill never *requires* them.

## Load + fault, together (non-negotiable for APIs)

Chaos-at-rest misses the failures that only appear under concurrency: **connection-pool exhaustion, retry storms, thundering herd, cascading failure through a shared pool.** Latency injection only reveals pool starvation once enough concurrent requests pile up behind the slow dependency. So drive representative load (`k6` / `vegeta` / `hey`, or a simple concurrent-request loop) **while** a fault is armed — on **read-only / idempotent** endpoints unless you have explicit authorisation for writes, with a capped concurrency, scoped to a test tenant/key. Stateful sequences matter too: fault the **Nth** call in a multi-step flow (the proxy's request counter does this) to reproduce "step 3 fails after payment authorised."
