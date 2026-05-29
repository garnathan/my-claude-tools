#!/usr/bin/env node
/**
 * fault-proxy — a zero-dependency, API-focused fault-injecting reverse proxy.
 *
 * Ships with the `chaos` skill so you never need Toxiproxy / Gremlin / FIS to
 * run a chaos experiment against an API — you need only Node + network access.
 * Put it between a client and a target API, OR between the target and one of
 * its dependencies, then arm faults live and watch the resilience mechanism
 * (or its absence) in the response behaviour.
 *
 * Pure Node stdlib (http/https). No npm install. Node 18+.
 *
 * ── Run ──────────────────────────────────────────────────────────────────
 *   node fault-proxy.mjs --listen 8080 --upstream https://api.example.com \
 *                        --control 8474
 *   # point your client (or the API's dependency config) at http://localhost:8080
 *
 * ── Control plane (on --control port) ────────────────────────────────────
 *   GET  /state             → current toxics + config
 *   GET  /stats             → request counts {total, byPath, byStatus} (retry-storm signal)
 *   POST /reset-stats       → zero the counters (call before each experiment)
 *   POST /arm   {json}       → merge toxics (below); (re)starts the auto-disarm timer
 *   POST /disarm            → clear all toxics (pass-through)
 *
 * ── Toxics (POST /arm body, all optional; default = pass-through) ─────────
 *   toxicity      0..1   fraction of requests affected            (default 1.0)
 *   latencyMs     int    delay before forwarding                  (timeouts, pools)
 *   jitterMs      int    ± random jitter on latency
 *   errorPct      0..1   fraction of (toxic) reqs answered with abortStatus, no upstream call
 *   abortStatus   int    status for errorPct / blackhole-less aborts   (default 503)
 *   resetPeer     bool   destroy the socket mid-flight (TCP RST)
 *   blackhole     bool   accept, never respond, close after timeoutMs (silent drop / hang)
 *   timeoutMs     int    how long blackhole holds before closing  (default 30000)
 *   truncateAt    int    bytes of response body to send, then kill the conn (malformed/truncated)
 *   bandwidthKBps int    throttle the downstream body to ~N KB/s   (slow body / congestion)
 *   autoDisarmSec int    SAFETY: auto-revert to pass-through after N seconds (default 300; 0 = off)
 *
 * ── Example session ──────────────────────────────────────────────────────
 *   curl -s localhost:8474/reset-stats -X POST
 *   curl -s localhost:8474/arm -X POST -d '{"errorPct":1.0,"abortStatus":503,"autoDisarmSec":120}'
 *   # ...drive load through :8080, observe the API's breaker/retry/fallback...
 *   curl -s localhost:8474/stats          # inbound count per path → retry-storm check
 *   curl -s localhost:8474/disarm -X POST # revert (or let auto-disarm fire)
 *
 * SAFETY: autoDisarmSec defaults to 300s so a forgotten experiment can't run
 * forever. Always /reset-stats before an experiment and /disarm after; verify
 * pass-through with a clean probe once disarmed.
 */
import http from 'node:http';
import https from 'node:https';
import { URL } from 'node:url';

function argOf(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const LISTEN_PORT = Number(argOf('listen', process.env.FAULT_LISTEN || 8080));
const CONTROL_PORT = Number(argOf('control', process.env.FAULT_CONTROL || 8474));
const UPSTREAM = argOf('upstream', process.env.FAULT_UPSTREAM || '');
if (!UPSTREAM) {
  console.error('fault-proxy: --upstream <url> is required (e.g. https://api.example.com)');
  process.exit(1);
}
const up = new URL(UPSTREAM);
const upClient = up.protocol === 'https:' ? https : http;

/** Live toxic state. Empty = pass-through. */
let toxics = {};
let autoDisarmTimer = null;

/** Verification counters — the retry-storm / inbound-count signal. */
const stats = { total: 0, byPath: Object.create(null), byStatus: Object.create(null) };

function clearAutoDisarm() {
  if (autoDisarmTimer) { clearTimeout(autoDisarmTimer); autoDisarmTimer = null; }
}
function arm(next) {
  toxics = { ...toxics, ...next };
  clearAutoDisarm();
  const secs = Number(toxics.autoDisarmSec ?? 300);
  if (secs > 0) {
    autoDisarmTimer = setTimeout(() => {
      toxics = {};
      console.error(`fault-proxy: auto-disarmed after ${secs}s (safety)`);
    }, secs * 1000);
    autoDisarmTimer.unref?.();
  }
}
function disarm() { toxics = {}; clearAutoDisarm(); }

const jittered = (base, jit) => Math.max(0, (base || 0) + (jit ? (Math.random() * 2 - 1) * jit : 0));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── Data proxy (faults applied here) ──────────────────────────────────────
const proxy = http.createServer(async (req, res) => {
  const path = (req.url || '/').split('?')[0];
  stats.total += 1;
  stats.byPath[path] = (stats.byPath[path] || 0) + 1;

  const t = toxics;
  const faulted = !t.toxicity || Math.random() < Number(t.toxicity); // default toxicity 1.0

  if (faulted) {
    // Blackhole: accept, never respond, close after timeoutMs (silent drop / hang).
    if (t.blackhole) {
      const hold = Number(t.timeoutMs ?? 30000);
      setTimeout(() => { try { req.socket.destroy(); } catch { /* gone */ } }, hold).unref?.();
      return;
    }
    // RST: destroy the socket mid-flight (connection reset by peer).
    if (t.resetPeer) { try { req.socket.destroy(); } catch { /* gone */ } return; }
    // Error injection: answer immediately with abortStatus, no upstream call.
    if (t.errorPct && Math.random() < Number(t.errorPct)) {
      const status = Number(t.abortStatus ?? 503);
      recordStatus(status);
      res.writeHead(status, { 'content-type': 'application/json', 'x-fault-proxy': 'abort' });
      res.end(JSON.stringify({ error: 'fault-proxy injected abort', status }));
      return;
    }
    // Latency (+jitter) before forwarding.
    if (t.latencyMs || t.jitterMs) await sleep(jittered(Number(t.latencyMs), Number(t.jitterMs)));
  }

  // Forward to upstream, streaming the response back (with optional body faults).
  const headers = { ...req.headers, host: up.host };
  const opts = {
    protocol: up.protocol, hostname: up.hostname,
    port: up.port || (up.protocol === 'https:' ? 443 : 80),
    method: req.method, path: req.url, headers,
  };
  const ureq = upClient.request(opts, (ures) => {
    recordStatus(ures.statusCode || 0);
    res.writeHead(ures.statusCode || 502, ures.headers);
    let sent = 0;
    const truncAt = faulted && t.truncateAt ? Number(t.truncateAt) : 0;
    const kbps = faulted && t.bandwidthKBps ? Number(t.bandwidthKBps) : 0;
    ures.on('data', async (chunk) => {
      if (truncAt && sent + chunk.length > truncAt) {
        try { res.write(chunk.subarray(0, Math.max(0, truncAt - sent))); } catch { /* */ }
        try { res.socket?.destroy(); } catch { /* */ } // truncate: kill mid-body
        ures.destroy();
        return;
      }
      sent += chunk.length;
      if (kbps) { ures.pause(); await sleep((chunk.length / (kbps * 1024)) * 1000); ures.resume(); }
      res.write(chunk);
    });
    ures.on('end', () => res.end());
  });
  ureq.on('error', (e) => {
    if (!res.headersSent) { res.writeHead(502, { 'x-fault-proxy': 'upstream-error' }); }
    res.end(JSON.stringify({ error: 'upstream error', detail: String(e.message || e) }));
  });
  req.pipe(ureq);
});

function recordStatus(s) {
  const k = `${Math.floor(s / 100)}xx`;
  stats.byStatus[k] = (stats.byStatus[k] || 0) + 1;
}

// ── Control plane (no faults; never proxied) ──────────────────────────────
const control = http.createServer((req, res) => {
  const send = (code, obj) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(obj, null, 2)); };
  const path = (req.url || '/').split('?')[0];
  if (req.method === 'GET' && (path === '/state' || path === '/')) return send(200, { upstream: UPSTREAM, toxics, autoDisarmActive: !!autoDisarmTimer });
  if (req.method === 'GET' && path === '/stats') return send(200, stats);
  if (req.method === 'POST' && path === '/reset-stats') { stats.total = 0; stats.byPath = Object.create(null); stats.byStatus = Object.create(null); return send(200, { ok: true }); }
  if (req.method === 'POST' && path === '/disarm') { disarm(); return send(200, { ok: true, toxics }); }
  if (req.method === 'POST' && path === '/arm') {
    let body = '';
    req.on('data', (d) => { body += d; if (body.length > 1e6) req.socket.destroy(); });
    req.on('end', () => {
      try { arm(JSON.parse(body || '{}')); send(200, { ok: true, toxics, autoDisarmActive: !!autoDisarmTimer }); }
      catch (e) { send(400, { error: 'invalid JSON', detail: String(e) }); }
    });
    return;
  }
  send(404, { error: 'unknown control route', routes: ['GET /state', 'GET /stats', 'POST /reset-stats', 'POST /arm', 'POST /disarm'] });
});

proxy.listen(LISTEN_PORT, () => console.error(`fault-proxy: proxying :${LISTEN_PORT} → ${UPSTREAM}`));
control.listen(CONTROL_PORT, () => console.error(`fault-proxy: control on :${CONTROL_PORT} (auto-disarm default 300s)`));
