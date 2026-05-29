# Faithfulness & judges — the trust spine

> What makes an eval trustworthy: detect hallucination by decomposition, judge open-ended quality well, control the judge's biases, and **validate the judge against humans before believing its number.** Read alongside `methodology.md`.

---

## 1. Faithfulness / groundedness / hallucination — definitions + the recipe

Three distinct properties, routinely conflated:
- **Faithfulness / groundedness** — is every claim *supported by the provided context/sources*? (A grounded answer can still be wrong if the source is wrong — faithfulness only asks "did it stick to its evidence.") The right metric for RAG and tool-output summarisation.
- **Factuality** — is the claim *true in the world*, independent of any supplied context? Needs an external knowledge source (FActScore, TruthfulQA). Note inverse-scaling: bigger models can be *less* truthful on imitative falsehoods (TruthfulQA).
- **Answer-relevance** — does the response actually address the question, regardless of truth/grounding?

**The concrete agent recipe for faithfulness (claim-decomposition + per-claim verification — the most defensible method, à la FActScore/RAGAS):**
1. **Decompose** — prompt the model to rewrite the response as a numbered list of **atomic, standalone claims**: one assertion each, no pronouns (resolve coreference so each claim stands alone).
2. **Verify each claim** against the grounding context with a verdict `supported` / `not_supported` / `not_addressed`, **requiring a verbatim quote from the context** as evidence for any `supported` (forces grounding, exposes bluffing). Or use an NLI/entailment model: Prob(entail) vs Prob(contradict).
3. **Score** `faithfulness = supported / total`. **Surface every `not_supported` claim — it's a hallucination — don't average it into a pass.**
4. For **factuality** (not just grounding), repeat step 2 against an external source.

**No grounding context? Use sample-consistency (SelfCheckGPT):** if the model truly knows a fact, stochastic samples agree; hallucinated facts diverge. Sample N responses at nonzero temperature, then score each sentence of the main answer for consistency against the N samples (NLI-contradiction or an LLM "is this supported by sample k?" prompt, averaged). The cheap reproducible alternative is a purpose-trained classifier (Vectara HHEM, <0.5 = hallucination) — not an LLM judge.

## 2. RAG / grounded-gen metrics — the RAGAS quartet (run without the library)

- **Faithfulness** — decompose answer → statements; NLI-judge each "entailed by retrieved context?"; `= entailed / total`. Catches **generation hallucination**.
- **Answer relevancy** — generate N (≈3) reverse-questions *from the answer*, embed, average cosine-sim to the original question. Catches **evasive / padded / incomplete** answers. (Embedding-based, no judge.)
- **Context precision** — for each retrieved chunk in rank order, judge binary `useful?`, then average-precision@k. Order-sensitive — rewards the useful chunk ranked first. Catches **bad retrieval ranking / junk**.
- **Context recall** — decompose the *reference answer* into statements; judge each `attributable to retrieved context?`; `= attributed / total`. Catches **retriever missing needed evidence**. (Needs a reference answer.)

Precision/recall diagnose the **retriever**; faithfulness/relevancy diagnose the **generator** — together they localise a bad answer's fault.

## 3. LLM-as-judge — doing it well

Three modes:
- **Pointwise** — score one output on a scale. Cheap, scales; absolute calibration drifts.
- **Pairwise** — "A or B better?" More reliable (relative judgments are easier); prefer where you have two candidates.
- **Reference-guided** — give the judge a gold answer. Sharply cuts errors on reasoning/math where the judge alone reasons poorly.

**Build a good judge:**
- Explicit **rubric**: named criteria, a defined scale with *what each level means*, and **few-shot anchors** (one labelled example per level).
- **Chain-of-thought before the score** (the G-Eval core: derive eval steps from the criteria, reason, *then* score). G-Eval reached Spearman ~0.51 with humans on summarisation, beating BLEU/ROUGE on open-ended tasks.
- Require an **evidence quote** for the verdict; emit **structured output** (`{reasoning, evidence, verdict}`) for aggregation.
- Prefer **binary pass/fail + critique** over Likert (actionable, less score-clustering).

**Don't use a judge when a deterministic check exists** (exact match, schema, regex, numeric tolerance, set membership) — those beat a stochastic judge on cost, latency, and reproducibility.

## 4. Judge biases + controls (critical)

A judge is a model with its own biases — measure and control them:
- **Position bias** — favours the first (or last) option; verdicts can flip on ~⅓ of pairs when order swaps. **Fix:** run both orders, count only **consistent** verdicts (else tie); randomise order. *(The shipped harness does the swap for you.)*
- **Verbosity / length bias** — longer answers score higher regardless of quality. **Fix:** instruct to ignore length; control/normalise length across candidates; measure the score-vs-length slope.
- **Self-enhancement / self-preference** — a model rates its own family higher. **Fix:** judge with a **different model family** than the one under test; ensemble across families.
- **Sycophancy** — agrees with assertions/authority in the prompt. **Fix:** don't reveal which system produced an answer; strip "this is correct" framing.
- **Leniency / score-clustering** — bunches scores at 4–5. **Fix:** pairwise; probability-weighted scoring; binary rubric.
- **Formatting bias** — markdown/lists/confident tone score higher. **Fix:** strip formatting before judging, or instruct to ignore it.

## 5. Validating the eval itself — the meta-eval loop (highest leverage)

**Before any judge/metric goes into a quality gate, measure how well it agrees with human ground truth.** This is the "who evaluates the evaluator" loop and the trust spine of the whole skill.

1. Hand-label a representative subset (an existing ground-truth benchmark is exactly this asset).
2. Run the judge on it; measure **agreement with humans**: **Cohen's κ** for categorical/pass-fail (track it over time), **Spearman/Kendall** for ranked scores, plain % agreement as a sanity floor. On imbalanced data, also report **precision and recall separately** — raw agreement lies.
3. **If the judge disagrees with humans, fix the rubric/anchors and re-measure — do not ship the eval.**
4. Measure **inter-annotator agreement** among your humans too — a judge can't be more reliable than its noisy labels.

The bar (MT-Bench): a strong judge reaches **~80%+ agreement with humans — the same level humans agree with each other.** You can't beat the human–human ceiling; aim for it. **A quality-gate % computed by an unvalidated judge is theater** — say so, and refuse to report it as trustworthy until κ clears the bar.

## 6. Tooling landscape + the gap an agent closes

- **DeepEval** — "pytest for LLMs"; prebuilt G-Eval/RAGAS/hallucination metrics + CI gating.
- **promptfoo** — CLI/YAML prompt-matrix + red-team; assertion + LLM-rubric graders.
- **RAGAS** — the RAG quartet as a library.
- **Braintrust / LangSmith** — hosted eval + trace/regression tracking + human annotation.
- **OpenAI Evals** — registry-style YAML/code harness.
- **UK AISI Inspect** — rigorous solvers + scorers + datasets + Docker sandboxes for agent eval.

**What an Opus-4.8 agent does beyond these, from first principles (LLM + scripting, no SaaS):** read the app's actual prompts/traces to design *targeted* evals for *its* failure modes; decompose claims and verify faithfulness by reasoning (§1) with verbatim-quote evidence; **detect judge bias by running the swap/length/family experiments itself**; critique a rubric for ambiguous criteria + missing anchors; run the **meta-eval κ** and refuse to trust a gate from an unvalidated judge; and find the eval's own blind spots. Frameworks give you *runners and prebuilt scorers*; the agent gives you *judgment about whether the eval is valid for this app and whether to trust its number.*

---

## Sources
RAGAS docs (docs.ragas.io) · G-Eval (arXiv:2303.16634) · Zheng et al. MT-Bench/Chatbot Arena (arXiv:2306.05685) · SelfCheckGPT (arXiv:2303.08896) · FActScore (arXiv:2305.14251) · TruthfulQA (arXiv:2109.07958) · Vectara HHEM / hallucination leaderboard · judge-bias surveys (arXiv:2506.22316) · tooling comparisons (DeepEval/promptfoo/Braintrust/LangSmith/Inspect docs).
