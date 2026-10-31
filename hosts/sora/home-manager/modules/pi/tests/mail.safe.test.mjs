import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { automaticEligible, bindingFor, canonical, classify, digest, finishSend, formatReply, Gate, normalize, ownerSafe, policyGrant, reserveSend, Store, validateConfig } from '../mail/core.mjs';
import { executeSafe, safePlan, safeResult } from '../mail/safe.mjs';
import { prepareOutcome, validateSend } from '../mail/workflow.mjs';

const weather = () => ({ name: 'weather', args: { city: 'Piracicaba', country: 'BR' } });
const health = () => ({ name: 'machine_status', args: {} });
const plan = () => ({ kind: 'safe', operations: [weather(), health()] });
const raw = () => ({ version: 1, messageId: '<safe@example.test>', from: 'owner@example.test', subject: 'Weather and health', body: 'How is the weather in Piracicaba and how is the machine running?', autoSubmitted: 'no', precedence: '', attachments: [] });
const config = cwd => ({ mailbox: 'fixture', selfAddress: 'assistant@example.test', provider: 'faux/faux', scope: 'test', cwd, contextPaths: [], automaticReplies: true, safeCapabilities: ['weather', 'machine_status'], recipientPolicy: { version: 1, allowedRecipients: ['owner@example.test', 'hidden@example.test'], defaultRecipient: 'owner@example.test' } });
const weatherData = () => ({ source: 'Open-Meteo model estimate', timezone: 'UTC', utcOffsetSeconds: 0, fetchedAt: new Date().toISOString(), city: 'Piracicaba', country: 'BR', observedAt: new Date().toISOString().slice(0, 16), temperatureC: 25, apparentTemperatureC: 26, humidityPercent: 60, precipitationMm: 0, weatherCode: 1, windKmh: 8 });
const healthData = () => ({ machine: 'Sora', collectedAt: new Date().toISOString(), uptimeSeconds: 1234, logicalCpus: 8, loadAverage: [0.1, 0.2, 0.3], ramAvailableBytes: 1000, ramTotalBytes: 2000, diskAvailableBytes: 3000, diskTotalBytes: 4000 });
function complete(store, binding, result = null) {
  const row = store.operation(binding);
  assert.ok(store.transition(row.key, 'pending', 'executing', policyGrant(binding)));
  new Gate(store, null).complete(binding, true, result);
}
async function fixture(fn, kind = 'safe') {
  const directory = await mkdtemp(join(tmpdir(), 'mail-safe-'));
  const store = new Store(directory), c = config(directory), request = normalize(raw(), c);
  store.claim(request); const owner = store.begin(request.id);
  store.db.prepare('UPDATE requests SET kind=? WHERE id=?').run(kind, request.id);
  if (kind === 'safe') {
    complete(store, bindingFor(request, c, 'safe_plan', plan()));
    for (const op of plan().operations) complete(store, bindingFor(request, c, 'safe_tool', { planDigest: digest(plan()), ...op }), op.name === 'weather' ? weatherData() : healthData());
  }
  const reply = formatReply(request, { subject: 'Ignored', body: 'Collected weather and basic health only.' }, c);
  complete(store, bindingFor(request, c, 'safe_reply', { kind, planDigest: kind === 'safe' ? digest(plan()) : null, replyDigest: digest(reply) }));
  store.finish(request.id, owner, 'reply_ready', null, reply);
  const approval = { configured: true, async createProposal() { throw new Error('must not propose'); }, async fetchDecision() { throw new Error('must not fetch'); }, async consumeGrant() { throw new Error('must not consume'); } };
  try { await fn({ directory, store, config: c, request, reply, approval }); }
  finally { store.close(); await rm(directory, { recursive: true, force: true }); }
}

test('safe plans are closed, bounded and never accept native tools, arbitrary URLs or approvals', () => {
  assert.deepEqual(classify(JSON.stringify(plan()), true), plan());
  assert.throws(() => classify(JSON.stringify(plan())));
  for (const p of [null, { ...plan(), approved: true }, { kind: 'safe', operations: [] }, { kind: 'safe', operations: [weather(), weather()] }, { kind: 'safe', operations: [weather(), health(), health()] }, { kind: 'safe', operations: [{ name: 'bash', args: {} }] }, { kind: 'safe', operations: [{ name: 'machine_status', args: { path: '/secret' } }] }, { kind: 'safe', operations: [{ name: 'weather', args: { city: 'https://example.test/', country: 'BR' } }] }, { kind: 'safe', operations: [{ name: 'weather', args: { ...weather().args, url: 'https://example.test' } }] }, { kind: 'safe', operations: [{ name: 'weather', args: { city: 'Piracicaba', country: 'br' } }] }]) assert.throws(() => safePlan(p));
});
test('safe config defaults off, needs explicit runtime owner policy and closed capability names', () => {
  const c = config('/tmp'), request = normalize(raw(), c);
  assert.ok(ownerSafe(request, c, plan().operations));
  for (const changed of [{ automaticReplies: false }, { safeCapabilities: ['weather'] }]) assert.equal(ownerSafe(request, { ...c, ...changed }, plan().operations), false);
  for (const key of ['automaticReplies', 'safeCapabilities', 'recipientPolicy']) { const legacy = { ...c }; delete legacy[key]; assert.equal(ownerSafe(request, legacy, plan().operations), false); }
  for (const changed of [{ automaticReplies: 'true' }, { safeCapabilities: ['bash'] }, { safeCapabilities: ['weather', 'weather'] }]) assert.throws(() => validateConfig({ ...c, ...changed }));
  assert.equal(ownerSafe(normalize({ ...raw(), from: 'outsider@example.test' }, c), c), false);
  assert.throws(() => normalize({ ...raw(), automaticReplies: true, safeCapabilities: ['weather'], plan: plan() }, c));
});
test('fixed weather HTTP uses only two allowlisted hosts and bounded typed data; strips remote extras', async () => {
  const urls = [];
  const fetchImpl = async (url, options) => {
    urls.push(url);
    assert.equal(url.protocol, 'https:'); assert.equal(options.redirect, 'error'); assert.equal(options.headers, undefined); assert.equal(options.body, undefined);
    const data = urls.length === 1 ? { results: [{ name: 'Piracicaba', country_code: 'BR', latitude: -22.72528, longitude: -47.64917, arbitrary: 'DROP_REMOTE_MARKER' }] } : { timezone: 'GMT', utc_offset_seconds: 0, current: { time: '2026-10-31T19:30', temperature_2m: 25, apparent_temperature: 26, relative_humidity_2m: 60, precipitation: 0, weather_code: 1, wind_speed_10m: 8 }, arbitrary: 'DROP_REMOTE_MARKER' };
    return Response.json(data);
  };
  const result = await executeSafe(weather(), AbortSignal.timeout(1000), { fetchImpl });
  assert.deepEqual(urls.map(url => url.hostname), ['geocoding-api.open-meteo.com', 'api.open-meteo.com']);
  assert.equal(urls[0].searchParams.get('countryCode'), 'BR'); assert.equal(urls[1].searchParams.get('timezone'), 'UTC');
  assert.equal(result.temperatureC, 25); assert.equal(result.timezone, 'UTC'); assert.equal(result.utcOffsetSeconds, 0); assert.match(result.source, /model estimate/); assert.doesNotMatch(canonical(result), /DROP_REMOTE_MARKER/);
});
for (const mode of ['network', 'redirect', 'oversize', 'wrong-country', 'invalid-coordinate', 'missing-current', 'non-json', 'http-failure']) test(`weather ${mode} fails closed without retries`, async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls++;
    if (mode === 'network') throw new Error('offline');
    if (mode === 'redirect') return new Response('', { status: 302 });
    if (mode === 'oversize') return new Response('x'.repeat(32769), { headers: { 'Content-Type': 'application/json' } });
    if (mode === 'non-json') return new Response('{}');
    if (mode === 'http-failure') return new Response('{}', { status: 500 });
    if (calls === 1) return Response.json({ results: [{ name: 'Piracicaba', country_code: mode === 'wrong-country' ? 'US' : 'BR', latitude: mode === 'invalid-coordinate' ? 91 : -22, longitude: -47 }] });
    return Response.json({ timezone: 'GMT', utc_offset_seconds: 0 });
  };
  await assert.rejects(executeSafe(weather(), AbortSignal.timeout(1000), { fetchImpl }));
  assert.equal(calls, mode === 'missing-current' ? 2 : 1);
});
test('fixed health exposes only bounded aggregate Sora data and falls back only on missing /persist', async () => {
  const paths = [];
  const os = { availableMemory: () => 1000, totalmem: () => 2000, uptime: () => 42, cpus: () => [{ model: 'PRIVATE_CPU_DETAIL' }, {}], loadavg: () => [0.1, 0.2, 0.3] };
  const statfsImpl = async path => { paths.push(path); if (path === '/persist') throw Object.assign(new Error('missing'), { code: 'ENOENT' }); return { bavail: 3, blocks: 4, bsize: 1000 }; };
  const value = await executeSafe(health(), AbortSignal.timeout(1000), { os, statfsImpl });
  assert.deepEqual(paths, ['/persist', '/']); assert.equal(value.diskTotalBytes, 4000); assert.equal(value.logicalCpus, 2); assert.doesNotMatch(canonical(value), /PRIVATE_CPU_DETAIL|\/persist/);
  await assert.rejects(executeSafe(health(), null, { os, statfsImpl: async () => { throw Object.assign(new Error('denied'), { code: 'EACCES' }); } }));
});
test('safe results reject overflow, extra/private fields and oversized strings', () => {
  for (const value of [{ ...weatherData(), private: 'no' }, { ...weatherData(), city: 'x'.repeat(4097) }, { ...weatherData(), temperatureC: 1000 }, { ...weatherData(), utcOffsetSeconds: -10800 }]) assert.throws(() => safeResult(weather(), value));
  for (const value of [{ ...healthData(), logicalCpus: 0 }, { ...healthData(), ramAvailableBytes: 9999 }, { ...healthData(), loadAverage: [Infinity, 0, 0] }, { ...healthData(), processes: [] }]) assert.throws(() => safeResult(health(), value));
});
test('safe timestamp parsing rejects impossible calendar dates and times without rejecting historical snapshots', () => {
  for (const stamp of ['2026-02-29T00:00', '2026-02-31T00:00:00.000Z', '2026-04-31T12:00', '2026-10-31T24:00', '2026-10-31T12:60', '2026-10-31T12:00:60Z', '2026-13-01T00:00', '2026-10-31T12:00-03:00']) {
    assert.throws(() => safeResult(weather(), { ...weatherData(), observedAt: stamp }));
    assert.throws(() => safeResult(weather(), { ...weatherData(), fetchedAt: stamp }));
    assert.throws(() => safeResult(health(), { ...healthData(), collectedAt: stamp }));
  }
  assert.ok(safeResult(health(), { ...healthData(), collectedAt: '2000-02-29T00:00:00Z' }));
  assert.ok(safeResult(weather(), { ...weatherData(), observedAt: '2000-02-29T00:00' }));
});
function updateSnapshot(store, name, changes) {
  const row = store.db.prepare("SELECT key,result FROM operations WHERE json_extract(binding,'$.phase')='safe_tool' AND json_extract(binding,'$.operation.name')=?").get(name);
  store.db.prepare('UPDATE operations SET result=? WHERE key=?').run(canonical({ ...JSON.parse(row.result), ...changes }), row.key);
}
for (const [name, field, age] of [
  ['machine_status', 'collectedAt', 300001], ['machine_status', 'collectedAt', -120001],
  ['weather', 'fetchedAt', 300001], ['weather', 'fetchedAt', -120001],
  ['weather', 'observedAt', 5400001], ['weather', 'observedAt', -120001],
]) test(`automatic reservation rejects stale/future ${name} ${field} age ${age} but retains manual approval`, async () => fixture(async ({ store, config, request, reply }) => {
  const now = Date.now();
  updateSnapshot(store, name, { [field]: new Date(now - age).toISOString() });
  assert.equal(automaticEligible(store, request, config, reply, now), false);
  let proposals = 0;
  const approval = { configured: true, async createProposal() { proposals++; return 'manual'; }, async fetchDecision() { return { status: 'pending' }; } };
  assert.equal((await reserveSend(store, request.id, config, approval, null, { now: () => now })).status, 'approval_required');
  assert.equal(proposals, 1);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE json_extract(binding,'$.phase')='send' AND grant IS NOT NULL").get().n, 0);
}));
test('freshness limits are inclusive and minute-only Open-Meteo observations are UTC', async () => fixture(async ({ store, config, request, reply }) => {
  const now = Date.parse('2026-10-31T19:30:00.000Z');
  updateSnapshot(store, 'weather', { fetchedAt: '2026-10-31T19:25:00Z', observedAt: '2026-10-31T18:00' });
  updateSnapshot(store, 'machine_status', { collectedAt: '2026-10-31T19:32:00.000Z' });
  assert.equal(automaticEligible(store, request, config, reply, now), true);
  assert.equal(automaticEligible(store, request, config, reply, now + 1), false);
  updateSnapshot(store, 'weather', { fetchedAt: '2026-10-31T19:32:00Z', observedAt: '2026-10-31T19:32' });
  updateSnapshot(store, 'machine_status', { collectedAt: '2026-10-31T19:25:00Z' });
  assert.equal(automaticEligible(store, request, config, reply, now), true);
  assert.equal(automaticEligible(store, request, config, reply, now - 1), false);
}));
for (const expireAt of [1, 2, 3]) test(`delayed automatic reservation rechecks snapshot age at boundary ${expireAt}`, async () => fixture(async ({ store, config, request }) => {
  const start = Date.now();
  updateSnapshot(store, 'weather', { fetchedAt: new Date(start).toISOString(), observedAt: new Date(start).toISOString() });
  updateSnapshot(store, 'machine_status', { collectedAt: new Date(start).toISOString() });
  let reads = 0, proposals = 0;
  const now = () => ++reads >= expireAt ? start + 300001 : start;
  const approval = { configured: true, async createProposal() { proposals++; return 'manual'; }, async fetchDecision() { return { status: 'pending' }; } };
  const result = await reserveSend(store, request.id, config, approval, null, { now });
  assert.equal(result.status, expireAt === 1 ? 'approval_required' : 'failed');
  assert.equal(proposals, expireAt === 1 ? 1 : 0);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='executing' AND json_extract(binding,'$.phase')='send'").get().n, 0);
}));
for (const state of ['pending', 'denied']) test(`stale snapshots preserve an existing ${state} manual decision`, async () => fixture(async ({ store, config, request, reply }) => {
  updateSnapshot(store, 'machine_status', { collectedAt: '2000-01-01T00:00:00Z' });
  const binding = bindingFor(request, config, 'send', { sender: config.selfAddress, recipient: reply.to, subject: reply.subject, body: reply.body, bodyDigest: digest(reply.body) });
  const op = store.operation(binding);
  store.db.prepare('UPDATE operations SET state=?,proposal=? WHERE key=?').run(state, 'original-proposal', op.key);
  const approval = { configured: true, async createProposal() { throw new Error('must retain proposal'); }, async fetchDecision(proposal) { assert.equal(proposal, 'original-proposal'); return { status: 'pending' }; } };
  assert.equal((await reserveSend(store, request.id, config, approval)).status, state === 'pending' ? 'approval_required' : 'failed');
  assert.equal(store.operation(binding).state, state); assert.equal(store.operation(binding).grant, null);
}));

test('stale snapshots can still receive exact manual disclosure approval, consumed once', async () => fixture(async ({ store, config, request, reply }) => {
  updateSnapshot(store, 'machine_status', { collectedAt: '2000-01-01T00:00:00Z' });
  let consumed = 0;
  const approval = { configured: true,
    async createProposal(proposal) {
      assert.equal(proposal.binding.operation.body, reply.body);
      assert.equal(proposal.binding.operation.recipient, reply.to);
      return proposal.digest;
    },
    async fetchDecision(key) { return { status: 'approved', digest: key, grantId: key, expiresAt: Date.now() + 60000 }; },
    async consumeGrant() { consumed++; return true; },
  };
  const reserved = await reserveSend(store, request.id, config, approval);
  assert.equal(reserved.status, 'send_reserved'); assert.equal(consumed, 1);
  assert.equal(store.db.prepare('SELECT grant FROM operations WHERE key=?').get(reserved.reservation).grant, reserved.reservation);
  finishSend(store, request.id, reserved.reservation, 'unknown');
  assert.equal((await reserveSend(store, request.id, config, approval)).status, 'failed'); assert.equal(consumed, 1);
}));

test('automatic delivery derives only from full exact stored host provenance and survives restart single-use', async () => fixture(async ({ directory, store, config, request, reply, approval }) => {
  assert.ok(automaticEligible(store, request, config, reply));
  const second = new Store(directory);
  try {
    const results = await Promise.all([reserveSend(store, request.id, config, approval), reserveSend(second, request.id, config, approval)]);
    assert.equal(results.filter(r => r.status === 'send_reserved').length, 1);
    const reserved = results.find(r => r.status === 'send_reserved');
    const output = { version: 1, reason: null, ...reserved };
    const validated = new Function('$input', '$', `return (${validateSend.toString()})();`)({ all: () => [{ json: { code: 0, stdout: JSON.stringify(output) } }] }, () => ({ first: () => ({ json: { deadline: Date.now() + 60000 } }) }));
    assert.equal(prepareOutcome('unknown', validated)[0].json.payload.length > 0, true);
    assert.equal(finishSend(second, request.id, reserved.reservation, 'unknown').status, 'send_unknown');
    assert.equal((await reserveSend(store, request.id, config, approval)).status, 'failed');
    assert.doesNotMatch(JSON.stringify(store.db.prepare('SELECT binding,result FROM operations').all()), /hidden@example.test/);
  } finally { second.close(); }
}));
test('public zero-tool owner reply can auto-send only with host provenance', async () => fixture(async ({ store, config, request, reply, approval }) => {
  assert.ok(automaticEligible(store, request, config, reply));
  assert.equal((await reserveSend(store, request.id, config, approval)).status, 'send_reserved');
}, 'reply'));
for (const mutation of ['missing-plan', 'missing-result', 'missing-grant', 'native-operation', 'investigation', 'context', 'forged-reply', 'cap-revoked', 'owner-revoked', 'scope-changed', 'safe-executing', 'safe-unknown']) test(`automatic eligibility rejects ${mutation}`, async () => fixture(async ({ store, config, request, reply }) => {
  if (mutation === 'missing-plan') store.db.exec("DELETE FROM operations WHERE json_extract(binding,'$.phase')='safe_plan'");
  if (mutation === 'missing-result') store.db.exec("UPDATE operations SET result=NULL WHERE json_extract(binding,'$.phase')='safe_tool'");
  if (mutation === 'missing-grant') store.db.exec('UPDATE operations SET grant=NULL');
  if (mutation === 'native-operation' || mutation === 'investigation') store.operation(bindingFor(request, config, mutation === 'native-operation' ? 'tool' : 'investigate', {}));
  if (mutation === 'context') store.db.prepare('UPDATE requests SET context=? WHERE id=?').run('private', request.id);
  if (mutation === 'forged-reply') reply.body += 'forged';
  if (mutation === 'cap-revoked') config.safeCapabilities = ['weather'];
  if (mutation === 'owner-revoked') config.recipientPolicy = { version: 1, allowedRecipients: ['hidden@example.test'], defaultRecipient: 'hidden@example.test' };
  if (mutation === 'scope-changed') config.scope = 'different';
  if (mutation.startsWith('safe-')) store.db.prepare("UPDATE operations SET state=? WHERE json_extract(binding,'$.phase')='safe_tool'").run(mutation.slice(5));
  assert.equal(automaticEligible(store, request, config, reply), false);
}));
for (const state of ['pending', 'denied', 'reserving', 'executing', 'sent', 'send_unknown', 'expired', 'consumed']) test(`automatic path preserves existing ${state} site delivery`, async () => fixture(async ({ store, config, request, reply, approval }) => {
  const binding = bindingFor(request, config, 'send', { sender: config.selfAddress, recipient: reply.to, subject: reply.subject, body: reply.body, bodyDigest: digest(reply.body) });
  const op = store.operation(binding);
  store.db.prepare('UPDATE operations SET state=?,proposal=? WHERE key=?').run(state, 'existing-site-proposal', op.key);
  if (state === 'pending') {
    let proposed = 0;
    const result = await reserveSend(store, request.id, config, { ...approval, async createProposal() { proposed++; return 'manual'; }, async fetchDecision() { return { status: 'pending' }; } });
    assert.equal(result.status, 'approval_required'); assert.equal(proposed, 0);
  } else assert.equal((await reserveSend(store, request.id, config, approval)).status, 'failed');
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='executing' AND grant LIKE 'host-safe-v1:%' AND json_extract(binding,'$.phase')='send'").get().n, 0);
}));
test('automatic path never adopts a pending delivery whose site proposal may still be in flight', async () => fixture(async ({ store, config, request, reply }) => {
  const binding = bindingFor(request, config, 'send', { sender: config.selfAddress, recipient: reply.to, subject: reply.subject, body: reply.body, bodyDigest: digest(reply.body) });
  store.operation(binding);
  let proposals = 0;
  const result = await reserveSend(store, request.id, config, { configured: true, async createProposal() { proposals++; return 'manual-site'; }, async fetchDecision() { return { status: 'pending' }; } });
  assert.equal(result.status, 'approval_required'); assert.equal(proposals, 1);
  assert.equal(store.operation(binding).grant, null);
}));
test('automatic path refreshes policy immediately before AND after durable reservation', async () => {
  for (const revokeAt of [2, 3]) for (const changed of [
    { recipientPolicy: { version: 1, allowedRecipients: ['hidden@example.test'], defaultRecipient: 'hidden@example.test' } },
    { automaticReplies: false }, { safeCapabilities: [] }, { safeCapabilities: ['weather'] },
  ]) await fixture(async ({ store, config, request, approval }) => {
    let reads = 0;
    const currentConfig = () => ++reads >= revokeAt ? { ...config, ...changed } : config;
    assert.equal((await reserveSend(store, request.id, config, approval, null, { currentConfig })).status, 'failed');
    assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='executing' AND json_extract(binding,'$.phase')='send'").get().n, 0);
  });
});
