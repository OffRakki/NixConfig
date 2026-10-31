import assert from 'node:assert/strict';
import { access, mkdir, mkdtemp, readFile, rm, writeFile, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { randomBytes } from 'node:crypto';
import { createApprovalServer, passwordHash } from '../mail/approval-server.mjs';
import { createApprovalAdapter, productionCli } from '../mail/production.mjs';
import { bindingFor, digest, encodeEnvelope, finishSend, normalize, reserveSend, Store } from '../mail/core.mjs';
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
  const host = { config, stateDirectory: join(directory, 'runner'), authPath: '/NEVER_READ', tokenFile: '/NEVER_READ', endpoint: 'http://127.0.0.1:8765' };
  const deps = { approval: createApprovalAdapter({ token, endpoint }), provider: async () => ({ modelRuntime, model: faux.getModel() }) };
  const cli = args => productionCli(args, host, deps);
  const http = (path, cookie, form) => fetch(endpoint + path, { redirect: 'manual', method: form ? 'POST' : 'GET', headers: { ...(cookie ? { Cookie: cookie } : {}), ...(form ? { Origin: endpoint, 'Content-Type': 'application/x-www-form-urlencoded' } : {}) }, body: form ? new URLSearchParams(form).toString() : undefined });
  try {
    faux.setResponses([message('{"kind":"reply"}'), message('{"subject":"Draft","body":"Full production fixture private send preview"}')]);
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
  } finally { await app.close(); await rm(directory, { recursive: true, force: true }); }
});
