---
name: llm-eval
description: Build and run a RIGOROUS evaluation of any LLM app or agent — and make the eval itself trustworthy. Define success criteria, mine real traces into a representative eval set, score deterministically-first (reserve judges for what code can't decide), VALIDATE every judge against human labels (Cohen's κ) before trusting its number, detect hallucination by claim-decomposition, control judge bias (position/verbosity/self-preference), and report with statistical honesty (paired-difference, confidence intervals, fixed temperature — never claim a model/prompt win on noise). Ships a zero-dependency eval harness (deterministic + judge scorers, position-swap, CI gate) — no promptfoo/DeepEval/RAGAS/Braintrust needed. Application-agnostic. Use to build an eval suite, gate a release, compare two models/prompts, measure hallucination/faithfulness, or audit an existing benchmark for flaws.
allowed-tools: Read, Write, Bash, Agent, WebFetch, WebSearch
---

# LLM-Eval — rigorous evals, and a trustworthy eval

You evaluate LLM systems the way the best eval engineers do — and you hold the eval itself to the same bar you hold the model. The throughline: **cheapest reliable check first, judge only what code can't decide, human-align every judge before trusting it, and never declare a comparison win on noise.** The two failure modes you exist to prevent are (1) shipping a regression because the eval was too shallow/unrepresentative, and (2) trusting a number from an unvalidated judge or a noisy A/B — "the eval passed" is theater without coverage, a validated judge, and a confidence interval.

This skill is **application-agnostic** and works from first principles — just an LLM + scripting, no SaaS eval backend — because it **ships its own zero-dependency harness** (`assets/eval-harness.mjs`).

## Read your knowledge base FIRST (both + the asset)

In this skill's directory:
1. **`methodology.md`** — the eval lifecycle, eval-set construction (mine traces → failure-mode taxonomy), the metric taxonomy (deterministic / reference / judge / human), **statistical rigor** (paired-difference, CIs, sample size, variance), agentic/multi-step eval (outcome vs trajectory), and the pitfalls table. *The backbone.*
2. **`faithfulness-and-judges.md`** — the **claim-decomposition faithfulness recipe**, the RAGAS quartet (runnable without the library), LLM-as-judge done well (rubric + CoT-before-score + evidence), the **judge-bias controls** (position/verbosity/self-preference), and the **meta-eval loop** (validate the judge against human labels with κ). *The trust spine.*
3. **`assets/eval-harness.mjs`** — the shipped runner. Read its header for the case format + scorer API. It runs deterministic + judge scorers over a JSONL eval set, does position-swap for pairwise, and reports per-category pass-rates with confidence intervals + a CI gate. There is nothing better worth downloading.

## The standard (litmus test)

Point this at a benchmark a team already trusts and either **find a flaw in the EVAL ITSELF** (an unvalidated judge whose κ-vs-human is low; a rubric with position/verbosity bias; train/eval contamination; a model-A/B "win" that's inside the noise; a whole failure mode the set never covers; a single aggregate score hiding a per-category regression) **or build a more rigorous eval that catches a regression the existing one misses.** A pass/fail count with no CI and no validated judge is not an eval. **Opus 4.8 sustains more reasoning per run than any eval framework — use it:** read the app's actual prompts/traces to design *targeted* evals, decompose claims to verify faithfulness, run the bias experiments yourself, and judge honestly whether a number can be trusted.

## Phase 0 — Recon: the app, its task, its current eval

Understand what you're evaluating: the task + what "good" means (read prompts, system messages, tool definitions, the success definition). Map the **surface** (single-turn? multi-step agent with tools? RAG/grounded? streaming?). Find the **existing eval/bench** if any (how it scores, what it claims) and — highest-yield — **read real traces/outputs** to see how it actually behaves and fails. Confirm **authorisation + cost**: evals cost tokens; on a paid API set a budget, fix temperature/seed, and never run destructive actions as part of an eval.

## Phase 1 — Define success criteria & build the eval set

Write the explicit, testable success criteria first (per `methodology.md` §1–2). Build a **representative** eval set, not happy-paths: mine production traces, cluster failures into a **failure-mode taxonomy**, and turn each mode into a test case. Cover edge/adversarial inputs. Stratify by capability/difficulty so per-category signal is readable. Keep a **held-out set** you never tune against (anti-goodhart). Note any **contamination** risk (benchmark answers leaked into training). Version the set with the code — it *is* the test suite.

## Phase 2 — Choose metrics: deterministic-first

Per `methodology.md` §3, assign the **cheapest mechanism that can decide correctness** to each criterion: deterministic checks (exact/regex/JSON-schema/contains/latency/cost/**placeholder-leak**) wherever possible; reference-based only where a canonical answer exists; **LLM-as-judge only for genuinely open-ended quality** (helpfulness, tone, coherence, faithfulness of prose). Record which metric covers which criterion in a coverage ledger — no criterion left unscored.

## Phase 3 — Build judges AND validate them (the meta-eval)

For each judge metric, build a real rubric (named criteria, defined scale, few-shot anchors), require **chain-of-thought before the score** and an **evidence quote**, emit structured output (`faithfulness-and-judges.md` §3). Then — before trusting any judge in a gate — run the **meta-eval** (§5): on a human-labeled subset, measure the judge's **agreement with humans (Cohen's κ / correlation)**. If it disagrees, **fix the rubric, don't ship the eval.** A quality-gate % from an unvalidated judge is theater. Also run the **bias checks** (§4): position-swap (count only consistent verdicts), verbosity slope, and use a **different model family** as judge than the one under test (self-preference).

## Phase 4 — Run with statistical rigor

Run the harness (`assets/eval-harness.mjs`) over the set. For stochastic/CoT outputs, **resample N times per case** (temperature is real noise). Report every score with a **confidence interval + n + temperature/seed** (`methodology.md` §4). When comparing two models/prompts, use a **paired-difference test** (same items both sides) and **only call a win if it clears the noise** — overlapping CIs / a 1-point delta on a paired test is *not* a win. Cluster standard errors when items are grouped. Track cost + latency as first-class metrics.

## Phase 5 — Faithfulness / hallucination pass

For any grounded or tool-using output, run the **claim-decomposition recipe** (`faithfulness-and-judges.md` §1): decompose the response into atomic, standalone claims → verify each against the grounding context with a `supported / not_supported / not_addressed` verdict requiring a **verbatim quote** for "supported" → `faithfulness = supported / total`, and **surface every `not_supported` claim** (a hallucination), don't average it away. Where there's no grounding context, use sample-consistency (SelfCheckGPT-style). For RAG, add the relevant RAGAS-quartet metrics (§2).

## Phase 6 — Self-critique against the pitfalls

Run the pitfalls table (`methodology.md` §6) as a checklist over your own eval: set too small/unrepresentative? happy-path only? overfitting the dev set? contamination? vibes with no rubric? single aggregate hiding a per-category regression? unvalidated judge? different temperatures across arms? no CIs? For each, fix or name it as a stated limitation. Find the eval's **blind spots** — cases it can't see, oracle gaps, where a deterministic check should replace a judge.

## Phase 7 — Report + CI gate

Report: per-category pass-rates **with CIs + n + temperature**, the judges used **and their κ-vs-human** (so the reader can trust the numbers), any A/B verdict **with the paired test result and whether it cleared noise**, the faithfulness score **with the surfaced hallucinations**, and cost/latency. Emit a **runnable CI gate** (the harness config + threshold) that fails the build on a regression and is versioned with the code. End with the **litmus scorecard**: what the eval now covers, which judges are validated (κ) vs not-yet-trusted, and either the flaw you found in the prior eval or the regression your eval newly catches.

## Rules
- **Read both knowledge files + the harness header first.**
- **Deterministic-first.** Use a judge only for what code can't decide. A cheap exact-match beats a flaky judge.
- **Validate the judge before you trust it.** Measure κ vs human labels; if low, fix the rubric — don't ship the eval. An unvalidated judge's score is worthless.
- **Control judge bias.** Swap positions (count only consistent verdicts), watch verbosity, judge with a different model family than the one under test.
- **Never claim a win on noise.** Paired-difference + CI + fixed temperature + n. Overlapping CIs = no win. Report score ± CI, always.
- **Faithfulness by decomposition.** Verify atomic claims against the source with verbatim-quote evidence; surface every hallucination.
- **Represent the real distribution; keep a holdout.** No happy-path-only sets; don't tune against the holdout; version the set.
- **Coverage is a claim you back.** Every success criterion mapped to a metric; per-category scores, not one hiding number.
- **Authorised + budgeted.** Fix temperature/seed; cap token spend; no destructive actions inside an eval; carry guardrails into sub-agents.
