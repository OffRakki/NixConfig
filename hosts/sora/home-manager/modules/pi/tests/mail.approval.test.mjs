import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { request as httpRequest } from 'node:http';
import { mkdtemp, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { Script } from 'node:vm';
import { bindingFor, canonical, digest, encodeEnvelope, normalize, reserveSend, Store } from '../mail/core.mjs';
import { createApprovalServer, passwordHash } from '../mail/approval-server.mjs';
import { createApprovalAdapter, productionCli } from '../mail/production.mjs';
import { runMail } from '../mail/runner.mjs';

const raw = () => ({ version: 1, messageId: null, from: 'sender@example.test', subject: '<script>bad</script>', body: '<img src=x onerror=bad()>', autoSubmitted: 'no', precedence: '', attachments: [] });
async function fixture(fn) {
  const directory = await mkdtemp(join(tmpdir(), 'mail-approval-test-')); const token = randomBytes(48).toString('base64url'); const password = randomBytes(32).toString('base64url');
  const ownerHash = await passwordHash(password); let clock = Date.now();
  let app = createApprovalServer({ directory: join(directory, 'site'), apiToken: token, ownerHash, port: 0, now: () => clock });
  let endpoint = await app.listen();
  const config = { mailbox: 'owner@example.test', selfAddress: 'assistant@example.test', provider: 'faux/offline', scope: 'test', cwd: directory, contextPaths: [] };
  const request = normalize(raw(), config);
  const proposal = operation => { const binding = bindingFor(request, config, 'tool', operation); return { digest: digest(binding), binding }; };
  const http = async (path, { method = 'GET', cookie, form, data, auth = false, origin, headers = {}, hostname = '127.0.0.1' } = {}) => fetch(endpoint.replace('127.0.0.1', hostname) + path, { method, redirect: 'manual', headers: { ...(cookie ? { Cookie: cookie } : {}), ...(auth ? { Authorization: `Bearer ${token}` } : {}), ...(form ? { 'Content-Type': 'application/x-www-form-urlencoded', Origin: origin ?? endpoint } : {}), ...(data ? { 'Content-Type': 'application/json' } : {}), ...headers }, body: form ? new URLSearchParams(form).toString() : data ? canonical(data) : undefined });
  async function login(hostname = '127.0.0.1', origin) {
    const pre = await http('/login', { hostname }); const html = await pre.text(); const cookie = pre.headers.get('set-cookie').split(';')[0]; const csrf = /name="csrf" value="([a-f0-9]+)"/.exec(html)[1];
    const logged = await http('/login', { method: 'POST', cookie, hostname, origin, form: { username: 'lucky', password, csrf } }); assert.equal(logged.status, 303);
    const ownerCookie = logged.headers.get('set-cookie').split(';')[0]; assert.notEqual(cookie, ownerCookie);
    const dashboard = await http('/', { cookie: ownerCookie, hostname }); const page = await dashboard.text();
    return { cookie: ownerCookie, csrf: /name="csrf" value="([a-f0-9]+)"/.exec(page)[1], preCookie: cookie, preCsrf: csrf };
  }
  const adapter = () => createApprovalAdapter({ token, endpoint });
  try { await fn({ app: () => app, directory, config, request, proposal, http, login, adapter, advance: ms => { clock += ms; }, restart: async ({ rotatePassword = false } = {}) => { await app.close(); app = createApprovalServer({ directory: join(directory, 'site'), apiToken: token, ownerHash: rotatePassword ? await passwordHash(`${password}-rotated`) : ownerHash, port: 0, now: () => clock }); endpoint = await app.listen(); } }); }
  finally { await app.close(); await rm(directory, { recursive: true, force: true }); }
}

test('HTTP API requires bearer auth, exact Host, immutable digest and closed schema', async () => fixture(async ({ http, proposal, adapter }) => {
  const p = proposal({ name: 'write', args: { path: 'fixture', content: 'test' } });
  const health = await http('/healthz'); assert.equal(health.status, 200); assert.deepEqual(await health.json(), { status: 'ok' });
  assert.equal((await http('/api/v1/proposals', { method: 'POST', data: p })).status, 401);
  const site = await http('/login'); const endpoint = new URL(site.url);
  const badHost = await new Promise((resolve, reject) => { const req = httpRequest({ hostname: endpoint.hostname, port: endpoint.port, path: '/', headers: { Host: 'evil.test' } }, res => { res.resume(); resolve(res.statusCode); }); req.on('error', reject); req.end(); });
  assert.equal(badHost, 403);
  assert.equal((await http('/api/v1/proposals', { method: 'POST', data: { ...p, digest: '0'.repeat(64) }, auth: true })).status, 400);
  assert.equal((await http('/api/v1/proposals', { method: 'POST', data: { ...p, state: 'approved' }, auth: true })).status, 400);
  assert.equal(await adapter().createProposal(p), p.digest); assert.equal(await adapter().createProposal(p), p.digest);
  assert.equal((await adapter().fetchDecision(p.digest)).status, 'pending');
}));
test('localhost supports login, polling and decisions but rejects other hosts and cross-alias origins', async () => fixture(async ({ http, login, proposal, adapter }) => {
  const endpoint = new URL((await http('/healthz')).url);
  const localhost = `localhost:${endpoint.port}`;
  const local = (path, options = {}) => http(path, { ...options, hostname: 'localhost' });
  assert.equal((await local('/healthz')).status, 200);
  for (const host of ['evil.test', `localhost.evil.test:${endpoint.port}`, 'localhost:1', `${endpoint.host}.evil.test`]) {
    const response = await new Promise((resolve, reject) => {
      const req = httpRequest({ hostname: endpoint.hostname, port: endpoint.port, path: '/', headers: { Host: host } }, res => { res.resume(); resolve(res.statusCode); });
      req.on('error', reject); req.end();
    });
    assert.equal(response, 403);
  }
  const pre = await local('/login');
  const cookie = pre.headers.get('set-cookie').split(';')[0];
  const csrf = /name="csrf" value="([a-f0-9]+)"/.exec(await pre.text())[1];
  // CSRF is checked before the password: valid same-origin requests reach password validation.
  const form = { csrf, username: 'lucky', password: 'incorrect-fixture' };
  assert.equal((await local('/login', { method: 'POST', cookie, form })).status, 403);
  assert.equal((await local('/login', { method: 'POST', cookie, origin: `http://${localhost}`, form })).status, 401);
  assert.equal((await http('/login', { method: 'POST', cookie, origin: `http://${localhost}`, form })).status, 403);
  const owner = await login('localhost', `http://${localhost}`);
  assert.equal((await local('/dashboard.js', owner)).status, 200);
  const p = proposal({ name: 'read', args: { path: 'localhost-fixture' } });
  await adapter().createProposal(p);
  assert.match(await (await local('/', owner)).text(), new RegExp(p.digest));
  const decision = { csrf: owner.csrf, id: p.digest, decision: 'denied' };
  assert.equal((await local('/decide', { ...owner, method: 'POST', form: decision })).status, 403);
  assert.equal((await local('/decide', { ...owner, method: 'POST', origin: `http://${localhost}`, form: decision })).status, 303);
  assert.equal((await adapter().fetchDecision(p.digest)).status, 'denied');
  assert.equal((await local('/logout', { ...owner, method: 'POST', origin: `http://${localhost}`, form: { csrf: owner.csrf } })).status, 303);
}));

test('login CSRF/Origin, hashed rotating sessions, escaped dashboard and logout revocation', async () => fixture(async ({ http, login, proposal, adapter, app }) => {
  const pre = await http('/login'); const page = await pre.text(); const cookie = pre.headers.get('set-cookie').split(';')[0];
  assert.match(pre.headers.get('set-cookie'), /HttpOnly; SameSite=Strict/); assert.ok(!pre.headers.get('set-cookie').includes('Secure')); assert.equal(pre.headers.get('cache-control'), 'no-store');
  // Browsers serialize a null Origin for form navigation under no-referrer; retain the origin only for same-origin requests.
  assert.equal(pre.headers.get('referrer-policy'), 'same-origin');
  const csrf = /name="csrf" value="([a-f0-9]+)"/.exec(page)[1];
  assert.equal((await http('/login', { method: 'POST', cookie, form: { csrf: 'wrong', username: 'lucky', password: 'wrong' } })).status, 403);
  assert.equal((await http('/login', { method: 'POST', cookie, origin: 'http://evil.test', form: { csrf, username: 'lucky', password: 'wrong' } })).status, 403);
  assert.equal((await http('/login', { method: 'POST', cookie, origin: 'null', form: { csrf, username: 'lucky', password: 'wrong' } })).status, 403);
  await adapter().createProposal(proposal({ name: 'read', args: { path: '<script>bad</script>' } }));
  const owner = await login();
  assert.equal((await http('/', { cookie: owner.preCookie })).status, 303);
  const dashboard = await http('/', owner); const html = await dashboard.text();
  assert.equal((await http('/', { cookie: `unrelated=fixture; ${owner.cookie}` })).status, 200);
  assert.equal((await http('/', { cookie: `${owner.cookie}; ${owner.cookie}` })).status, 303);
  assert.ok(html.includes('&lt;script&gt;')); assert.ok(!html.includes('<script>')); assert.match(dashboard.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  const sessions = app().store.db.prepare('SELECT * FROM approval_sessions').all(); assert.ok(sessions.every(row => !row.id.includes(owner.cookie.slice(13))));
  assert.equal((await http('/logout', { ...owner, method: 'POST', form: { csrf: owner.csrf } })).status, 303);
  assert.equal((await http('/', owner)).status, 303);
}));
test('live dashboard polls authenticated pages and reflects new, decided and expired proposals', async () => fixture(async ({ http, login, proposal, adapter, advance }) => {
  assert.equal((await http('/dashboard.js')).status, 401);
  const owner = await login();
  assert.equal((await http('/dashboard.js', { cookie: owner.preCookie })).status, 401);
  const script = await http('/dashboard.js', owner);
  assert.equal(script.status, 200);
  assert.match(script.headers.get('content-type'), /text\/javascript/);
  assert.equal(script.headers.get('cache-control'), 'no-store');
  const source = await script.text();
  assert.doesNotThrow(() => new Script(source));
  assert.match(source, /setInterval\(refresh, 3000\)/);
  assert.match(source, /fetch\(location.pathname/);
  const initial = await http('/', owner);
  const html = await initial.text();
  assert.match(html, /id="proposals"/);
  assert.match(html, /<script src="\/dashboard.js" defer><\/script>/);
  assert.match(initial.headers.get('content-security-policy'), /script-src 'self'; connect-src 'self'/);
  assert.ok(!initial.headers.get('content-security-policy').includes("script-src 'unsafe-inline'"));
  const p = proposal({ name: 'read', args: { path: 'live-update' } });
  await adapter().createProposal(p);
  assert.match(await (await http('/', owner)).text(), new RegExp(`id="proposal-${p.digest}" data-state="pending"`));
  assert.equal((await http('/decide', { ...owner, method: 'POST', form: { csrf: owner.csrf, id: p.digest, decision: 'denied' } })).status, 303);
  assert.match(await (await http('/', owner)).text(), new RegExp(`id="proposal-${p.digest}" data-state="denied"`));
  const expiring = proposal({ name: 'read', args: { path: 'live-expiry' } });
  await adapter().createProposal(expiring);
  advance(16 * 60000 + 1);
  assert.match(await (await http('/', owner)).text(), new RegExp(`id="proposal-${expiring.digest}" data-state="expired"`));
  const older = await (await http('/page/1', owner)).text();
  assert.match(older, /Page 2/);
  assert.ok(!older.includes(`id="proposal-${p.digest}"`));
  advance(8 * 3600000);
  assert.equal((await http('/dashboard.js', owner)).status, 401);
  assert.equal((await http('/', owner)).headers.get('location'), '/login');
}));

test('signed approved grants consume atomically once across concurrency and restart', async () => fixture(async ({ proposal, adapter, login, http, restart, app, directory }) => {
  const p = proposal({ name: 'write', args: { path: 'fixture', content: 'once' } }); await adapter().createProposal(p);
  const owner = await login();
  assert.equal((await http('/decide', { ...owner, method: 'POST', form: { csrf: owner.csrf, id: p.digest, decision: 'approved' } })).status, 303);
  assert.equal((await http('/decide', { ...owner, method: 'POST', form: { csrf: owner.csrf, id: p.digest, decision: 'denied' } })).status, 409);
  const decision = await adapter().fetchDecision(p.digest); assert.equal(decision.status, 'approved');
  const grant = { proposal: p.digest, digest: p.digest, binding: p.binding, grantId: decision.grantId };
  assert.equal(await adapter().consumeGrant({ ...grant, binding: { ...p.binding, scope: 'changed' } }).catch(() => false), false);
  const outcomes = await Promise.all([adapter().consumeGrant(grant), adapter().consumeGrant(grant)]); assert.equal(outcomes.filter(Boolean).length, 1);
  await restart(); assert.equal(await adapter().consumeGrant(grant), false); assert.equal((await adapter().fetchDecision(p.digest)).status, 'consumed');
  assert.equal((await stat(join(directory, 'site'))).mode & 0o777, 0o700); assert.equal((await stat(join(directory, 'site', 'state.sqlite'))).mode & 0o777, 0o600);
  assert.equal(app().store.db.prepare('SELECT COUNT(*) AS n FROM approval_proposals').get().n, 1);
}));
test('password rotation revokes owner sessions while retaining runner API credentials', async () => fixture(async ({ login, http, restart, adapter, proposal }) => {
  const owner = await login();
  const p = proposal({ name: 'read', args: { path: 'rotation-fixture' } });
  await adapter().createProposal(p);
  await restart();
  assert.equal((await http('/', owner)).status, 200);
  await restart({ rotatePassword: true });
  assert.equal((await http('/', owner)).status, 303);
  assert.equal((await http('/dashboard.js', owner)).status, 401);
  assert.equal((await adapter().fetchDecision(p.digest)).status, 'pending');
}));

test('denied and expired proposals never grant, reset expiry or become approved', async () => fixture(async ({ proposal, adapter, login, http, advance }) => {
  const p = proposal({ name: 'read', args: { path: 'denied' } }); await adapter().createProposal(p); const owner = await login();
  assert.equal((await http('/decide', { ...owner, method: 'POST', form: { csrf: owner.csrf, id: p.digest, decision: 'denied' } })).status, 303);
  assert.equal((await adapter().fetchDecision(p.digest)).status, 'denied');
  assert.equal((await http('/decide', { ...owner, method: 'POST', form: { csrf: owner.csrf, id: p.digest, decision: 'approved' } })).status, 409);
  const exp = proposal({ name: 'read', args: { path: 'expires' } }); await adapter().createProposal(exp); advance(16 * 60000 + 1);
  assert.equal((await adapter().fetchDecision(exp.digest)).status, 'expired'); await adapter().createProposal(exp);
  assert.equal((await adapter().fetchDecision(exp.digest)).status, 'expired');
  assert.equal((await http('/decide', { ...owner, method: 'POST', form: { csrf: owner.csrf, id: exp.digest, decision: 'approved' } })).status, 409);
}));
test('actual HTTP adapter binds full final private send preview and reserves once without SMTP', async () => fixture(async ({ directory, config, request, adapter, login, http }) => {
  const store = new Store(join(directory, 'runner')); store.claim(request); const ownerClaim = store.begin(request.id);
  const reply = { to: request.input.from, subject: 'Final subject', body: 'FULL_PRIVATE_SEND_PREVIEW' }; store.finish(request.id, ownerClaim, 'reply_ready', null, reply);
  try {
    const first = await reserveSend(store, request.id, config, adapter()); assert.equal(first.status, 'approval_required');
    const owner = await login(); const html = await (await http('/', owner)).text(); assert.match(html, /FULL_PRIVATE_SEND_PREVIEW/); assert.match(html, /requestPreview/); assert.match(html, /bodyDigest/);
    const binding = bindingFor(request, config, 'send', { sender: config.selfAddress, recipient: reply.to, subject: reply.subject, body: reply.body, bodyDigest: digest(reply.body) });
    assert.equal((await http('/decide', { ...owner, method: 'POST', form: { csrf: owner.csrf, id: digest(binding), decision: 'approved' } })).status, 303);
    const reserved = await reserveSend(store, request.id, config, adapter()); assert.equal(reserved.status, 'send_reserved'); assert.deepEqual(reserved.reply, reply);
    assert.equal((await reserveSend(store, request.id, config, adapter())).status, 'failed');
  } finally { store.close(); }
}));
test('persisted pending HTTP decision is polled before provider or SDK loading', async () => fixture(async ({ directory, config, request, adapter }) => {
  const store = new Store(join(directory, 'runner')); store.claim(request);
  const binding = bindingFor(request, config, 'investigate', { contextPaths: [] }); const op = store.operation(binding); const id = await adapter().createProposal({ digest: op.key, binding }); store.db.prepare('UPDATE operations SET proposal=? WHERE key=?').run(id, op.key);
  let calls = 0;
  try {
    const result = await runMail({ store, id: request.id, config, approval: adapter(), provider: async () => { calls++; throw new Error('must not load'); } });
    assert.equal(result.status, 'approval_required'); assert.equal(calls, 0);
  } finally { store.close(); }
}));
test('owner sessions expire absolutely and login attempts are bounded', async () => fixture(async ({ login, http, advance }) => {
  const owner = await login();
  assert.equal((await http('/login', owner)).status, 303); // GET login cannot log an owner out.
  assert.equal((await http('/', owner)).status, 200);
  advance(8 * 3600000 + 1); assert.equal((await http('/', owner)).status, 303);
  const pre = await http('/login'); const cookie = pre.headers.get('set-cookie').split(';')[0]; const csrf = /name="csrf" value="([a-f0-9]+)"/.exec(await pre.text())[1];
  for (let i = 0; i < 5; i++) assert.equal((await http('/login', { cookie, method: 'POST', form: { csrf, username: 'lucky', password: 'incorrect-fixture' } })).status, 401);
  assert.equal((await http('/login', { cookie, method: 'POST', form: { csrf, username: 'lucky', password: 'incorrect-fixture' } })).status, 429);
}));

test('production adapter rejects unsigned or forged decision responses', async () => {
  const token = randomBytes(48).toString('base64url'); const id = 'a'.repeat(64);
  const adapter = createApprovalAdapter({ token, fetchImpl: async () => new Response(JSON.stringify({ decision: { status: 'approved', digest: id, binding: {}, grantId: 'forged', expiresAt: Date.now() + 60000 }, signature: 'forged' }), { headers: { 'Content-Type': 'application/json' } }) });
  await assert.rejects(adapter.fetchDecision(id));
});

test('production CLI offline help needs no host config or credential files', async () => {
  assert.equal((await productionCli(['--help'], null)).status, 'configured');
  await assert.rejects(productionCli(['--approved', 'yes'], {}));
});
