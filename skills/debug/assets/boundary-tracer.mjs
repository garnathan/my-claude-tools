#!/usr/bin/env node
/**
 * boundary-tracer.mjs — a zero-dependency distributed-failure localizer.
 *
 * Ships with the `debug` skill to automate "quit thinking and look" (Agans #3):
 * it probes a target's boundaries IN ORDER — DNS resolve → TCP connect → TLS
 * handshake → HTTP status+latency → auth round-trip → a content oracle — and,
 * given a WORKING target alongside the FAILING one, emits a DIFFERENTIAL that
 * exonerates whole branches of the localization decision tree in a single run
 * and points the bisection at the first divergent layer.
 *
 * Pure `node:` builtins (dns, net, tls, http/https, perf_hooks). No npm install.
 *
 * ── Run ──────────────────────────────────────────────────────────────────
 *   # localize a single failing endpoint
 *   node boundary-tracer.mjs --target https://failing.example.com/api/health
 *
 *   # DIFFERENTIAL — the payoff: compare failing vs a known-good sibling
 *   node boundary-tracer.mjs --target https://oac.example.com/api/health \
 *        --vs https://aidp.example.com/api/health \
 *        --auth "Authorization: Bearer $TOKEN" \
 *        --oracle '/"version"/'  --out trace.json
 *
 * ── Flags ──────────────────────────────────────────────────────────────────
 *   --target  <url>   the failing endpoint (required)
 *   --vs      <url>   a working endpoint for the differential (optional)
 *   --auth    "H: v"  header sent on the WITH-auth HTTP probe; also drives the
 *                     auth round-trip (compares status WITH vs WITHOUT it)
 *   --oracle  <s>     content oracle over the body: substring, or /regex/.
 *                     A 200 whose body fails the oracle is a CONTENT failure.
 *   --timeout <ms>    per-probe timeout (default 8000)
 *   --out     <file>  also write the structured JSON report
 *
 * SAFETY: GET-only, read-only. Probes you own or are authorised to test.
 */
import dns from 'node:dns/promises';
import net from 'node:net';
import tls from 'node:tls';
import http from 'node:http';
import https from 'node:https';
import { performance } from 'node:perf_hooks';
import { writeFileSync } from 'node:fs';

function arg(n, d) { const i = process.argv.indexOf(`--${n}`); return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : d; }
const TARGET = arg('target'); const VS = arg('vs'); const AUTH = arg('auth');
const ORACLE = arg('oracle'); const TIMEOUT = Number(arg('timeout', 8000)); const OUT = arg('out');
if (!TARGET) { console.error('usage: boundary-tracer.mjs --target <url> [--vs <working-url>] [--auth "Authorization: Bearer .."] [--oracle <substr|/regex/>]'); process.exit(2); }

const ms = (t) => Math.round(performance.now() - t);
const oraclePred = (() => {
  if (!ORACLE) return null;
  if (ORACLE.length > 1 && ORACLE.startsWith('/') && ORACLE.endsWith('/')) { const re = new RegExp(ORACLE.slice(1, -1)); return (b) => re.test(b); }
  return (b) => b.includes(ORACLE);
})();
const authHeader = AUTH ? { name: AUTH.slice(0, AUTH.indexOf(':')).trim(), value: AUTH.slice(AUTH.indexOf(':') + 1).trim() } : null;

function probeTcp(host, port) {
  return new Promise((resolve) => {
    const t = performance.now(); const s = net.connect({ host, port });
    let done = false; const fin = (ok, detail) => { if (done) return; done = true; try { s.destroy(); } catch { /* */ } resolve({ layer: 'tcp', ok, ms: ms(t), port, detail }); };
    s.setTimeout(TIMEOUT);
    s.on('connect', () => fin(true, 'connected'));
    s.on('timeout', () => fin(false, 'timeout (no SYN-ACK — likely routing/security-list/NAT, not a closed port)'));
    s.on('error', (e) => fin(false, e.code === 'ECONNREFUSED' ? 'refused/RST (port closed / nothing listening)' : `${e.code || e.message}`));
  });
}
function probeTls(host, port) {
  return new Promise((resolve) => {
    const t = performance.now(); const s = tls.connect({ host, port, servername: host, timeout: TIMEOUT });
    let done = false; const fin = (ok, detail, extra = {}) => { if (done) return; done = true; try { s.destroy(); } catch { /* */ } resolve({ layer: 'tls', ok, ms: ms(t), detail, ...extra }); };
    s.on('secureConnect', () => { const c = s.getPeerCertificate() || {}; fin(s.authorized, s.authorized ? 'handshake ok' : (s.authorizationError || 'unauthorized'), { cert_subject: c.subject?.CN, cert_issuer: c.issuer?.CN, valid_to: c.valid_to }); });
    s.on('timeout', () => fin(false, 'tls handshake timeout'));
    s.on('error', (e) => fin(false, `${e.code || e.message}`));
  });
}
function probeHttp(u, withAuth) {
  return new Promise((resolve) => {
    const t = performance.now(); const lib = u.protocol === 'https:' ? https : http;
    const headers = {}; if (withAuth && authHeader) headers[authHeader.name] = authHeader.value;
    const req = lib.request({ protocol: u.protocol, hostname: u.hostname, port: u.port || (u.protocol === 'https:' ? 443 : 80), path: u.pathname + u.search, method: 'GET', headers, timeout: TIMEOUT },
      (res) => { let body = ''; let bytes = 0; res.on('data', (c) => { bytes += c.length; if (body.length < 65536) body += c.toString('utf8'); }); res.on('end', () => resolve({ status: res.statusCode, ms: ms(t), bytes, headers: { 'content-type': res.headers['content-type'], server: res.headers.server }, body })); });
    req.on('timeout', () => { req.destroy(); resolve({ status: 0, ms: ms(t), detail: 'http timeout (connected but no response — slow upstream/app hang)' }); });
    req.on('error', (e) => resolve({ status: 0, ms: ms(t), detail: `${e.code || e.message}` }));
    req.end();
  });
}

async function trace(label, urlStr) {
  const u = new URL(urlStr); const port = Number(u.port) || (u.protocol === 'https:' ? 443 : 80);
  const hops = [];

  // DNS
  let addrs = [];
  { const t = performance.now(); try { addrs = (await dns.lookup(u.hostname, { all: true })).map(a => a.address); hops.push({ layer: 'dns', ok: addrs.length > 0, ms: ms(t), detail: addrs.join(',') }); } catch (e) { hops.push({ layer: 'dns', ok: false, ms: ms(t), detail: `${e.code || e.message}` }); } }
  if (!hops[0].ok) return finish(label, urlStr, hops);

  // TCP
  hops.push(await probeTcp(u.hostname, port));
  if (!hops.at(-1).ok) return finish(label, urlStr, hops);

  // TLS (https only)
  if (u.protocol === 'https:') { hops.push(await probeTls(u.hostname, port)); if (!hops.at(-1).ok) return finish(label, urlStr, hops); }

  // HTTP (with auth if provided)
  const h = await probeHttp(u, true);
  const httpOk = h.status > 0 && h.status < 400;
  hops.push({ layer: 'http', ok: httpOk, ms: h.ms, status: h.status, bytes: h.bytes, detail: h.detail || `${h.status}${h.headers?.['content-type'] ? ' ' + h.headers['content-type'] : ''}` });

  // Auth round-trip (compare WITH vs WITHOUT the credential)
  if (authHeader && h.status > 0) {
    const noAuth = await probeHttp(u, false);
    const delta = noAuth.status !== h.status;
    hops.push({ layer: 'auth', ok: !(h.status === 401 || h.status === 403), with_status: h.status, without_status: noAuth.status, detail: (h.status === 401 || h.status === 403) ? `${h.status} even WITH credential ⇒ authz deny / wrong principal` : (delta ? `with=${h.status} without=${noAuth.status} ⇒ auth is enforced and your credential is accepted` : `status unchanged by credential (${h.status}) ⇒ endpoint not auth-gated`) });
  }

  // Content oracle (a 200 with the wrong body still fails)
  if (oraclePred && h.status > 0) { const pass = oraclePred(h.body || ''); hops.push({ layer: 'content', ok: pass, detail: pass ? 'oracle matched' : `oracle did NOT match (status ${h.status}, ${h.bytes}B) ⇒ reachable but wrong/empty content` }); }

  return finish(label, urlStr, hops);
}

function verdictFor(hops) {
  const f = hops.find(h => !h.ok);
  if (!f) return 'all boundaries healthy';
  switch (f.layer) {
    case 'dns': return 'DNS / name resolution';
    case 'tcp': return f.detail?.includes('refused') ? 'app/listener down (port closed)' : 'network path — routing / security-list / peering / NAT';
    case 'tls': return 'TLS / certificate';
    case 'http': return f.status === 401 || f.status === 403 ? 'auth / IAM (authz deny)' : f.status >= 500 ? 'app / upstream (5xx)' : f.status === 0 ? 'app hang / no response' : `HTTP ${f.status}`;
    case 'auth': return 'auth / IAM (authz deny)';
    case 'content': return 'content — reachable but wrong/empty body (config / scoping / stale deploy)';
    default: return f.layer;
  }
}
function finish(label, urlStr, hops) { return { label, url: urlStr, hops, first_failure: hops.find(h => !h.ok)?.layer || null, verdict: verdictFor(hops) }; }

// ── run ──────────────────────────────────────────────────────────────────
const failing = await trace('failing', TARGET);
const working = VS ? await trace('working', VS) : null;

const tick = (b) => b ? '✓' : '✗';
const printTrace = (tr) => {
  console.log(`\n[${tr.label}] ${tr.url}`);
  for (const h of tr.hops) console.log(`  ${tick(h.ok)} ${h.layer.padEnd(7)} ${(h.ms != null ? h.ms + 'ms' : '').padStart(7)}  ${h.detail || (h.status != null ? 'status ' + h.status : '')}`);
  console.log(`  → first_failure: ${tr.first_failure || 'none'}   verdict: ${tr.verdict}`);
};
printTrace(failing);
let diff = null;
if (working) {
  printTrace(working);
  const layers = ['dns', 'tcp', 'tls', 'http', 'auth', 'content'];
  let firstDiverge = null; const same = [];
  for (const L of layers) {
    const a = failing.hops.find(h => h.layer === L); const b = working.hops.find(h => h.layer === L);
    if (!a || !b) continue;
    const equal = a.ok === b.ok && (L !== 'http' || a.status === b.status);
    if (equal) same.push(L); else { firstDiverge = L; break; }
  }
  diff = { identical_through: same, first_divergence: firstDiverge };
  console.log(`\nDIFF working↔failing:`);
  console.log(`  identical: [${same.join(', ') || 'none'}]  ⇒ NOT a ${same.includes('tcp') && same.includes('tls') ? 'network-path/TLS' : same.join('/')} bug`);
  console.log(`  first divergence: ${firstDiverge || 'none (paths identical — look at app state/data, not the path)'}`);
}

if (OUT) writeFileSync(OUT, JSON.stringify({ failing, working, diff }, null, 2));
process.exit(failing.first_failure ? 1 : 0);
