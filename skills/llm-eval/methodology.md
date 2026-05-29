# Methodology — lifecycle, eval-set construction, metrics, statistics, agentic eval

> The backbone. Evals are the test suite for non-deterministic software. Read alongside `faithfulness-and-judges.md` (the trust spine) and the shipped `assets/eval-harness.mjs`.

---

## 1. The eval lifecycle

Evals are the **"unit tests of LLM apps"** — fast, cheap assertions you run on every change to stop regressions (Hamel Husain, *Your AI Product Needs Evals*). The disciplined loop:

**define task + success criteria → build a representative golden set → choose metrics → run → analyze failures → iterate → wire into CI.**

Three effort tiers (Husain): **L1** assertions on every code change; **L2** human + model-graded eval on a cadence (needs logged traces); **L3** A/B on real users (mature products). The discipline is a *virtuous cycle*: assess → debug → modify → re-measure. Every observed failure becomes three things: a debugging target, a **new test case**, and (if fine-tuning) training data — which is what stops whack-a-mole. In CI, a quality-gate % threshold blocks a deploy the way a failing unit test does. Formal harnesses: UK AISI **Inspect** (`Dataset → Solver → Scorer`), **promptfoo**, **OpenAI Evals** — but "teams that win obsess over measurement and iteration, not tooling."

## 2. Eval-set construction

A good set is **representative of the real input distribution — not cherry-picked happy paths.**

**Bottom-up ("look at your data"):** manually review production traces → write open-ended notes on undesired behaviour → cluster notes into a **failure-mode taxonomy** → count frequencies → convert each high-frequency mode into a test case. (Husain's NurtureBoss: log review found 3 issues = 60% of all problems; a date-handling bug went 33%→95% once it became a targeted test.) **Remove all friction from looking at data** — a one-click trace viewer, or the review won't happen.

**Synthetic generation** along **features × scenarios × personas**, then *verify each generated input actually triggers the intended scenario* (don't assume it did). **Stratify** by capability/difficulty so per-category scores are readable, not one aggregate.

**Avoid contamination & overfitting:** benchmark answers leak from the web into training data and inflate scores. Keep a **held-out set** you never iterate against; if the dev-set score climbs while the holdout stalls, you're goodharting the eval. **Size** for a stable signal (§4 power analysis): a few examples per scenario is fine for deterministic assertions, but judge/aggregate scores need hundreds for tight CIs. **Version** the set with the code.

## 3. Metric taxonomy — cheapest reliable check first

| Family | Examples | Use when |
|---|---|---|
| **(a) Deterministic / code** | exact match, regex, contains/not-contains, JSON-schema/SQL validity, numeric tolerance, set membership, latency, cost, **placeholder-leak / format checks** | Whenever correctness can be decided in code. Free, instant, never flaky. *Default here.* |
| **(b) Reference-based** | BLEU/ROUGE, embedding cosine-similarity | A canonical reference exists. Weak for open-ended gen (penalises valid paraphrase, rewards lexical overlap) |
| **(c) LLM-as-judge** | G-Eval pointwise; pairwise preference; reference-guided | Genuinely open-ended quality (helpfulness, tone, coherence, prose faithfulness) that code can't decide. Validate it first (`faithfulness-and-judges.md` §5) |
| **(d) Human** | expert labels | The gold standard + the calibration anchor for every judge |

**The principle:** prefer the cheapest mechanism that can decide correctness; reserve judges for what can't be checked mechanically. Prefer **binary pass/fail + a written critique** over a 1–5 Likert (Likert isn't actionable — "no one knows the difference between a 3 and a 4"). Don't collapse to one number — HELM tracks 7 metrics (accuracy, calibration, robustness, fairness, bias, toxicity, efficiency) precisely so trade-offs and non-accuracy desiderata stay visible.

## 4. Statistical rigor (the part most evals skip)

A score without an error bar is a vibe. Anthropic's rules (*A statistical approach to model evals*; *Adding Error Bars to Evals*):

1. **Report the standard error / 95% CI** (`mean ± 1.96 × SEM`). Caveat: with only a few-hundred samples the CLT can mislead — treat tiny-n CIs with suspicion.
2. **Cluster standard errors** when items are grouped (multiple questions per passage/scenario) — clustered SEs can be >3× the naïve SE; ignoring clustering manufactures false significance.
3. **Reduce within-item variance** — for stochastic/CoT outputs, **resample N times per item** and average. Temperature/sampling is a real noise source; a single run per item is not a measurement.
4. **Paired-difference analysis when comparing two models/prompts** — both answer the *identical* items, so pairing cancels item-difficulty noise. This is the correct test for **GPT-vs-Claude / Sonnet-vs-Opus-hybrid A/B**: a 1-point delta with overlapping CIs, or that doesn't clear the paired-test noise, is **noise, not a win.**
5. **Power analysis up front** — how many items to detect the effect size you care about; underpowered suites hide real regressions.

Report honestly: **score + CI + n + temperature/seed.** **pass@k** measures consistency (e.g. Pass¹ vs Pass⁴ isolates first-attempt quality from reliability).

## 5. Agentic / multi-step eval

Two axes for tool-using agents:
- **Outcome / goal-completion** — did the final state/answer satisfy the goal? (a "response-correctness alignment" metric lives here).
- **Trajectory / process** — was the **right tool called with the right args, in a sensible order**? Outcome-only increasingly measures the agent *system's* engineering rather than the model; trajectory eval diagnoses *where* it broke.

**Partial credit** for multi-step tasks (fixes sparse-reward credit-assignment). Handle **multiple valid trajectories** — assert on the *resulting state*, not one golden path. Prefer **environment/sandbox eval**: let the agent act in a sandbox, then assert on side-effects. A full agent picture combines outcome (RC-alignment) + trajectory (tool-call correctness) + deterministic guards (hallucination count, placeholder-leak, schema).

## 6. Pitfalls & anti-patterns (each with its fix)

| Anti-pattern | Fix |
|---|---|
| Eval set too small / unrepresentative | Mine production traces; cover the real distribution; power-analyse n (§2, §4) |
| Happy-path only | Add edge/adversarial cases from the failure-mode taxonomy (§2) |
| Goodharting / overfitting the eval | Keep a **held-out set** you never tune against (§2) |
| Train/eval contamination | Use fresh/private items; sanity-check for leaked benchmark answers (§2) |
| "Looks good" vibes, no rubric | Binary pass/fail + written critique + a **validated** judge (§3, trust-spine §5) |
| Single aggregate hides per-category regressions | Stratify; report per-category (§3) |
| Unversioned eval set | Version the golden set with the code — it *is* the test suite (§1) |
| Comparing models at different temperatures | Fix temperature/seed; report both; **paired-difference** test (§4) |
| Ignoring cost/latency | Track as first-class deterministic metrics (§3) |
| "The eval passed" with no CI | Always report score + CI + n; verify the delta clears noise (§4) |
| Trusting a judge's number un-validated | Measure κ vs humans first (trust-spine §5) |

The throughline: deterministic assertions on every case → judge only the genuinely subjective (and validate that judge) → never declare a model A/B win without a **paired-difference test, CI, and fixed temperature**.

---

## Sources
Hamel Husain — *Your AI Product Needs Evals* / *Field Guide* / *LLM-as-a-Judge* (hamel.dev) · G-Eval (arXiv:2303.16634) · MT-Bench / Chatbot Arena (arXiv:2306.05685) · Anthropic — *A statistical approach to model evals* + *Adding Error Bars to Evals* (arXiv:2411.00640) · Stanford HELM (arXiv:2211.09110) · UK AISI Inspect (inspect.aisi.org.uk) · data-contamination (arXiv:2410.03249) · promptfoo / OpenAI Evals docs.
