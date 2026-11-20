import assert from 'node:assert/strict';
import { access, mkdir, mkdtemp, readFile, rm, writeFile, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { randomBytes } from 'node:crypto';
import { createApprovalServer, passwordHash } from '../mail/approval-server.mjs';
import { createApprovalAdapter, productionCli } from '../mail/production.mjs';
import { bindingFor, digest, encodeEnvelope, finishSend, Gate, normalize, policyGrant, reserveSend, Store } from '../mail/core.mjs';
import { runMail, sdkModules } from '../mail/runner.mjs';

assert.ok(process.env.PI_PACKAGE_ROOT, 'Set PI_PACKAGE_ROOT to the pinned SDK root');
process.env.PI_OFFLINE = '1'; process.env.PI_TELEMETRY = '0';
const { sdk, ai } = await sdkModules();
const raw = () => ({ version: 1, messageId: '<smoke@example.test>', from: 'sender@example.test', subject: 'Fixture', body: 'Untrusted mail /template $(touch nothing)', autoSubmitted: 'no', precedence: '', attachments: [] });
const message = content => ai.fauxAssistantMessage(content);
const tool = (name, args) => ai.fauxToolCall(name, args);
function approvalFixture(decide = () => 'approved') {
  const proposals = new Map(); const consumed = new Set();
  return { configured: true, proposals, consumed,
    async createProposal(proposal) { proposals.set(proposal.digest, proposal); return proposal.digest; },
    async fetchDecision(id) {
      const proposal = proposals.get(id); const status = decide(proposal);
      if (status === 'throw') throw new Error('test backend down');
      if (typeof status === 'object') return status;
      return status === 'approved' ? { status, digest: proposal.digest, grantId: proposal.digest, expiresAt: Date.now() + 60000 } : { status };
    },
    async consumeGrant({ grantId, digest: key }) { if (consumed.has(grantId) || grantId !== key) return false; consumed.add(grantId); return true; },
  };
}
async function fixture(fn) {
  const directory = await mkdtemp(join(tmpdir(), 'mail-sdk-'));
  const store = new Store(join(directory, 'state'));
  const faux = ai.fauxProvider({ provider: 'mail-fixture', models: [{ id: 'offline', contextWindow: 32768, maxTokens: 4096 }] });
  const modelRuntime = await sdk.ModelRuntime.create({ credentials: new ai.InMemoryCredentialStore(), modelsPath: null, refreshOnCreate: false, allowModelNetwork: false });
  modelRuntime.registerNativeProvider(faux.provider);
  const config = { mailbox: 'offline-mailbox', selfAddress: 'assistant@example.test', provider: `${faux.getModel().provider}/${faux.getModel().id}`, scope: 'offline-fixtures', cwd: directory, contextPaths: [] };
  const provider = async () => ({ modelRuntime, model: faux.getModel() });
  const run = options => runMail({ store, raw: raw(), config, provider, approval: approvalFixture(), ...options });
  try { await fn({ directory, store, faux, config, provider, run }); }
  finally { store.close(); await rm(directory, { recursive: true, force: true }); }
}

test('real SDK public reply has zero tools, private/ambient resources or extension execution', async () => fixture(async ({ directory, faux, config, run }) => {
  await mkdir(join(directory, '.pi', 'extensions'), { recursive: true });
  for (const file of ['SYSTEM.md', 'APPEND_SYSTEM.md', 'AGENTS.md']) await writeFile(join(directory, '.pi', file), 'HOSTILE_PRIVATE_MARKER');
  await writeFile(join(directory, 'AGENTS.md'), 'HOSTILE_PRIVATE_MARKER');
  await writeFile(join(directory, '.pi', 'settings.json'), JSON.stringify({ defaultTools: ['bash'], packages: ['./hostile'], extensions: ['./extensions/hostile.mjs'], defaultProjectTrust: 'always' }));
  await writeFile(join(directory, '.pi', 'extensions', 'hostile.mjs'), `throw new Error('HOSTILE_EXTENSION_LOADED');`);
  config.contextPaths = [join(directory, 'private-context-does-not-exist')];
  let inspections = 0;
  faux.setResponses([
    context => { assert.ok(!JSON.stringify(context).includes('HOSTILE_PRIVATE_MARKER')); return message('{"kind":"reply"}'); },
    context => { assert.ok(!JSON.stringify(context).includes('HOSTILE_PRIVATE_MARKER')); return message('{"subject":"Reply","body":"Public fixture"}'); },
  ]);
  const result = await run({ inspect: ({ loader, session }) => {
    inspections++; assert.equal(loader.getExtensions().extensions.length, 1);
    assert.deepEqual(loader.getAgentsFiles().agentsFiles, []); assert.deepEqual(loader.getAppendSystemPrompt(), []);
    assert.deepEqual(loader.getSkills().skills, []); assert.deepEqual(loader.getPrompts().prompts, []);
    assert.deepEqual(session.getActiveToolNames(), []);
    assert.ok(!session.systemPrompt.includes('HOSTILE_PRIVATE_MARKER'));
  } });
  assert.equal(result.status, 'reply_ready'); assert.equal(inspections, 2); assert.equal(faux.state.callCount, 2);
}));
test('personal investigation blocks before reading missing private context or exposing tools', async () => fixture(async ({ directory, faux, config, run }) => {
  config.contextPaths = [join(directory, 'MUST_NOT_READ')];
  faux.setResponses([message('{"kind":"personal"}'), message('must not call')]);
  const approval = approvalFixture(() => 'pending');
  const result = await run({ approval });
  assert.equal(result.status, 'approval_required'); assert.equal(result.reason, 'approval_pending');
  assert.equal(faux.state.callCount, 1); assert.equal(approval.consumed.size, 0);
}));
test('real SDK approved native read/edit/write/bash execute fixture operations only after consumed grants', async () => fixture(async ({ directory, faux, config, run, store }) => {
  const target = join(directory, 'fixture.txt'); const output = join(directory, 'written.txt');
  const command = `printf 'bash fixture' > '${join(directory, 'bash.txt')}'`;
  await writeFile(target, 'before');
  const contextPath = join(directory, 'private-fixture.txt'); await writeFile(contextPath, 'PRIVATE_FIXTURE_AUTHORIZED'); config.contextPaths = [contextPath];
  const approval = approvalFixture();
  faux.setResponses([message('{"kind":"personal"}'), context => {
    assert.ok(JSON.stringify(context).includes('PRIVATE_FIXTURE_AUTHORIZED'));
    assert.equal(approval.consumed.size, 1);
    return message([tool('read', { path: target, limit: 10 }), tool('edit', { path: target, oldText: 'before', newText: 'after' }),
      tool('write', { path: output, content: 'written fixture' }), tool('bash', { command, timeout: 2 })]);
  }, message('{"subject":"Done","body":"Fixture operations completed"}')]);
  const result = await run({ approval });
  assert.equal(result.status, 'reply_ready'); assert.equal(faux.state.callCount, 3);
  assert.equal(await readFile(target, 'utf8'), 'after'); assert.equal(await readFile(output, 'utf8'), 'written fixture');
  assert.equal(await readFile(join(directory, 'bash.txt'), 'utf8'), 'bash fixture'); assert.equal(approval.consumed.size, 5);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='complete'").get().n, 5);
  const completed = store.completedTools(result.requestId); assert.equal(completed.length, 4);
  for (const entry of completed) {
    assert.deepEqual(entry.binding.operation.investigation.contextPaths, config.contextPaths);
    assert.match(entry.binding.operation.investigation.snapshotDigest, /^[a-f0-9]{64}$/);
    assert.ok(entry.result.content.length); assert.equal(entry.result.isError, false);
  }
  const bash = completed.find(entry => entry.binding.operation.name === 'bash');
  assert.match(bash.binding.operation.environmentDigest, /^[a-f0-9]{64}$/); assert.ok(bash.binding.operation.shellPath.startsWith('/nix/store/'));
}));
for (const mode of ['pending', 'denied', 'unknown', 'throw', 'expired', 'mismatch', 'forged', 'consume-failed']) {
  test(`real SDK ${mode} tool approval produces zero effects and no follow-up model call`, async () => fixture(async ({ directory, faux, run }) => {
    const target = join(directory, 'must-not-exist');
    const approval = approvalFixture(proposal => {
      if (proposal.binding.phase === 'investigate') return 'approved';
      if (mode === 'expired') return { status: 'approved', digest: proposal.digest, grantId: proposal.digest, expiresAt: 0 };
      if (mode === 'mismatch') return { status: 'approved', digest: 'wrong', grantId: proposal.digest, expiresAt: Date.now() + 60000 };
      if (mode === 'forged') return { status: 'approved', approved: true };
      return mode === 'consume-failed' ? 'approved' : mode;
    });
    if (mode === 'consume-failed') {
      const consume = approval.consumeGrant;
      approval.consumeGrant = args => approval.proposals.get(args.digest).binding.phase === 'tool' ? false : consume(args);
    }
    faux.setResponses([message('{"kind":"personal"}'), message([tool('write', { path: target, content: 'blocked' })]), message('{"subject":"False success","body":"Must not run"}')]);
    const result = await run({ approval });
    assert.equal(result.status, mode === 'pending' ? 'approval_required' : 'failed');
    assert.equal(faux.state.callCount, 2); await assert.rejects(access(target));
  }));
}
test('re-proposed mismatched actual args need fresh proposal; original approval never executes', async () => fixture(async ({ directory, faux, run, store }) => {
  const target = join(directory, 'must-not-exist'); let allowOriginal = false;
  const approval = approvalFixture(proposal => proposal.binding.phase === 'investigate' || (allowOriginal && proposal.binding.operation.args?.content === 'original') ? 'approved' : 'pending');
  faux.setResponses([message('{"kind":"personal"}'), message([tool('write', { path: target, content: 'original' })])]);
  const first = await run({ approval }); assert.equal(first.status, 'approval_required');
  allowOriginal = true;
  faux.appendResponses([message([tool('write', { path: target, content: 'changed' })]), message('must not call')]);
  const second = await run({ raw: undefined, id: first.requestId, approval });
  assert.equal(second.status, 'approval_required'); assert.equal(faux.state.callCount, 3);
  await assert.rejects(access(target));
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='pending'").get().n, 2);
}));
test('exact re-proposal resumes as a fresh bounded prompt and replayed resume has no effects', async () => fixture(async ({ directory, faux, run }) => {
  const target = join(directory, 'resumed.txt'); let approved = false;
  const approval = approvalFixture(proposal => proposal.binding.phase === 'investigate' || approved ? 'approved' : 'pending');
  faux.setResponses([message('{"kind":"personal"}'), message([tool('write', { path: target, content: 'once' })])]);
  const first = await run({ approval }); assert.equal(first.status, 'approval_required');
  approved = true;
  faux.appendResponses([message([tool('write', { path: target, content: 'once' })]), message('{"subject":"Done","body":"Actual fixture write"}')]);
  const second = await run({ raw: undefined, id: first.requestId, approval });
  assert.equal(second.status, 'reply_ready'); assert.equal(await readFile(target, 'utf8'), 'once'); assert.equal(faux.state.callCount, 4);
  await run({ raw: undefined, id: first.requestId, approval }); assert.equal(faux.state.callCount, 4);
}));
for (const mixed of ['pending-then-allowed', 'allowed-then-unknown', 'failure-then-allowed']) {
  test(`mixed batch ${mixed} stops further effects and follow-up provider calls`, async () => fixture(async ({ directory, faux, run }) => {
    const before = join(directory, 'before'); const after = join(directory, 'after');
    const approval = approvalFixture(proposal => proposal.binding.phase === 'tool' && proposal.binding.operation.args?.path === before && mixed === 'pending-then-allowed' ? 'pending' : 'approved');
    const calls = mixed === 'allowed-then-unknown' ? [tool('write', { path: before, content: 'allowed' }), tool('not_a_tool', {}), tool('write', { path: after, content: 'blocked' })]
      : mixed === 'failure-then-allowed' ? [tool('edit', { path: before, oldText: 'missing', newText: 'changed' }), tool('write', { path: after, content: 'blocked' })]
        : [tool('write', { path: before, content: 'pending' }), tool('write', { path: after, content: 'blocked' })];
    faux.setResponses([message('{"kind":"personal"}'), message(calls), message('must not run')]);
    const result = await run({ approval });
    assert.equal(result.status, mixed === 'pending-then-allowed' ? 'approval_required' : 'failed');
    assert.equal(faux.state.callCount, 2); await assert.rejects(access(after));
    if (mixed !== 'allowed-then-unknown') await assert.rejects(access(before));
  }));
}
test('invalid classification and attempted tools in public classification fail closed', async () => {
  for (const response of [message('YES'), message('{"kind":"personal","approved":true}'), message([tool('bash', { command: 'false', timeout: 1 })])]) {
    await fixture(async ({ faux, run }) => {
      faux.setResponses([response, message('must not run')]);
      assert.equal((await run()).status, 'failed'); assert.equal(faux.state.callCount, 1);
    });
  }
});
test('aborted model turn fails closed; no tools are executed or automatic retries made', async () => fixture(async ({ faux, run }) => {
  const controller = new AbortController();
  faux.setResponses([async () => { controller.abort(); return message('{"kind":"reply"}'); }]);
  assert.equal((await run({ signal: controller.signal })).status, 'failed'); assert.equal(faux.state.callCount, 1);
}));
test('denied disclosure remains terminal even with a later granting adapter', async () => fixture(async ({ faux, run, store, config }) => {
  faux.setResponses([message('{"kind":"reply"}'), message('{"subject":"Draft","body":"Private"}')]);
  const result = await run();
  assert.equal((await reserveSend(store, result.requestId, config, approvalFixture(() => 'denied'))).status, 'failed');
  const grant = approvalFixture();
  assert.equal((await reserveSend(store, result.requestId, config, grant)).status, 'failed');
  assert.equal(grant.consumed.size, 0);
}));

test('read result survives Store reopen and edit resumes once without rereading changed context', async () => fixture(async ({ directory, store, faux, config, provider, run }) => {
  const target = join(directory, 'partial.txt'); const contextPath = join(directory, 'context.txt');
  await writeFile(target, 'READ_RESULT_MARKER'); await writeFile(contextPath, 'SAVED_CONTEXT_MARKER'); config.contextPaths = [contextPath];
  let approved = false;
  const approval = approvalFixture(proposal => proposal.binding.operation.name === 'edit' && !approved ? 'pending' : 'approved');
  faux.setResponses([message('{"kind":"personal"}'), message([tool('read', { path: target }), tool('edit', { path: target, oldText: 'READ_RESULT_MARKER', newText: 'edited' })])]);
  const first = await run({ approval }); assert.equal(first.status, 'approval_required');
  store.close(); await writeFile(contextPath, 'CHANGED_CONTEXT_MUST_NOT_APPEAR');
  const reopened = new Store(join(directory, 'state')); approved = true;
  try {
    faux.appendResponses([context => {
      const serialized = JSON.stringify(context);
      assert.ok(serialized.includes('READ_RESULT_MARKER')); assert.ok(serialized.includes('SAVED_CONTEXT_MARKER'));
      assert.ok(!serialized.includes('CHANGED_CONTEXT_MUST_NOT_APPEAR'));
      return message([tool('edit', { path: target, oldText: 'READ_RESULT_MARKER', newText: 'edited' })]);
    }, message('{"subject":"Done","body":"Edited once"}')]);
    const options = { store: reopened, id: first.requestId, config, provider, approval };
    assert.equal((await runMail(options)).status, 'reply_ready'); assert.equal(await readFile(target, 'utf8'), 'edited');
    const calls = faux.state.callCount; await runMail(options); assert.equal(faux.state.callCount, calls);
    assert.equal(reopened.completedTools(first.requestId).length, 2);
  } finally { reopened.close(); }
  // Fixture cleanup owns this Store handle; restore it after deliberately testing a restart.
  store.db = new Store(join(directory, 'state')).db;
}));

test('controlled native bash omits ambient env and abort waits until a pending command stops', async () => fixture(async ({ directory, faux, run }) => {
  const started = join(directory, 'started'); const late = join(directory, 'late');
  const controller = new AbortController();
  process.env.MAIL_AMBIENT_MARKER = 'must-not-inherit';
  faux.setResponses([message('{"kind":"personal"}'), message([tool('bash', { command: `test -z "$MAIL_AMBIENT_MARKER" && printf started > '${started}'; sleep 0.4; printf late > '${late}'`, timeout: 2 })])]);
  const polling = setInterval(async () => { try { await access(started); controller.abort(); } catch {} }, 5);
  try {
    assert.equal((await run({ signal: controller.signal })).status, 'failed');
    await access(started); await new Promise(resolve => setTimeout(resolve, 500)); await assert.rejects(access(late));
  } finally { clearInterval(polling); delete process.env.MAIL_AMBIENT_MARKER; }
}));

test('context rejects symlinks and special files without opening a blocking FIFO', async () => {
  for (const special of ['symlink', 'directory', 'fifo']) await fixture(async ({ directory, faux, config, run }) => {
    const path = join(directory, 'unsafe');
    if (special === 'symlink') { await writeFile(join(directory, 'regular'), 'private'); await symlink(join(directory, 'regular'), path); }
    else if (special === 'directory') await mkdir(path);
    else { const { execFileSync } = await import('node:child_process'); execFileSync('/run/current-system/sw/bin/mkfifo', [path]); }
    config.contextPaths = [path]; faux.setResponses([message('{"kind":"personal"}')]);
    const start = Date.now(); assert.equal((await run()).status, 'failed'); assert.ok(Date.now() - start < 2000);
    assert.equal(faux.state.callCount, 1);
  });
});

test('SDK draft disclosure is separately authorized exactly and interrupted sends cannot retry', async () => fixture(async ({ faux, run, store, config }) => {
  faux.setResponses([message('{"kind":"reply"}'), message('{"subject":"Draft","body":"Sensitive fixture"}')]);
  const result = await run(); assert.equal(result.status, 'reply_ready');
  const approval = approvalFixture();
  const reserved = await reserveSend(store, result.requestId, config, approval);
  assert.equal(reserved.status, 'send_reserved');
  const request = normalize(raw(), config);
  const expected = bindingFor(request, config, 'send', { sender: config.selfAddress, recipient: raw().from, subject: 'Re: Fixture', body: result.reply.body, bodyDigest: digest(result.reply.body) });
  assert.equal(reserved.reservation, digest(expected));
  assert.equal((await reserveSend(store, result.requestId, config, approval)).status, 'failed');
  assert.equal(finishSend(store, result.requestId, reserved.reservation, 'unknown').status, 'send_unknown');
}));

test('production CLI drives real SDK and HTTP owner approval without real credentials/model/SMTP', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'mail-production-smoke-'));
  const token = randomBytes(48).toString('base64url'); const password = randomBytes(32).toString('base64url');
  const app = createApprovalServer({ directory: join(directory, 'site'), apiToken: token, ownerHash: await passwordHash(password), port: 0 });
  const endpoint = await app.listen();
  const faux = ai.fauxProvider({ provider: 'openai-codex', models: [{ id: 'gpt-6.1-sol', contextWindow: 32768, maxTokens: 4096 }] });
  const modelRuntime = await sdk.ModelRuntime.create({ credentials: new ai.InMemoryCredentialStore(), modelsPath: null, refreshOnCreate: false, allowModelNetwork: false }); modelRuntime.registerNativeProvider(faux.provider);
  const config = { mailbox: 'fixture@example.test', selfAddress: 'assistant@example.test', provider: 'openai-codex/gpt-6.1-sol', scope: 'test', cwd: directory, contextPaths: [] };
  const recipientPolicyFile = join(directory, 'recipients.json');
  await writeFile(recipientPolicyFile, JSON.stringify({ version: 1, allowedRecipients: ['sender@example.test', 'hidden-policy-entry@example.test'], defaultRecipient: 'sender@example.test' }), { mode: 0o600 });
  const host = { config, stateDirectory: join(directory, 'runner'), authPath: '/NEVER_READ', tokenFile: '/NEVER_READ', recipientPolicyFile, endpoint: 'http://127.0.0.1:8765' };
  const deps = { approval: createApprovalAdapter({ token, endpoint }), provider: async () => ({ modelRuntime, model: faux.getModel() }) };
  const cli = args => productionCli(args, host, deps);
  const http = (path, cookie, form) => fetch(endpoint + path, { redirect: 'manual', method: form ? 'POST' : 'GET', headers: { ...(cookie ? { Cookie: cookie } : {}), ...(form ? { Origin: endpoint, 'Content-Type': 'application/x-www-form-urlencoded' } : {}) }, body: form ? new URLSearchParams(form).toString() : undefined });
  try {
    faux.setResponses([
      context => { assert.ok(!JSON.stringify(context).includes('hidden-policy-entry@example.test')); return message('{"kind":"reply"}'); },
      context => { assert.ok(!JSON.stringify(context).includes('hidden-policy-entry@example.test')); return message('{"subject":"Draft","body":"Full production fixture private send preview"}'); },
    ]);
    const result = await cli(['process', encodeEnvelope(raw())]); assert.equal(result.status, 'reply_ready'); assert.equal(faux.state.callCount, 2);
    assert.equal((await cli(['resume', result.requestId])).status, 'reply_ready'); assert.equal(faux.state.callCount, 2);
    assert.equal((await cli(['status', result.requestId])).status, 'reply_ready');
    const reserve = encodeEnvelope({ requestId: result.requestId });
    assert.equal((await cli(['send-reserve', reserve])).status, 'approval_required');
    const pre = await http('/login'); const preCookie = pre.headers.get('set-cookie').split(';')[0]; const preCsrf = /name="csrf" value="([a-f0-9]+)"/.exec(await pre.text())[1];
    const logged = await http('/login', preCookie, { csrf: preCsrf, username: 'lucky', password }); assert.equal(logged.status, 303); const cookie = logged.headers.get('set-cookie').split(';')[0];
    const dashboard = await (await http('/', cookie)).text(); assert.match(dashboard, /Full production fixture private send preview/);
    const csrf = /name="csrf" value="([a-f0-9]+)"/.exec(dashboard)[1]; const proposal = app.store.db.prepare('SELECT id FROM approval_proposals').get().id;
    assert.equal((await http('/decide', cookie, { csrf, id: proposal, decision: 'approved' })).status, 303);
    const approved = await cli(['send-reserve', reserve]); assert.equal(approved.status, 'send_reserved'); assert.equal(approved.version, 1); assert.equal(approved.reason, null); assert.deepEqual(approved.reply, result.reply);
    const finish = encodeEnvelope({ requestId: result.requestId, reservation: approved.reservation, outcome: 'unknown' });
    assert.equal((await cli(['send-finish', finish])).status, 'send_unknown');
    await assert.rejects(cli(['send-finish', finish])); assert.equal((await cli(['send-reserve', reserve])).status, 'failed'); assert.equal(faux.state.callCount, 2);
    faux.appendResponses([
      context => { assert.ok(!JSON.stringify(context).includes('hidden-policy-entry@example.test')); return message('{"kind":"reply"}'); },
      context => { assert.ok(!JSON.stringify(context).includes('hidden-policy-entry@example.test')); return message('{"subject":"Draft","body":"Answer for owner review"}'); },
    ]);
    const outside = await cli(['process', encodeEnvelope({ ...raw(), from: 'outside@example.test', sentAt: '2026-10-31T19:30:20.000Z' })]);
    assert.equal(outside.status, 'reply_ready'); assert.equal(outside.reply.to, 'sender@example.test');
    assert.match(outside.reply.body, /Original sender \(unverified From\): outside@example.test/);
    assert.match(outside.reply.body, /2026-10-31T19:30:20.000Z/); assert.match(outside.reply.body, /Answer for owner review/);
    assert.equal((await cli(['send-reserve', encodeEnvelope({ requestId: outside.requestId })])).status, 'approval_required');
    assert.equal(faux.state.callCount, 4);
  } finally { await app.close(); await rm(directory, { recursive: true, force: true }); }
});

const safeOperations = () => [{ name: 'weather', args: { city: 'Piracicaba', country: 'BR' } }, { name: 'machine_status', args: {} }];
const safeClassification = () => JSON.stringify({ kind: 'safe', operations: safeOperations() });
function enableSafe(config) {
  config.automaticReplies = true; config.safeCapabilities = ['weather', 'machine_status'];
  config.recipientPolicy = { version: 1, allowedRecipients: ['sender@example.test', 'hidden-owner@example.test'], defaultRecipient: 'sender@example.test', safeCapabilities: [...config.safeCapabilities], automaticReplies: true };
}
function safeMocks({ onFetch, failure } = {}) {
  const calls = [];
  const safeDependencies = {
    async fetchImpl(url, options) {
      calls.push(url.hostname); assert.equal(options.redirect, 'error'); await onFetch?.();
      if (failure === 'network') throw new Error('fixture offline');
      if (failure === 'oversized') return new Response('x'.repeat(32769), { headers: { 'Content-Type': 'application/json' } });
      return Response.json(url.hostname === 'geocoding-api.open-meteo.com' ? { results: [{ name: 'Piracicaba', latitude: -22.72528, longitude: -47.64917, country_code: 'BR' }] }
        : { timezone: 'GMT', utc_offset_seconds: 0, current: { time: new Date().toISOString().slice(0, 16), temperature_2m: 25, apparent_temperature: 26, relative_humidity_2m: 60, precipitation: 0, weather_code: 1, wind_speed_10m: 8 } });
    },
    os: { availableMemory: () => 4000, totalmem: () => 8000, cpus: () => [{}, {}, {}, {}], uptime: () => 12345, loadavg: () => [0.1, 0.2, 0.3] },
    async statfsImpl(path) { calls.push(path); assert.equal(path, '/persist'); return { bavail: 20, blocks: 100, bsize: 4096 }; },
  };
  return { calls, safeDependencies };
}

test('real SDK owner weather AND health collect fixed live snapshots, zero approvals/context/tools, then auto-reserve once', async () => fixture(async ({ directory, faux, config, run, store }) => {
  enableSafe(config); config.contextPaths = [join(directory, 'NEVER_READ')];
  const approval = approvalFixture(() => 'pending'), mock = safeMocks();
  const input = { ...raw(), body: 'Hows weather in Piracicaba? Also how is machine running?' };
  faux.setResponses([
    context => { assert.doesNotMatch(JSON.stringify(context), /hidden-owner@example.test/); return message(safeClassification()); },
    context => {
      const prompt = JSON.stringify(context);
      for (const value of ['temperatureC', '25', 'logicalCpus', 'Sora', '12345', 'model estimate', 'fetchedAt', 'UTC']) assert.ok(prompt.includes(value));
      assert.doesNotMatch(prompt, /hidden-owner@example.test/);
      return message('{"subject":"Weather and health","body":"Open-Meteo estimates 25 C in Piracicaba. Sora has four logical CPUs, 12345 seconds uptime, and low aggregate load."}');
    },
  ]);
  const result = await run({ raw: input, approval, safeDependencies: mock.safeDependencies, inspect: ({ session, loader }) => { assert.deepEqual(session.getActiveToolNames(), []); assert.deepEqual(loader.getAgentsFiles().agentsFiles, []); } });
  assert.equal(result.status, 'reply_ready'); assert.deepEqual(mock.calls, ['geocoding-api.open-meteo.com', 'api.open-meteo.com', '/persist']);
  assert.equal(approval.proposals.size, 0); assert.equal(approval.consumed.size, 0); assert.equal(store.get(result.requestId).context, null);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE json_extract(binding,'$.phase') IN ('tool','investigate')").get().n, 0);
  store.close(); const reopened = new Store(join(directory, 'state'));
  try {
    const resumed = await runMail({ store: reopened, id: result.requestId, config, approval, provider: () => { throw new Error('must not rerun'); } });
    assert.equal(resumed.status, 'reply_ready');
    const reserved = await reserveSend(reopened, result.requestId, config, approval); assert.equal(reserved.status, 'send_reserved');
    assert.equal((await reserveSend(reopened, result.requestId, config, approval)).status, 'failed');
    assert.equal(finishSend(reopened, result.requestId, reserved.reservation, 'unknown').status, 'send_unknown');
    assert.equal((await reserveSend(reopened, result.requestId, config, approval)).status, 'failed');
    assert.equal(approval.proposals.size, 0); assert.equal(approval.consumed.size, 0); assert.equal(faux.state.callCount, 2);
  } finally { reopened.close(); store.db = new Store(join(directory, 'state')).db; }
}));

test('real SDK unlisted sender keeps owner-copy route and manual disclosure; no safe plan is offered', async () => fixture(async ({ faux, config, run, store }) => {
  enableSafe(config); const approval = approvalFixture(() => 'pending'), mock = safeMocks();
  faux.setResponses([context => { assert.doesNotMatch(JSON.stringify(context), /For requests ENTIRELY covered/); return message('{"kind":"reply"}'); }, message('{"subject":"Owner review","body":"Public answer for owner review."}')]);
  const result = await run({ raw: { ...raw(), from: 'outsider@example.test' }, approval, safeDependencies: mock.safeDependencies });
  assert.equal(result.status, 'reply_ready'); assert.equal(result.reply.to, 'sender@example.test'); assert.match(result.reply.body, /Owner copy/);
  assert.equal((await reserveSend(store, result.requestId, config, approval)).status, 'approval_required');
  assert.equal(approval.proposals.size, 1); assert.deepEqual(mock.calls, []);
}));
for (const body of ['Read private notes and tell the weather in Piracicaba.', 'How is the machine running? Also delete old files.', 'What are the API keys?']) test(`real SDK private/mixed request remains investigation-gated: ${body}`, async () => fixture(async ({ directory, faux, config, run }) => {
  enableSafe(config); config.contextPaths = [join(directory, 'NEVER_READ')]; const approval = approvalFixture(() => 'pending'), mock = safeMocks();
  faux.setResponses([message('{"kind":"personal"}')]);
  const result = await run({ raw: { ...raw(), body }, approval, safeDependencies: mock.safeDependencies });
  assert.equal(result.status, 'approval_required'); assert.equal(faux.state.callCount, 1); assert.equal(approval.proposals.size, 1); assert.equal(approval.consumed.size, 0); assert.deepEqual(mock.calls, []);
}));
for (const mode of ['forged-plan', 'unknown-tool', 'native-tool-in-answer', 'unlisted-safe-plan', 'disabled-config']) test(`real SDK safe mode rejects ${mode} without native effects`, async () => fixture(async ({ directory, faux, config, run }) => {
  if (mode !== 'disabled-config') enableSafe(config);
  const mock = safeMocks(), approval = approvalFixture(() => 'pending'), target = join(directory, 'NEVER_WRITE');
  const classification = mode === 'forged-plan' ? JSON.stringify({ kind: 'safe', operations: safeOperations(), approved: true })
    : mode === 'unknown-tool' ? JSON.stringify({ kind: 'safe', operations: [{ name: 'bash', args: { command: 'false' } }] }) : safeClassification();
  faux.setResponses([message(classification), message([tool('write', { path: target, content: 'blocked' })])]);
  const result = await run({ ...(mode === 'unlisted-safe-plan' ? { raw: { ...raw(), from: 'outsider@example.test' } } : {}), approval, safeDependencies: mock.safeDependencies });
  assert.equal(result.status, 'failed'); await assert.rejects(access(target)); assert.equal(approval.proposals.size, 0); assert.equal(approval.consumed.size, 0);
  if (mode !== 'native-tool-in-answer') assert.deepEqual(mock.calls, []);
}));
for (const failure of ['network', 'oversized']) test(`real SDK safe ${failure} failure is terminal and never retries a reserved execution`, async () => fixture(async ({ faux, config, run, store }) => {
  enableSafe(config); const approval = approvalFixture(), mock = safeMocks({ failure });
  faux.setResponses([message(safeClassification()), message('must not call')]);
  const result = await run({ approval, safeDependencies: mock.safeDependencies });
  assert.equal(result.status, 'failed'); assert.equal(faux.state.callCount, 1); assert.equal(mock.calls.length, 1);
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='unknown'").get().n, 1);
  await run({ raw: undefined, id: result.requestId, approval, safeDependencies: mock.safeDependencies });
  assert.equal(faux.state.callCount, 1); assert.equal(mock.calls.length, 1); assert.equal(approval.proposals.size, 0);
}));
for (const phase of ['classification', 'tool', 'answer', 'send']) test(`real SDK policy revocation during ${phase} prevents automatic delivery`, async () => fixture(async ({ faux, config, run, store }) => {
  enableSafe(config); let revoked = false;
  const currentConfig = () => revoked ? { ...config, recipientPolicy: { version: 1, allowedRecipients: ['hidden-owner@example.test'], defaultRecipient: 'hidden-owner@example.test' } } : config;
  const approval = approvalFixture(() => 'pending'), mock = safeMocks({ onFetch: () => { if (phase === 'tool') revoked = true; } });
  faux.setResponses([() => { if (phase === 'classification') revoked = true; return message(safeClassification()); }, () => { if (phase === 'answer') revoked = true; return message('{"subject":"Collected","body":"Only bounded safe results."}'); }]);
  const result = await run({ approval, currentConfig, safeDependencies: mock.safeDependencies });
  if (phase === 'send') {
    assert.equal(result.status, 'reply_ready'); revoked = true;
    assert.equal((await reserveSend(store, result.requestId, config, approval, null, { currentConfig })).status, 'failed');
  } else assert.equal(result.status, 'failed');
  assert.equal(approval.proposals.size, 0); assert.equal(approval.consumed.size, 0);
}));

test('real SDK disallowed capability plan falls back to investigation approval, never native authority', async () => fixture(async ({ faux, config, run }) => {
  enableSafe(config); config.safeCapabilities = ['weather'];
  const approval = approvalFixture(() => 'pending'), mock = safeMocks();
  faux.setResponses([message(safeClassification())]);
  const result = await run({ approval, safeDependencies: mock.safeDependencies });
  assert.equal(result.status, 'approval_required'); assert.deepEqual(mock.calls, []); assert.equal(approval.proposals.size, 1); assert.equal(approval.consumed.size, 0);
}));

test('real SDK resumed safe request replays completed exact snapshots without fetching again', async () => fixture(async ({ faux, config, run, store }) => {
  enableSafe(config);
  const request = normalize(raw(), config); store.claim(request);
  const plan = { kind: 'safe', operations: [{ name: 'machine_status', args: {} }] };
  const snapshot = { machine: 'Sora', collectedAt: '2000-01-01T00:00:00.000Z', uptimeSeconds: 789, logicalCpus: 4, loadAverage: [0.1, 0.2, 0.3], ramAvailableBytes: 4000, ramTotalBytes: 8000, diskAvailableBytes: 2000, diskTotalBytes: 10000 };
  store.db.prepare('UPDATE requests SET kind=? WHERE id=?').run('safe', request.id);
  for (const [binding, result] of [[bindingFor(request, config, 'safe_plan', plan), null], [bindingFor(request, config, 'safe_tool', { planDigest: digest(plan), ...plan.operations[0] }), snapshot]]) {
    const op = store.operation(binding); store.transition(op.key, 'pending', 'executing', policyGrant(binding)); new Gate(store, null).complete(binding, true, result);
  }
  faux.setResponses([context => { assert.ok(JSON.stringify(context).includes('789')); return message('{"subject":"Health","body":"Saved Sora snapshot: uptime 789 seconds."}'); }]);
  const result = await run({ raw: undefined, id: request.id, safeDependencies: { statfsImpl: () => { throw new Error('must not execute'); } } });
  assert.equal(result.status, 'reply_ready'); assert.equal(faux.state.callCount, 1);
  const approval = approvalFixture(() => 'pending');
  assert.equal((await reserveSend(store, request.id, config, approval)).status, 'approval_required');
  await run({ raw: undefined, id: request.id, safeDependencies: { statfsImpl: () => { throw new Error('must not re-execute'); } } });
  assert.equal(faux.state.callCount, 1); assert.equal(approval.proposals.size, 1); assert.equal(approval.consumed.size, 0);
}));

test('real SDK owner public reply automatic mode cannot override an earlier manual denial', async () => fixture(async ({ faux, config, run, store }) => {
  enableSafe(config);
  faux.setResponses([message('{"kind":"reply"}'), message('{"subject":"Hello","body":"Public zero-tool reply."}')]);
  const result = await run(); assert.equal(result.status, 'reply_ready');
  config.automaticReplies = false;
  assert.equal((await reserveSend(store, result.requestId, config, approvalFixture(() => 'denied'))).status, 'failed');
  config.automaticReplies = true; const approval = approvalFixture();
  assert.equal((await reserveSend(store, result.requestId, config, approval)).status, 'failed'); assert.equal(approval.proposals.size, 0);
}));

const productionPolicyCases = [
  { phase: 'none', authority: 'enabled' },
  ...['recipient', 'off', 'missing', 'reduced'].flatMap(authority => ['classification', 'tool', 'answer', 'send'].map(phase => ({ phase, authority }))),
  ...['off', 'missing', 'reduced'].map(authority => ({ phase: 'initial', authority })),
];
for (const { phase, authority } of productionPolicyCases) test(`production CLI runtime authority ${authority} during ${phase} overrides pinned startup flags`, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'mail-production-safe-'));
  const faux = ai.fauxProvider({ provider: 'openai-codex', models: [{ id: 'gpt-6.1-sol', contextWindow: 32768, maxTokens: 4096 }] });
  const modelRuntime = await sdk.ModelRuntime.create({ credentials: new ai.InMemoryCredentialStore(), modelsPath: null, refreshOnCreate: false, allowModelNetwork: false }); modelRuntime.registerNativeProvider(faux.provider);
  const config = { mailbox: 'fixture', selfAddress: 'assistant@example.test', provider: 'openai-codex/gpt-6.1-sol', scope: 'test', cwd: directory, contextPaths: [] }; enableSafe(config);
  const recipientPolicyFile = join(directory, 'policy.json');
  const enabledPolicy = config.recipientPolicy;
  const changedPolicy = { ...enabledPolicy };
  if (authority === 'recipient') { changedPolicy.allowedRecipients = ['hidden-owner@example.test']; changedPolicy.defaultRecipient = 'hidden-owner@example.test'; }
  if (authority === 'off') changedPolicy.automaticReplies = false;
  if (authority === 'missing') { delete changedPolicy.automaticReplies; delete changedPolicy.safeCapabilities; }
  if (authority === 'reduced') changedPolicy.safeCapabilities = ['weather'];
  await writeFile(recipientPolicyFile, JSON.stringify(phase === 'initial' ? changedPolicy : enabledPolicy), { mode: 0o600 }); delete config.recipientPolicy;
  // Intentionally leave stale startup flags TRUE/full: runtime policy must override them on every reload.
  const revoke = () => writeFile(recipientPolicyFile, JSON.stringify(changedPolicy));
  const host = { config, stateDirectory: join(directory, 'state'), authPath: '/NEVER_READ', tokenFile: '/NEVER_READ', recipientPolicyFile, endpoint: 'http://127.0.0.1:8765' };
  const approval = approvalFixture(() => 'pending'), mock = safeMocks({ onFetch: () => phase === 'tool' ? revoke() : undefined });
  const cli = args => productionCli(args, host, { approval, provider: async () => ({ modelRuntime, model: faux.getModel() }), safeDependencies: mock.safeDependencies });
  try {
    faux.setResponses([async context => {
      const prompt = JSON.stringify(context);
      assert.doesNotMatch(prompt, /hidden-owner@example.test|allowedRecipients|defaultRecipient/);
      if (phase === 'initial' && authority !== 'reduced') {
        assert.doesNotMatch(prompt, /For requests ENTIRELY covered/);
        return message('{"kind":"reply"}');
      }
      if (phase === 'initial') {
        assert.match(prompt, /Allowed fixed capability names:.*weather/);
        assert.doesNotMatch(prompt, /Allowed fixed capability names:.*machine_status/);
      }
      if (phase === 'classification') await revoke();
      return message(safeClassification());
    }, async context => {
      assert.doesNotMatch(JSON.stringify(context), /hidden-owner@example.test|allowedRecipients|defaultRecipient/);
      if (phase === 'answer') await revoke();
      return message('{"subject":"Results","body":"Open-Meteo model estimate: 25 C. Sora: four logical CPUs and low load."}');
    }]);
    const result = await cli(['process', encodeEnvelope(raw())]);
    const reducedClassification = authority === 'reduced' && ['initial', 'classification'].includes(phase);
    if (reducedClassification) assert.equal(result.status, 'approval_required');
    else if (['classification', 'tool', 'answer'].includes(phase)) assert.equal(result.status, 'failed');
    else {
      assert.equal(result.status, 'reply_ready'); if (phase === 'send') await revoke();
      const reserve = encodeEnvelope({ requestId: result.requestId });
      const reserved = await cli(['send-reserve', reserve]);
      assert.equal(reserved.status, phase === 'none' ? 'send_reserved' : authority === 'recipient' ? 'failed' : 'approval_required');
      if (phase === 'none') {
        assert.deepEqual(reserved.reply, result.reply); assert.equal(reserved.reason, null); assert.equal(reserved.version, 1);
        assert.equal((await cli(['send-reserve', reserve])).status, 'failed');
        assert.equal((await cli(['send-finish', encodeEnvelope({ requestId: result.requestId, reservation: reserved.reservation, outcome: 'unknown' })])).status, 'send_unknown');
      }
    }
    const manual = reducedClassification || (['initial', 'send'].includes(phase) && authority !== 'recipient');
    assert.equal(approval.proposals.size, manual ? 1 : 0); assert.equal(approval.consumed.size, 0);
    if (phase === 'initial' || phase === 'classification') assert.deepEqual(mock.calls, []);
    assert.equal(config.automaticReplies, true); assert.deepEqual(config.safeCapabilities, ['weather', 'machine_status']);
    const check = new Store(host.stateDirectory);
    try {
      assert.doesNotMatch(JSON.stringify(check.db.prepare('SELECT binding,result FROM operations').all()), /hidden-owner@example.test|allowedRecipients|defaultRecipient/);
      if (phase !== 'none') assert.equal(check.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='executing' AND json_extract(binding,'$.phase')='send'").get().n, 0);
    } finally { check.close(); }
  } finally { await rm(directory, { recursive: true, force: true }); }
});
