# Method, anti-patterns, and the distributed localization decision tree

> The discipline. Read alongside `assets/boundary-tracer.mjs`. Sources: Agans *Debugging: The 9 Indispensable Rules*; the scientific method / hypothetico-deductive loop; Google SRE *Effective Troubleshooting* (Triage → Examine → Diagnose → Test/Treat → Cure); Zeller *Why Programs Fail* / delta debugging; distributed-tracing + correlation-ID practice.

---

## The loop = Agans' 9 Rules × scientific method × SRE Triage→Cure

| Step | Agans rule(s) | What it means in practice |
|---|---|---|
| **Reproduce** | #2 Make it fail | A reliable repro is the foundation. *Stimulate, don't simulate* — exercise the real path. Intermittent? find the uncontrolled condition; record everything to capture the signature. (Prod bleeding → SRE **Triage**/mitigate first; mitigation ≠ root cause.) |
| **Observe / instrument** | #3 Quit thinking and look · #1 Understand the system | Get *data* before theories. SRE **Examine**: metrics (what/where) + logs (why) + traces (which request). You can't localize a fault in a topology you can't draw. |
| **Hypothesize** | #1 | One **falsifiable** claim. Occam: hoofbeats → horses, but allow multiple causes. |
| **Test, one thing** | #5 Change one thing at a time · #7 Check the plug | Derive a prediction it *must* satisfy; change exactly one variable. Prefer the probe that **rules out the most** (SRE: mutually-exclusive experiments). Question assumptions: *is it even deployed / pointed at the right host?* |
| **Bisect** | #4 Divide and conquer | Halve at a boundary; find which side carries the fault; recurse (Zeller delta-debugging / `git bisect`). |
| **Confirm** | (the gate) | Toggle the bug on/off by the suspected cause (§ Confirmed-vs-Suspected). |
| **Fix + prove** | #9 If you didn't fix it, it ain't fixed | It's *really* fixed AND it's *your* fix: remove → returns, re-apply → gone. |
| **Regress + record** | #6 Keep an audit trail · #8 Get a fresh view | Permanent guard (probe/test/alarm); publish negative results; rubber-duck when stuck. |

---

## Anti-patterns (each tagged with the rule it breaks)

- **Fix before root cause found** — breaks #3 + #9. Symptom-patching; the fault resurfaces elsewhere.
- **Shotgun / random-change debugging** — breaks #3 + #5. Throwing changes hoping one sticks.
- **Changing multiple variables at once** — breaks #5. Even a working fix is then unattributable.
- **"It works now" with no causal story** — breaks #9. Could be a flaky intermittent that self-cleared, or your unrelated restart.
- **Trusting assumptions over instrumentation** — breaks #3 + #7.
- **No audit trail** — breaks #6. You re-walk dead ends and lose the intermittent's signature.
- **Correlation mistaken for causation** — SRE's named pitfall. The deploy at 14:00 + errors at 14:02 is a clue, not proof.
- **Tunnel vision** — breaks #8. Get a fresh view / rubber-duck.

---

## Distributed-systems localization decision tree (the differentiator)

Symptom in hand, walk the branches; each has a **cheap probe** that confirms/denies *before you touch code*. Always **compare a working path vs the failing path** (differential) and **trace every hop** with an ID that survives each boundary — correlation/trace IDs that die at an HTTP-client/queue boundary are the #1 reason a request can't be followed end-to-end. The shipped tracer automates the DNS→TCP→TLS→HTTP→auth→content probes and the differential.

| Branch | Symptom shape | Cheap probe (confirm/deny) |
|---|---|---|
| **App logic** | Same input → wrong output, deterministic, single replica | Replay the input against ONE instance directly (bypass the LB); read its span/logs. |
| **DNS** | Intermittent / "host not found" / resolves to wrong IP | Resolve the name **from inside the container**; compare to the expected LB/backend IP. |
| **Routing / security-list / peering / NAT** | TCP connect hangs or times out, no RST | TCP-connect probe `host:port` from the source subnet; check route table, security list, LPG/DRG attachment, NAT egress allowlist. *Reachable from A, not B ⇒ path, not app.* |
| **TLS** | Connects, then handshake / cert error | Handshake probe; inspect chain, SNI, `valid_to`. |
| **IAM / auth** | 401/403; or worked-then-stopped; or works in region A not B | Round-trip the **same** credential out-of-band. New policy? IAM propagation to replicated regions takes **30–45 min** — wait, don't iterate syntax. Token `exp`? Missing policy ⇒ deny in the audit log. |
| **Eventual consistency** | Read-after-write misses; succeeds on retry | Re-read after a delay; if it then succeeds ⇒ replication/propagation lag, not data loss. (Object-store list lag, IAM, DNS TTL.) |
| **Config drift / stale deploy** | "Code is right but behavior is old"; env var not taking effect | Probe the running container's **actual** env/version endpoint; diff deployed image tag vs intended. *Rendered config regenerated from a source-of-truth file — editing the rendered file alone is silently reverted.* |
| **Shared-resource clobber** | A sibling/peer deploy breaks an unrelated target | Diff the shared resource (security list, bucket policy, DNS, LB backend set) **before vs after** the peer's change — did target B's deploy strip target A's rules? |

**Order:** boundary-trace to the *first hop where the trace goes dark or a value goes wrong*, then bisect within that hop. Metrics say *when/where*, traces say *which request*, logs say *why* — combine all three.

---

## Confirmed vs Suspected — the gate, and the ledger

A hypothesis is **Confirmed** only when you can **turn the bug ON and OFF by toggling the suspected cause** (re-introduce → failure returns; remove → gone). Anything on correlation, timing, or "the change looks related" is **Suspected** — and you must name the toggle test still owed. Never write "root cause: X" when the ledger shows only correlation.

**Hypothesis ledger** (the audit trail, structured):

| Claim | Prediction (must hold if true) | Test (one variable) | Result | Verdict |
|---|---|---|---|---|
| IAM policy not yet propagated to replica region | Same creds succeed in home region, fail in replica | Run identical creds against both regions | home 200 / replica 403 | **Suspected** (consistent, not yet toggled) |
| …same | After ~45 min, replica succeeds with no code change | Wait, re-run | replica now 200 | **Confirmed** (toggled by a time-only variable) |

---

## The shipped boundary tracer (`assets/boundary-tracer.mjs`)

Zero-dependency Node (pure `node:` builtins — `dns`, `net`, `tls`, `https`/`http`, `perf_hooks`). It automates "quit thinking and look": probe each boundary for a target, in order, recording every layer (short-circuiting detail on the first hard failure but still reporting the rest), and — given a **working** target alongside the **failing** one — emit a **differential** that exonerates whole branches of the tree above in a single run.

Per hop it measures: **DNS** (resolve → addresses + ms), **TCP** (connect → connected | refused/RST | timeout + ms), **TLS** (handshake → authorized?, cert subject/issuer/`valid_to`, SNI), **HTTP** (method+path → status, latency, key headers, body bytes), **auth round-trip** (same call with vs without the credential → status delta, isolating authz from transport), and a caller-supplied **content oracle** (a predicate over the body — so a 200 with wrong content still fails). Output: a structured evidence timeline with `first_failure` + `verdict`, and a `DIFF working↔failing` line naming the first divergent layer. Identical lower layers *exonerate* the network-path branches; the first divergence points the bisection.

---

## Sources
Agans, *Debugging: The 9 Indispensable Rules* (dwheeler.com essay; Embedded Artistry summary). Google SRE Book — *Effective Troubleshooting* + *Monitoring Distributed Systems*; *Debugging Incidents in Google's Distributed Systems* (ACM Queue). Zeller, *Why Programs Fail* / delta debugging (ACM Queue; Wikipedia). Correlation/trace-ID practice (distributed tracing literature).
