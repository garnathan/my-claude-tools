#!/usr/bin/env node
/**
 * verify.mjs — a zero-dependency web-UI verification harness.
 *
 * Ships with the `ui-verify` skill so you can PROVE a deployed UI works —
 * not just that it loaded — without installing Playwright or any npm package.
 * It drives headless Chrome over the DevTools Protocol using only Node 22
 * built-ins (global `fetch` + global `WebSocket`), runs your content oracles,
 * captures console + network as FAIL-GATES, samples streaming growth, takes a
 * screenshot, and emits a structured per-assertion pass/fail report.
 *
 * "Deployed ≠ working": a 200 that paints clears L0 only. This asserts
 * L1 (real content), L2 (right backend call succeeded), L3 (streaming) too.
 *
 * Requires: Node >= 22 (built-in WebSocket) and a Chrome/Chromium binary.
 *
 * ── Run ──────────────────────────────────────────────────────────────────
 *   node verify.mjs --url https://app.example.com [--config verify.json] \
 *        [--chrome "/path/to/chrome"] [--port 9222] [--out report.json] \
 *        [--screenshot shot.png] [--quorum 1] [--timeout 20000]
 *   # exit 0 = VERIFIED, 1 = BROKEN (an assertion failed), 2 = UNVERIFIED/usage
 *
 * ── Config (verify.json — every field optional) ───────────────────────────
 *   {
 *     "api_prefix": "/api",                  // what counts as a backend call
 *     "console_fail_on_error": true,         // L1: fail on console.error / pageerror
 *     "forbid_api_errors": true,             // L2: fail on any api_prefix 4xx/5xx
 *     "expect_content": [                    // L1 oracles (ALL must hold)
 *       { "selector": "table tbody tr", "min_count": 1 },
 *       { "text": "Welcome back" },
 *       { "js": "document.title.length > 0" }
 *     ],
 *     "forbid_selectors": [                  // L1 negatives (must be ABSENT)
 *       ".error-boundary", "[data-testid=skeleton]", ".empty-state"
 *     ],
 *     "expect_api": [                        // L2: a matching 2xx response must have occurred
 *       { "url_contains": "/api/messages", "status_lt": 400 }
 *     ],
 *     "sse": { "selector": "#answer", "samples": 4, "interval_ms": 500 }  // L3 streaming
 *   }
 *
 * With NO config: asserts L0 + console fail-gate, screenshots, and reports a
 * network summary (a sane default that still beats "it returned 200").
 *
 * SAFETY: read-only — it navigates and reads. It does not submit forms or
 * mutate unless your oracle's `js` does so. Use only against targets you own
 * or are authorised to test.
 */
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

function arg(n, d) { const i = process.argv.indexOf(`--${n}`); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : d; }
const URL_ = arg('url'); const CFG = arg('config'); const PORT = Number(arg('port', 9222));
const OUT = arg('out'); const SHOT = arg('screenshot'); const QUORUM = Number(arg('quorum', 1));
const TIMEOUT = Number(arg('timeout', 20000));
if (!URL_) { console.error('usage: verify.mjs --url <url> [--config verify.json] [--screenshot shot.png] [--out report.json]'); process.exit(2); }
if (Number(process.versions.node.split('.')[0]) < 22) { console.error(`verify.mjs needs Node >= 22 (built-in WebSocket); have ${process.version}`); process.exit(2); }

const cfg = CFG ? JSON.parse(await import('node:fs').then(m => m.readFileSync(CFG, 'utf8'))) : {};
const API_PREFIX = cfg.api_prefix || '/api';
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

function findChrome() {
  const cand = [process.env.CHROME_BIN, arg('chrome'),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary',
    'google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser'].filter(Boolean);
  return cand[0] && (arg('chrome') || process.env.CHROME_BIN) ? (arg('chrome') || process.env.CHROME_BIN) : cand[0];
}

// ── launch headless Chrome + wait for the CDP endpoint ──────────────────────
const userDir = mkdtempSync(join(tmpdir(), 'uiverify-'));
const chromeBin = findChrome();
const chrome = spawn(chromeBin, [
  '--headless=new', `--remote-debugging-port=${PORT}`, `--user-data-dir=${userDir}`,
  '--no-first-run', '--no-default-browser-check', '--disable-gpu', '--disable-dev-shm-usage',
  '--hide-scrollbars', 'about:blank',
], { stdio: 'ignore' });
let chromeErr = null;
chrome.on('error', (e) => { chromeErr = e; });

async function pageWsUrl() {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    if (chromeErr) throw new Error(`chrome launch failed (${chromeBin}): ${chromeErr.message}`);
    try {
      const targets = await fetch(`http://127.0.0.1:${PORT}/json`).then(r => r.json());
      const page = targets.find(t => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page.webSocketDebuggerUrl;
    } catch { /* not up yet */ }
    await sleep(200);
  }
  throw new Error('CDP endpoint did not come up — is the Chrome binary correct? set --chrome or CHROME_BIN');
}

// ── minimal CDP client over the built-in WebSocket ──────────────────────────
function cdp(wsUrl) {
  const ws = new WebSocket(wsUrl);
  let id = 0; const pending = new Map(); const listeners = [];
  const ready = new Promise((res, rej) => { ws.addEventListener('open', () => res()); ws.addEventListener('error', (e) => rej(new Error('CDP ws error'))); });
  ws.addEventListener('message', (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id !== undefined && pending.has(m.id)) { const { resolve, reject } = pending.get(m.id); pending.delete(m.id); m.error ? reject(new Error(m.error.message)) : resolve(m.result); }
    else if (m.method) listeners.forEach(fn => fn(m.method, m.params));
  });
  return {
    ready,
    send: (method, params = {}) => new Promise((resolve, reject) => { const i = ++id; pending.set(i, { resolve, reject }); ws.send(JSON.stringify({ id: i, method, params })); }),
    on: (fn) => listeners.push(fn),
    close: () => { try { ws.close(); } catch { /* */ } },
  };
}

// ── verification run ────────────────────────────────────────────────────────
async function runOnce() {
  const checks = []; // {level, name, ok, detail}
  const add = (level, name, ok, detail) => checks.push({ level, name, ok, detail });
  const consoleErrors = []; const requests = new Map(); const responses = [];
  let client, loaded = false;
  try {
    client = cdp(await pageWsUrl());
    await client.ready;
    client.on((method, p) => {
      if (method === 'Runtime.consoleAPICalled' && p.type === 'error') consoleErrors.push((p.args || []).map(a => a.value ?? a.description ?? '').join(' '));
      else if (method === 'Runtime.exceptionThrown') consoleErrors.push(p.exceptionDetails?.exception?.description || p.exceptionDetails?.text || 'exception');
      // JS errors only. `source:"network"` Log entries are resource-load failures
      // (favicon, images, the wrong-endpoint XHR) — those are the NETWORK gate's
      // job (forbid_api_errors / expect_api), not a console-error signal.
      else if (method === 'Log.entryAdded' && p.entry?.level === 'error' && p.entry?.source !== 'network') consoleErrors.push(`[${p.entry.source}] ${p.entry.text}`);
      else if (method === 'Network.requestWillBeSent') requests.set(p.requestId, { url: p.request.url, method: p.request.method });
      else if (method === 'Network.responseReceived') { const rq = requests.get(p.requestId) || {}; responses.push({ url: p.response.url || rq.url, status: p.response.status, method: rq.method }); }
      else if (method === 'Page.loadEventFired') loaded = true;
    });
    await client.send('Page.enable'); await client.send('Runtime.enable');
    await client.send('Network.enable'); await client.send('Log.enable');

    // L0 — navigate + load
    const nav = await client.send('Page.navigate', { url: URL_ });
    if (nav.errorText) { add('L0', `navigate ${URL_}`, false, nav.errorText); throw new Error('navigation failed: ' + nav.errorText); }
    const navDeadline = Date.now() + TIMEOUT;
    while (!loaded && Date.now() < navDeadline) await sleep(100);
    add('L0', 'page load fired', loaded, loaded ? 'load event received' : `no load event within ${TIMEOUT}ms`);

    const evalJs = async (expr) => {
      const r = await client.send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
      if (r.exceptionDetails) return { err: r.exceptionDetails.exception?.description || r.exceptionDetails.text };
      return { value: r.result?.value };
    };
    const pollTrue = async (expr, ms) => {
      const dl = Date.now() + ms; let last;
      while (Date.now() < dl) { const { value, err } = await evalJs(expr); last = err || value; if (value === true) return { ok: true }; await sleep(250); }
      return { ok: false, detail: `not true within ${ms}ms (last: ${JSON.stringify(last)})` };
    };

    // L1 — content oracles
    for (const o of (cfg.expect_content || [])) {
      let expr, name;
      if (o.selector) { const n = o.min_count ?? 1; expr = `document.querySelectorAll(${JSON.stringify(o.selector)}).length >= ${n}`; name = `≥${n} of ${o.selector}`; }
      else if (o.text != null) { expr = `(document.body?.innerText||'').includes(${JSON.stringify(o.text)})`; name = `text "${o.text}"`; }
      else if (o.js) { expr = `!!(${o.js})`; name = `js ${o.js}`; }
      else continue;
      const r = await pollTrue(expr, TIMEOUT);
      add('L1', `content: ${name}`, r.ok, r.detail || 'present');
    }
    // L1 — negative oracles (must be absent)
    for (const sel of (cfg.forbid_selectors || [])) {
      const { value } = await evalJs(`document.querySelectorAll(${JSON.stringify(sel)}).length`);
      add('L1', `absent: ${sel}`, value === 0, value === 0 ? 'absent' : `present (${value})`);
    }
    // L1 — console fail-gate
    if (cfg.console_fail_on_error !== false) add('L1', 'no console errors', consoleErrors.length === 0, consoleErrors.length ? consoleErrors.slice(0, 5) : 'clean');

    // L2 — network
    const apiResp = responses.filter(r => (r.url || '').includes(API_PREFIX));
    if (cfg.forbid_api_errors !== false) { const bad = apiResp.filter(r => r.status >= 400); add('L2', `no ${API_PREFIX} 4xx/5xx`, bad.length === 0, bad.length ? bad.map(b => `${b.status} ${b.url}`).slice(0, 8) : `${apiResp.length} api call(s) all <400`); }
    for (const e of (cfg.expect_api || [])) {
      const lt = e.status_lt ?? 400;
      const hit = responses.find(r => (r.url || '').includes(e.url_contains) && r.status < lt && r.status > 0);
      add('L2', `api ${e.url_contains} <${lt}`, !!hit, hit ? `${hit.status} ${hit.url}` : `no matching response <${lt} (saw: ${responses.filter(r => (r.url || '').includes(e.url_contains)).map(r => r.status).join(',') || 'none'})`);
    }

    // L3 — SSE / streaming growth
    if (cfg.sse?.selector) {
      const n = cfg.sse.samples ?? 4, iv = cfg.sse.interval_ms ?? 500; const lens = [];
      for (let i = 0; i < n; i++) { const { value } = await evalJs(`(document.querySelector(${JSON.stringify(cfg.sse.selector)})?.innerText||'').length`); lens.push(value ?? 0); await sleep(iv); }
      const nonDecreasing = lens.every((v, i) => i === 0 || v >= lens[i - 1]);
      const grew = lens[lens.length - 1] > lens[0];
      const distinct = new Set(lens).size >= 2; // arrived in steps, not all-at-once at the end
      add('L3', `stream grows in ${cfg.sse.selector}`, nonDecreasing && grew && distinct, `lengths=[${lens.join(',')}] nonDecreasing=${nonDecreasing} grew=${grew} incremental=${distinct}`);
    }

    // screenshot evidence
    if (SHOT) { const r = await client.send('Page.captureScreenshot', { format: 'png' }); writeFileSync(SHOT, Buffer.from(r.data, 'base64')); }
  } finally { client?.close(); }
  return { checks, consoleErrors, network: responses };
}

// ── quorum + report ─────────────────────────────────────────────────────────
try {
  const runs = [];
  for (let i = 0; i < Math.max(1, QUORUM); i++) runs.push(await runOnce());
  const last = runs[runs.length - 1];
  // a check passes the quorum only if it passed in EVERY run
  const merged = last.checks.map((c, idx) => ({ ...c, ok: runs.every(r => r.checks[idx]?.ok) }));
  const failed = merged.filter(c => !c.ok);
  const verdict = failed.length === 0 ? 'VERIFIED' : 'BROKEN';
  const report = { url: URL_, quorum: QUORUM, verdict, checks: merged, failed_count: failed.length, console_errors: last.consoleErrors, network_summary: { total: last.network.length, api: last.network.filter(r => (r.url || '').includes(API_PREFIX)).length }, screenshot: SHOT || null };
  if (OUT) writeFileSync(OUT, JSON.stringify(report, null, 2));

  const tick = (b) => b ? '✓' : '✗';
  console.log(`\nui-verify — ${URL_}  (quorum ${QUORUM})`);
  for (const c of merged) console.log(`  ${tick(c.ok)} [${c.level}] ${c.name}${c.ok ? '' : '  → ' + JSON.stringify(c.detail)}`);
  console.log(`  network: ${report.network_summary.total} req (${report.network_summary.api} ${API_PREFIX}) · console errors: ${last.consoleErrors.length}`);
  console.log(`VERDICT: ${verdict}${failed.length ? ` (${failed.length} failed assertion(s))` : ''}`);
  rmSync(userDir, { recursive: true, force: true }); try { chrome.kill(); } catch { /* */ }
  process.exit(verdict === 'VERIFIED' ? 0 : 1);
} catch (e) {
  console.error(`UNVERIFIED: ${e.message}`);
  rmSync(userDir, { recursive: true, force: true }); try { chrome.kill(); } catch { /* */ }
  process.exit(2);
}
