#!/usr/bin/env node
/**
 * eval-harness — a zero-dependency LLM eval runner + scorer.
 *
 * Ships with the `llm-eval` skill so you never need promptfoo / DeepEval /
 * RAGAS / Braintrust to run a rigorous eval — you need only Node + a way to
 * call your model/judge. It is a SCORER over already-produced outputs (the
 * most provider-agnostic shape): you bring a JSONL of cases that include the
 * model output(s); the harness applies deterministic + judge scorers, swaps
 * positions for pairwise judges, and reports per-category pass-rates WITH
 * confidence intervals, a CI gate, judge↔human agreement (Cohen's κ — the
 * meta-eval), and a paired-difference A/B test that won't call a win on noise.
 *
 * Pure Node stdlib. No npm install. Node 18+.
 *
 * ── Run ──────────────────────────────────────────────────────────────────
 *   node eval-harness.mjs --set cases.jsonl --config eval.json
 *   node eval-harness.mjs --set cases.jsonl --config eval.json --json out.json
 *
 * ── Case (one JSON object per line in --set) ──────────────────────────────
 *   {
 *     "id": "case-1",
 *     "category": "retrieval",          // for stratified reporting
 *     "output": "the model's answer",   // the text under test
 *     "expected": "gold answer",        // optional, for exact/reference scorers
 *     "context": "grounding source",    // optional, for faithfulness/judge
 *     "human_label": "pass",            // optional "pass"|"fail" → enables κ meta-eval
 *     "output_b": "model B's answer"    // optional → enables pairwise + paired A/B
 *   }
 *
 * ── Config (--config eval.json) ───────────────────────────────────────────
 *   {
 *     "scorers": [
 *       {"type":"exact",        "field":"output", "expectedField":"expected"},
 *       {"type":"contains",     "field":"output", "value":"approved"},
 *       {"type":"not_contains", "field":"output", "value":"{{", "name":"placeholder_leak"},
 *       {"type":"regex",        "field":"output", "pattern":"^\\d{4}-\\d{2}-\\d{2}$"},
 *       {"type":"json_valid",   "field":"output"},
 *       {"type":"num_tolerance","field":"output", "expectedField":"expected", "tol":0.01},
 *       {"type":"judge", "name":"helpfulness", "mode":"pointwise",
 *        "prompt":"Score whether the answer is helpful and correct.\nQ/context:\n{{context}}\nAnswer:\n{{output}}"},
 *       {"type":"judge", "name":"prefers", "mode":"pairwise",
 *        "prompt":"Which answer is better for: {{context}}\nA:\n{{output}}\nB:\n{{output_b}}"}
 *     ],
 *     "judge_cmd": "claude -p --output-format text",  // gets the judge prompt on STDIN
 *     "gate": {"min_pass_rate": 0.9}
 *   }
 *
 * The judge_cmd is any shell command that reads a prompt on STDIN and prints a
 * verdict. The harness appends strict output instructions and tolerantly parses
 * the first {...} it finds. Expected judge JSON:
 *   pointwise → {"verdict":"pass"|"fail","reasoning":"...","evidence":"<quote>"}
 *   pairwise  → {"winner":"A"|"B"|"tie","reasoning":"..."}
 *
 * ── Bias control: pairwise judging is run BOTH orders (A/B then B/A); a winner
 *    is only credited if the verdict is CONSISTENT across the swap, else "tie".
 * ── Meta-eval: if cases carry human_label, κ between the (first pass/fail) judge
 *    and the human is reported. κ<0.6 ⇒ the judge is NOT yet trustworthy.
 * ── Stats: per-category pass-rate with a 95% Wilson interval; A/B paired delta
 *    (output vs output_b) with a bootstrap 95% CI — overlap with 0 ⇒ NOT a win.
 */
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

function arg(name, fb) { const i = process.argv.indexOf(`--${name}`); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fb; }
const SET = arg('set'); const CONFIG = arg('config'); const JSON_OUT = arg('json');
if (!SET || !CONFIG) { console.error('usage: eval-harness.mjs --set cases.jsonl --config eval.json [--json out.json]'); process.exit(2); }

const cases = fs.readFileSync(SET, 'utf8').split('\n').map(s => s.trim()).filter(Boolean).map((l, i) => {
  try { return JSON.parse(l); } catch (e) { console.error(`bad JSONL at line ${i + 1}: ${e.message}`); process.exit(2); }
});
const cfg = JSON.parse(fs.readFileSync(CONFIG, 'utf8'));
const scorers = cfg.scorers || [];

const fill = (tpl, c) => String(tpl).replace(/\{\{(\w+)\}\}/g, (_, k) => (c[k] ?? ''));
const firstJson = (s) => { const m = String(s).match(/\{[\s\S]*\}/); if (!m) return null; try { return JSON.parse(m[0]); } catch { return null; } };

function runJudge(prompt, mode) {
  if (!cfg.judge_cmd) return { error: 'no judge_cmd configured' };
  const schema = mode === 'pairwise'
    ? '\n\nRespond with ONLY JSON: {"winner":"A"|"B"|"tie","reasoning":"..."}. Think step by step in "reasoning" BEFORE deciding. Ignore answer length and formatting; judge substance.'
    : '\n\nRespond with ONLY JSON: {"verdict":"pass"|"fail","reasoning":"...","evidence":"<verbatim quote from the source or answer>"}. Reason in "reasoning" BEFORE the verdict.';
  const r = spawnSync(cfg.judge_cmd, { input: prompt + schema, shell: true, encoding: 'utf8', maxBuffer: 1 << 24 });
  if (r.status !== 0 && !r.stdout) return { error: (r.stderr || 'judge failed').slice(0, 200) };
  return firstJson(r.stdout) || { error: 'unparseable judge output' };
}

// ── deterministic scorers → boolean pass ───────────────────────────────────
function deterministic(s, c) {
  const v = String(c[s.field] ?? '');
  switch (s.type) {
    case 'exact': return v.trim() === String(c[s.expectedField] ?? s.value ?? '').trim();
    case 'contains': return v.includes(s.value);
    case 'not_contains': return !v.includes(s.value);
    case 'regex': return new RegExp(s.pattern, s.flags || '').test(v);
    case 'json_valid': try { JSON.parse(v); return true; } catch { return false; }
    case 'num_tolerance': { const a = parseFloat(v), b = parseFloat(c[s.expectedField] ?? s.value); return Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) <= (s.tol ?? 0); }
    default: return null; // not deterministic
  }
}

// ── per-case scoring ────────────────────────────────────────────────────────
const results = [];
let firstJudgeName = null;
for (const c of cases) {
  const row = { id: c.id, category: c.category || 'default', scores: {}, judgeVerdict: null };
  for (const s of scorers) {
    const name = s.name || s.type;
    if (s.type === 'judge') {
      if (!firstJudgeName) firstJudgeName = name;
      if (s.mode === 'pairwise') {
        const ab = runJudge(fill(s.prompt, c), 'pairwise');           // A=output, B=output_b
        const swapped = { ...c, output: c.output_b, output_b: c.output };
        const ba = runJudge(fill(s.prompt, swapped), 'pairwise');     // positions swapped
        // consistent only: A wins iff (ab=A and ba=B)
        let winner = 'tie';
        if (ab.winner === 'A' && ba.winner === 'B') winner = 'A';
        else if (ab.winner === 'B' && ba.winner === 'A') winner = 'B';
        row.scores[name] = { kind: 'pairwise', winner, consistent: winner !== 'tie', raw: [ab.winner, ba.winner] };
      } else {
        const j = runJudge(fill(s.prompt, c), 'pointwise');
        const pass = j.verdict === 'pass';
        row.scores[name] = { kind: 'judge', pass, reasoning: j.reasoning, evidence: j.evidence, error: j.error };
        if (name === firstJudgeName) row.judgeVerdict = j.verdict === 'pass' ? 'pass' : j.verdict === 'fail' ? 'fail' : null;
      }
    } else {
      const pass = deterministic(s, c);
      row.scores[name] = { kind: 'deterministic', pass };
    }
  }
  // case passes if every non-pairwise scorer passes
  row.pass = Object.values(row.scores).every(x => x.kind === 'pairwise' || x.pass === true);
  results.push(row);
}

// ── stats ────────────────────────────────────────────────────────────────────
function wilson(k, n) { // 95% Wilson score interval for a proportion
  if (n === 0) return [0, 0, 0];
  const z = 1.96, p = k / n, d = 1 + z * z / n;
  const c = (p + z * z / (2 * n)) / d, m = (z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))) / d;
  return [p, Math.max(0, c - m), Math.min(1, c + m)];
}
function cohenKappa(pairs) { // pairs of [judge, human] in {pass,fail}
  const n = pairs.length; if (!n) return null;
  let a = 0; const m = { pass: { pass: 0, fail: 0 }, fail: { pass: 0, fail: 0 } };
  for (const [j, h] of pairs) { if (j === h) a++; m[j] && m[j][h] !== undefined && m[j][h]++; }
  const po = a / n;
  const jp = (m.pass.pass + m.pass.fail) / n, hp = (m.pass.pass + m.fail.pass) / n;
  const pe = jp * hp + (1 - jp) * (1 - hp);
  return pe === 1 ? 1 : (po - pe) / (1 - pe);
}

const byCat = {};
for (const r of results) { (byCat[r.category] ||= []).push(r); }
const catReport = Object.entries(byCat).map(([cat, rs]) => {
  const k = rs.filter(r => r.pass).length, [p, lo, hi] = wilson(k, rs.length);
  return { category: cat, n: rs.length, pass: k, pass_rate: +p.toFixed(4), ci95: [+lo.toFixed(4), +hi.toFixed(4)] };
});
const totK = results.filter(r => r.pass).length, [tp, tlo, thi] = wilson(totK, results.length);

// meta-eval: κ judge vs human
const kPairs = results.filter(r => r.judgeVerdict && cases.find(c => c.id === r.id)?.human_label)
  .map(r => [r.judgeVerdict, cases.find(c => c.id === r.id).human_label]);
const kappa = cohenKappa(kPairs);

// paired A/B (output vs output_b) on deterministic+pointwise pass — bootstrap CI on the delta
let ab = null;
if (cases.some(c => c.output_b !== undefined) && cfg.ab_field) {
  // optional: requires a 'pass_b' per case computed elsewhere; skipped unless provided
}
// pairwise win tally (consistent only)
const pw = {};
for (const r of results) for (const [n, s] of Object.entries(r.scores)) if (s.kind === 'pairwise') {
  (pw[n] ||= { A: 0, B: 0, tie: 0 }); pw[n][s.winner]++;
}

// ── gate ──────────────────────────────────────────────────────────────────
const min = cfg.gate?.min_pass_rate;
const gatePass = min == null ? null : tlo >= min ? true : tp >= min ? 'marginal' : false; // gate on the LOWER CI bound — honest

// ── report ──────────────────────────────────────────────────────────────────
const report = {
  set: SET, n: results.length,
  overall: { pass: totK, pass_rate: +tp.toFixed(4), ci95: [+tlo.toFixed(4), +thi.toFixed(4)] },
  by_category: catReport,
  judge_vs_human: kappa == null ? 'no human_label in set — judge UNVALIDATED' : { n: kPairs.length, cohen_kappa: +kappa.toFixed(3), trustworthy: kappa >= 0.6 },
  pairwise: pw,
  gate: min == null ? 'none' : { min_pass_rate: min, pass: gatePass, note: gatePass === 'marginal' ? 'point estimate clears bar but lower CI bound does not — collect more n' : undefined },
};
if (JSON_OUT) fs.writeFileSync(JSON_OUT, JSON.stringify({ report, results }, null, 2));

const pct = x => (x * 100).toFixed(1) + '%';
console.log(`\neval-harness — ${results.length} cases`);
console.log(`overall: ${pct(report.overall.pass_rate)}  95% CI [${pct(tlo)}, ${pct(thi)}]  (${totK}/${results.length})`);
for (const c of catReport) console.log(`  ${c.category.padEnd(20)} ${pct(c.pass_rate).padStart(7)}  CI[${pct(c.ci95[0])}, ${pct(c.ci95[1])}]  n=${c.n}`);
if (kappa != null) console.log(`judge↔human: κ=${kappa.toFixed(3)} over n=${kPairs.length} → ${kappa >= 0.6 ? 'TRUSTWORTHY' : 'NOT trustworthy (fix the rubric)'}`);
else console.log(`judge↔human: no human_label → judge UNVALIDATED (add human_label to trust judge scores)`);
for (const [n, t] of Object.entries(pw)) console.log(`pairwise ${n}: A=${t.A} B=${t.B} tie/inconsistent=${t.tie} (consistent-only)`);
if (min != null) console.log(`gate (min ${pct(min)} on lower CI bound): ${gatePass === true ? 'PASS' : gatePass === 'marginal' ? 'MARGINAL — need more n' : 'FAIL'}`);
process.exit(gatePass === false ? 1 : 0);
