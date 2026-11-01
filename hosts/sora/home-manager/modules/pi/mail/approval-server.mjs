import { createServer } from 'node:http';
import { createHash, createHmac, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { canonical, closed, digest, Store, text } from './core.mjs';
import { dashboardScript, pageSizes, renderDashboard, renderLogin, states } from './approval-ui.mjs';

const derive = promisify(scrypt);
const random = () => randomBytes(32).toString('base64url');
const hash = value => createHash('sha256').update(value).digest('hex');
export function equal(a, b) { const x = Buffer.from(a); const y = Buffer.from(b); return x.length === y.length && timingSafeEqual(x, y); }
export async function passwordHash(password) {
  const salt = randomBytes(32).toString('hex');
  const key = await derive(password, salt, 64);
  return `scrypt:${salt}:${key.toString('hex')}`;
}
export function validatePasswordHash(value) {
  if (!/^scrypt:[a-f0-9]{64}:[a-f0-9]{128}$/.test(value)) throw new Error('invalid_password_hash');
  return value;
}
export function validateProposal(value) {
  closed(value, ['digest', 'binding']);
  if (!/^[a-f0-9]{64}$/.test(value.digest) || digest(value.binding) !== value.digest) throw new Error('binding_mismatch');
  const b = closed(value.binding, ['version', 'requestId', 'mailbox', 'source', 'provider', 'scope', 'cwd', 'phase', 'operation', 'requestPreview']);
  if (b.version !== 3 || !/^[a-f0-9]{64}$/.test(b.requestId) || !/^[a-f0-9]{64}$/.test(b.source) || !['tool', 'send', 'investigate'].includes(b.phase)) throw new Error('invalid_binding');
  for (const key of ['mailbox', 'provider', 'scope', 'cwd']) text(b[key], 4096, 1);
  closed(b.requestPreview, ['from', 'subject', 'body']);
  text(b.requestPreview.from, 254, 1); text(b.requestPreview.subject, 512); text(b.requestPreview.body, 8192);
  if (Buffer.byteLength(canonical(b)) > 98304) throw new Error('binding_too_large');
  if (b.phase === 'send') {
    const op = closed(b.operation, ['sender', 'recipient', 'subject', 'body', 'bodyDigest']);
    for (const k of ['sender', 'recipient']) text(op[k], 254, 1);
    text(op.subject, 512, 1); text(op.body, 16384, 1);
    if (digest(op.body) !== op.bodyDigest) throw new Error('body_digest_mismatch');
  }
  return value;
}
export const signDecision = (value, token) => createHmac('sha256', token).update(canonical(value)).digest('hex');
export function dashboardQuery(target) {
  text(target, 2048, 1);
  const match = /^\/(?:page\/([0-9]{1,6}))?(?:\?([^#]*))?$/.exec(target);
  if (!match || /[\x00-\x20\x7f]/.test(target)) throw new Error('invalid_dashboard_path');
  const params = new URLSearchParams(match[2] ?? '');
  const keys = [...params.keys()];
  if (new Set(keys).size !== keys.length || keys.some(key => !['q', 'size', 'status'].includes(key))) throw new Error('invalid_filters');
  const rawQuery = text(params.get('q') ?? '', 256);
  const q = rawQuery.trim();
  const size = params.get('size') ?? '32', status = params.get('status') ?? 'all';
  if (!pageSizes.map(String).includes(size) || !['all', ...states].includes(status) || /[\x00-\x1f\x7f]/.test(rawQuery) || q.split(/\s+/).length > 16) throw new Error('invalid_filters');
  return { index: Number(match[1] ?? 0), size: Number(size), q, status };
}
const fold = value => value.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
export function fuzzyScore(query, document) {
  if (!query) return 1;
  const source = fold(document), terms = fold(query).trim().split(/\s+/);
  let words, score = 0;
  for (const term of terms) {
    if (source.includes(term)) { score += 1000; continue; }
    words ??= source.split(/[\s"{}\[\],]+/u);
    let best = 0;
    for (const word of words) {
      if (word.length < term.length || word.length > 4096) continue;
      let cursor = 0, first = -1, end = -1;
      for (const char of term) {
        end = word.indexOf(char, cursor);
        if (end < 0) break;
        if (first < 0) first = end;
        cursor = end + char.length;
      }
      const span = end - first + 1;
      if (end >= 0 && span <= Math.max(12, term.length * 3)) best = Math.max(best, 500 - (span - term.length) * 10);
    }
    if (!best) return 0;
    score += best;
  }
  return score;
}
async function body(req) {
  const type = req.headers['content-type'];
  if (!['application/json', 'application/x-www-form-urlencoded'].includes(type)) throw new Error('unsupported_content_type');
  if (req.headers['transfer-encoding'] || !/^\d{1,6}$/.test(req.headers['content-length'] ?? '') || Number(req.headers['content-length']) > 131072) throw new Error('body_limit');
  const chunks = []; let size = 0;
  for await (const chunk of req) { size += chunk.length; if (size > 131072) throw new Error('body_limit'); chunks.push(chunk); }
  const raw = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks));
  if (type === 'application/json') return JSON.parse(raw);
  const entries = [...new URLSearchParams(raw)];
  if (new Set(entries.map(([k]) => k)).size !== entries.length) throw new Error('duplicate_fields');
  return Object.fromEntries(entries);
}
export function createApprovalServer({ directory, apiToken, ownerHash, port = 8765, now = Date.now, proposalTTL = 16 * 60000 }) {
  text(apiToken, 256, 32); validatePasswordHash(ownerHash);
  if (!Number.isSafeInteger(proposalTTL) || proposalTTL < 1 || proposalTTL > 16 * 60000) throw new Error('invalid_ttl');
  const store = new Store(directory); const db = store.db;
  db.exec(`CREATE TABLE IF NOT EXISTS approval_proposals(id TEXT PRIMARY KEY,binding TEXT NOT NULL,state TEXT NOT NULL,expires INTEGER NOT NULL,grant TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS approval_sessions(id TEXT PRIMARY KEY,csrf TEXT NOT NULL,owner INTEGER NOT NULL,expires INTEGER NOT NULL);`);
  db.function('approval_score', { deterministic: true }, (query, id, binding) => fuzzyScore(query, `${id} ${binding}`));
  let host = `127.0.0.1:${port}`; let attemptStart = 0; let attempts = 0; let authenticating = false;
  const csrf = token => createHmac('sha256', apiToken).update(`csrf:${token}`).digest('hex');
  // Password rotation invalidates existing sessions without changing the runner API token.
  const sessionId = token => hash(`${ownerHash}:${token}`);
  function session(req) {
    const cookie = req.headers.cookie ?? '';
    if (cookie.length > 4096) return null;
    const matches = cookie.split(';').map(part => part.trim()).filter(part => part.startsWith('mail_session='));
    if (matches.length !== 1 || !/^mail_session=[A-Za-z0-9_-]{43}$/.test(matches[0])) return null;
    const token = matches[0].slice(13);
    const row = db.prepare('SELECT * FROM approval_sessions WHERE id=? AND expires>?').get(sessionId(token), now());
    return row ? { ...row, token } : null;
  }
  function newSession(res, owner) {
    db.prepare('DELETE FROM approval_sessions WHERE expires<=?').run(now());
    if (db.prepare('SELECT COUNT(*) AS n FROM approval_sessions').get().n >= 512) throw new Error('session_limit');
    const token = random(); const anti = csrf(token);
    db.prepare('INSERT INTO approval_sessions VALUES(?,?,?,?)').run(sessionId(token), hash(anti), owner ? 1 : 0, now() + (owner ? 8 * 3600000 : 600000));
    res.setHeader('Set-Cookie', `mail_session=${token}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${owner ? 28800 : 600}`);
    return anti;
  }
  function getProposal(id) {
    if (!/^[a-f0-9]{64}$/.test(id)) throw new Error('invalid_proposal');
    db.prepare("UPDATE approval_proposals SET state='expired' WHERE id=? AND state IN ('pending','approved') AND expires<=?").run(id, now());
    const row = db.prepare('SELECT * FROM approval_proposals WHERE id=?').get(id);
    if (!row) throw new Error('unknown_proposal');
    return row;
  }
  const server = createServer({ maxHeaderSize: 8192, requestTimeout: 10000, headersTimeout: 5000, keepAliveTimeout: 1000 }, async (req, res) => {
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
    res.setHeader('X-Frame-Options', 'DENY'); res.setHeader('X-Content-Type-Options', 'nosniff'); res.setHeader('Cache-Control', 'no-store'); res.setHeader('Referrer-Policy', 'same-origin');
    const send = (code, value, html = false) => { res.writeHead(code, { 'Content-Type': html ? 'text/html; charset=utf-8' : 'application/json' }); res.end(html ? value : canonical(value)); };
    try {
      const names = req.rawHeaders.filter((_, i) => i % 2 === 0).map(s => s.toLowerCase());
      const path = req.url.split('?')[0];
      const dashboard = path === '/' || /^\/page\/[0-9]{1,6}$/.test(path);
      if (['host', 'origin', 'authorization', 'content-length', 'cookie'].some(k => names.filter(n => n === k).length > 1) || ![host, `localhost:${server.address().port}`].includes(req.headers.host) || !req.url.startsWith('/') || (req.url.includes('?') && !(req.method === 'GET' && dashboard))) return send(403, { error: 'request_rejected' });
      if (!['GET', 'POST'].includes(req.method)) return send(405, { error: 'method_rejected' });
      const api = req.url.startsWith('/api/');
      if (api) {
        if (req.headers.origin || !equal(req.headers.authorization ?? '', `Bearer ${apiToken}`)) return send(401, { error: 'unauthorized' });
        if (req.method === 'POST' && req.url === '/api/v1/proposals') {
          const value = validateProposal(await body(req));
          db.prepare("UPDATE approval_proposals SET state='expired' WHERE state IN ('pending','approved') AND expires<=?").run(now());
          const existing = db.prepare('SELECT binding FROM approval_proposals WHERE id=?').get(value.digest);
          if (!existing && db.prepare("SELECT COUNT(*) AS n FROM approval_proposals WHERE state IN ('pending','approved')").get().n >= 512) return send(429, { error: 'pending_limit' });
          if (existing && existing.binding !== canonical(value.binding)) throw new Error('immutable_mismatch');
          db.prepare("INSERT OR IGNORE INTO approval_proposals VALUES(?,?,'pending',?,?)").run(value.digest, canonical(value.binding), now() + proposalTTL, random());
          return send(200, { id: value.digest });
        }
        const match = /^\/api\/v1\/proposals\/([a-f0-9]{64})\/(decision|consume)$/.exec(req.url);
        if (match) {
          const row = getProposal(match[1]);
          if (req.method === 'GET' && match[2] === 'decision') {
            const decision = { status: row.state, digest: row.id, binding: JSON.parse(row.binding), grantId: row.state === 'approved' ? row.grant : null, expiresAt: row.expires };
            return send(200, { decision, signature: signDecision(decision, apiToken) });
          }
          if (req.method === 'POST' && match[2] === 'consume') {
            const value = closed(await body(req), ['digest', 'binding', 'grantId']);
            const valid = value.digest === row.id && canonical(value.binding) === row.binding && typeof value.grantId === 'string' && equal(value.grantId, row.grant);
            const consumed = valid && db.prepare("UPDATE approval_proposals SET state='consumed' WHERE id=? AND state='approved' AND expires>?").run(row.id, now()).changes === 1;
            return send(200, { consumed: Boolean(consumed) });
          }
        }
        return send(404, { error: 'not_found' });
      }
      if (req.method === 'GET' && req.url === '/healthz') return send(200, { status: 'ok' });
      const current = session(req);
      if (req.method === 'GET' && req.url === '/dashboard.js') {
        if (!current?.owner) return send(401, { error: 'owner_required' });
        res.writeHead(200, { 'Content-Type': 'text/javascript; charset=utf-8' });
        return res.end(dashboardScript);
      }
      if (req.method === 'GET' && req.url === '/login') {
        if (current?.owner) { res.writeHead(303, { Location: '/' }); return res.end(); }
        if (current) db.prepare('DELETE FROM approval_sessions WHERE id=?').run(current.id);
        const anti = newSession(res, false);
        return send(200, renderLogin(anti), true);
      }
      if (req.method === 'POST') {
        if (req.headers.origin !== `http://${req.headers.host}` || !current) return send(403, { error: 'csrf_rejected' });
        const value = await body(req);
        if (typeof value.csrf !== 'string' || !equal(hash(value.csrf), current.csrf)) return send(403, { error: 'csrf_rejected' });
        if (req.url === '/login') {
          closed(value, ['csrf', 'username', 'password']); text(value.password, 256, 1); text(value.username, 32, 1);
          if (current.owner) return send(409, { error: 'already_authenticated' });
          if (now() - attemptStart >= 60000) { attemptStart = now(); attempts = 0; }
          if (attempts++ >= 5 || authenticating) return send(429, { error: 'login_throttled' });
          authenticating = true;
          let valid;
          try { const [, salt, expected] = ownerHash.split(':'); valid = equal((await derive(value.password, salt, 64)).toString('hex'), expected) && value.username === 'lucky'; }
          finally { authenticating = false; }
          if (!valid) return send(401, { error: 'login_failed' });
          db.prepare('DELETE FROM approval_sessions WHERE id=?').run(current.id); newSession(res, true);
          res.writeHead(303, { Location: '/' }); return res.end();
        }
        if (!current.owner) return send(401, { error: 'owner_required' });
        if (req.url === '/logout') {
          closed(value, ['csrf']); db.prepare('DELETE FROM approval_sessions WHERE id=?').run(current.id);
          res.setHeader('Set-Cookie', 'mail_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0'); res.writeHead(303, { Location: '/login' }); return res.end();
        }
        if (req.url === '/decide') {
          closed(value, ['csrf', 'id', 'decision'], ['returnTo']);
          const returnTo = value.returnTo ?? '/';
          dashboardQuery(returnTo);
          if (!['approved', 'denied'].includes(value.decision)) throw new Error('invalid_decision');
          getProposal(value.id);
          const changed = db.prepare("UPDATE approval_proposals SET state=? WHERE id=? AND state='pending' AND expires>?").run(value.decision, value.id, now()).changes;
          if (!changed) return send(409, { error: 'decision_immutable' });
          res.writeHead(303, { Location: returnTo }); return res.end();
        }
      }
      if (req.method === 'GET' && dashboard) {
        if (!current?.owner) { res.writeHead(303, { Location: '/login' }); return res.end(); }
        const view = dashboardQuery(req.url);
        db.prepare("UPDATE approval_proposals SET state='expired' WHERE state IN ('pending','approved') AND expires<=?").run(now());
        const { index, size, q, status } = view;
        const counts = Object.fromEntries(db.prepare('SELECT state, COUNT(*) AS n FROM approval_proposals GROUP BY state').all().map(row => [row.state, row.n]));
        const total = db.prepare("SELECT COUNT(*) AS n FROM approval_proposals WHERE (?='all' OR state=?) AND (?='' OR approval_score(?,id,binding)>0)").get(status, status, q, q).n;
        const rows = db.prepare(`WITH ranked AS MATERIALIZED (
          SELECT id,binding,state,expires,rowid AS sequence,approval_score(?,id,binding) AS score
          FROM approval_proposals WHERE (?='all' OR state=?))
          SELECT * FROM ranked WHERE score>0 ORDER BY score DESC,sequence DESC LIMIT ? OFFSET ?`).all(q, status, status, size, index * size);
        return send(200, renderDashboard({ rows, counts, total, ...view, csrf: csrf(current.token) }), true);
      }
      return send(404, { error: 'not_found' });
    } catch { if (!res.headersSent) send(400, { error: 'invalid_request' }); else res.destroy(); }
  });
  server.maxHeadersCount = 32; server.maxRequestsPerSocket = 100; server.maxConnections = 64;
  server.on('connection', socket => socket.setTimeout(15000, () => socket.destroy()));
  return { server, store, async listen() { await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); }); host = `127.0.0.1:${server.address().port}`; return `http://${host}`; }, async close() { await new Promise(resolve => server.close(resolve)); store.close(); } };
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.length !== 5) throw new Error('usage');
    const app = createApprovalServer({ directory: process.argv[2], apiToken: readFileSync(process.argv[3], 'utf8').trim(), ownerHash: readFileSync(process.argv[4], 'utf8').trim() });
    await app.listen();
    for (const event of ['SIGINT', 'SIGTERM']) process.once(event, () => { void app.close().then(() => process.exit(0)); });
  } catch { process.stderr.write('Approval server configuration failed\n'); process.exitCode = 1; }
}
