import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, stat, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { bindingFor, canonical, classify, decodeEnvelope, digest, encodeEnvelope, finishSend, Gate, normalize, reserveSend, Store, unconfiguredApproval, formatReply } from '../mail/core.mjs';
import { cli, runMail } from '../mail/runner.mjs';

export const rawFixture = () => ({ version: 1, messageId: '<fixture@example.test>', from: 'sender@example.test', subject: 'Fixture', body: 'Untrusted request', autoSubmitted: 'no', precedence: '', attachments: [] });
export const configFixture = cwd => ({ mailbox: 'trusted-fixture', selfAddress: 'assistant@example.test', provider: 'faux/faux', scope: 'fixture-only', cwd, contextPaths: [] });
export function testApproval(decide = () => 'approved') {
  const proposals = new Map();
  const consumed = new Set();
  return { configured: true, proposals, consumed,
    async createProposal(proposal) { const id = proposal.digest; proposals.set(id, proposal); return id; },
    async fetchDecision(id) {
      const proposal = proposals.get(id);
      const mode = decide(proposal);
      if (mode && typeof mode === 'object') return mode;
      if (mode === 'throw') throw new Error('fixture failure');
      if (mode !== 'approved') return { status: mode };
      return { status: 'approved', digest: proposal.digest, grantId: proposal.digest, expiresAt: Date.now() + 60000 };
    },
    async consumeGrant({ grantId, digest: key }) { if (grantId !== key || consumed.has(grantId)) return false; consumed.add(grantId); return true; },
  };
}
async function fixture(fn) {
  const directory = await mkdtemp(join(tmpdir(), 'mail-unit-'));
  const store = new Store(directory);
  try { await fn({ directory, store, config: configFixture(directory) }); }
  finally { store.close(); await rm(directory, { recursive: true, force: true }); }
}

test('canonical transport is closed, deterministic, bounded and unambiguous', () => {
  assert.equal(canonical({ z: 1, a: 2 }), '{"a":2,"z":1}');
  assert.deepEqual(decodeEnvelope(encodeEnvelope(rawFixture())), rawFixture());
  for (const source of ['{} {}', '{ "a":1}', '{"a":1,"a":2}', '{"__proto__":1}', '{"a":1}\n']) assert.throws(() => decodeEnvelope(Buffer.from(source).toString('base64')));
  for (const source of ['', 'a', 'abcd;whoami', 'e30=\n', '_w==', '/x==']) assert.throws(() => decodeEnvelope(source));
  assert.throws(() => decodeEnvelope(Buffer.alloc(140000, 'x').toString('base64')));
  assert.throws(() => normalize({ ...rawFixture(), approved: true }, configFixture('/tmp')));
});
test('classifier accepts only exact typed kinds, never exact-YES or invalid output', () => {
  for (const kind of ['reply', 'personal', 'reject']) assert.equal(classify(JSON.stringify({ kind })), kind);
  for (const output of ['YES', 'false', 'null', '[]', '{"kind":"YES"}', '{"kind":"personal","approved":true}', '```json\n{"kind":"reply"}\n```']) assert.throws(() => classify(output));
});
test('identity fallback isolates content and trusted mailbox without trusting From or message IDs', () => {
  const config = configFixture('/tmp');
  const a = normalize(rawFixture(), config);
  assert.equal(a.id, normalize(rawFixture(), config).id);
  assert.notEqual(a.id, normalize({ ...rawFixture(), body: 'Different content, same Message-ID' }, config).id);
  assert.notEqual(a.id, normalize(rawFixture(), { ...config, mailbox: 'other' }).id);
  assert.match(normalize({ ...rawFixture(), messageId: null }, config).id, /^[a-f0-9]{64}$/);
  for (const messageId of ['../../bad', '<bad>', '<bad\n@host>', 42]) assert.throws(() => normalize({ ...rawFixture(), messageId }, config));
  assert.throws(() => normalize({ ...rawFixture(), from: 'bad@example.test\nBcc: victim@example.test' }, config));
});
test('loop suppression and attachments fail closed without filesystem extraction', () => {
  const config = configFixture('/tmp');
  for (const change of [{ from: config.selfAddress }, { autoSubmitted: 'auto-replied' }, { precedence: 'bulk' }]) assert.equal(normalize({ ...rawFixture(), ...change }, config).rejection, 'loop_suppressed');
  const attachment = { name: '../../same.txt', size: 5, mime: 'text/plain' };
  assert.equal(normalize({ ...rawFixture(), attachments: [attachment, attachment] }, config).rejection, 'attachments_unsupported');
  assert.throws(() => normalize({ ...rawFixture(), attachments: Array(9).fill(attachment) }, config));
  assert.throws(() => normalize({ ...rawFixture(), attachments: [{ ...attachment, size: 10485761 }] }, config));
});
test('state is private and refuses unsafe directories and symlinks', async () => fixture(async ({ directory }) => {
  assert.equal((await stat(directory)).mode & 0o777, 0o700);
  assert.equal((await stat(join(directory, 'state.sqlite'))).mode & 0o777, 0o600);
  const insecure = join(directory, 'insecure');
  const other = new Store(insecure); other.close();
  await chmod(insecure, 0o755); assert.throws(() => new Store(insecure), /permissions/);
  const link = join(directory, 'link'); await symlink(directory, link); assert.throws(() => new Store(link));
}));
test('unique immutable claims, concurrent owners and interrupted runs never auto-retry', async () => fixture(async ({ directory, store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  assert.throws(() => store.claim({ ...request, source: 'changed' }), /immutable/);
  assert.ok(store.begin(request.id));
  const second = new Store(directory);
  try { assert.equal(second.begin(request.id), null); assert.equal(second.result(request.id).reason, 'run_in_progress_or_uncertain'); }
  finally { second.close(); }
  assert.equal(store.begin(request.id), null);
}));
test('unconfigured runtime cannot call a provider, load context or accept caller approval', async () => fixture(async ({ store }) => {
  const result = await runMail({ store, raw: { ...rawFixture(), approved: true }, provider: () => { throw new Error('must not run'); } });
  assert.equal(result.reason, 'UNCONFIGURED'); assert.equal(result.reply, null);
}));
test('default approval refuses all operations regardless email and environment', async () => fixture(async ({ store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const gate = new Gate(store, unconfiguredApproval);
  assert.equal(await gate.authorize(bindingFor(request, config, 'tool', { approved: true })), false);
  assert.equal(gate.reason, 'approval_backend_unconfigured');
}));
test('approval rejects pending/denied/unknown/expired/mismatched/forged/failed decisions', async () => fixture(async ({ store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const modes = ['pending', 'denied', 'unknown', 'throw', { status: 'approved', digest: 'bad', grantId: 'fixture', expiresAt: Date.now() + 60000 },
    { status: 'approved', digest: 'bad', grantId: 'fixture', expiresAt: 0 }, { status: 'approved', approved: true }];
  for (const [index, mode] of modes.entries()) {
    const adapter = testApproval(() => mode); const gate = new Gate(store, adapter);
    assert.equal(await gate.authorize(bindingFor(request, config, 'tool', { index })), false);
    assert.equal(adapter.consumed.size, 0);
  }
}));
test('exact-operation grants bind cwd/provider/scope/phase/args and consume once before effects', async () => fixture(async ({ store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const binding = bindingFor(request, config, 'tool', { name: 'write', args: { path: 'fixture', content: 'one' } });
  const adapter = testApproval(); const gate = new Gate(store, adapter);
  assert.equal(await gate.authorize(binding), true);
  assert.equal(store.operation(binding).state, 'executing'); assert.equal(adapter.consumed.size, 1);
  gate.complete(binding, true);
  assert.equal(await new Gate(store, adapter).authorize(binding), false);
  for (const changed of [{ ...binding, cwd: '/elsewhere' }, { ...binding, provider: 'other/model' }, { ...binding, phase: 'send' }, { ...binding, operation: { ...binding.operation, args: { path: 'fixture', content: 'two' } } }]) assert.notEqual(digest(changed), digest(binding));
}));
test('concurrent reservations and restart after consumption have at most one effect', async () => fixture(async ({ directory, store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const binding = bindingFor(request, config, 'tool', { name: 'bash', args: { command: 'fixture', timeout: 2 } });
  const adapter = testApproval(); const second = new Store(directory);
  try {
    const results = await Promise.all([new Gate(store, adapter).authorize(binding), new Gate(second, adapter).authorize(binding)]);
    assert.equal(results.filter(Boolean).length, 1); assert.equal(adapter.consumed.size, 1);
    assert.equal(await new Gate(second, adapter).authorize(binding), false);
  } finally { second.close(); }
}));
test('failed consume and uncertain reservations cannot be retried', async () => fixture(async ({ store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const binding = bindingFor(request, config, 'tool', { name: 'edit' });
  const adapter = testApproval(); adapter.consumeGrant = async () => false;
  assert.equal(await new Gate(store, adapter).authorize(binding), false);
  assert.equal(store.operation(binding).state, 'reserving');
  assert.equal(await new Gate(store, testApproval()).authorize(binding), false);
}));
test('abort bounds a non-responsive approval adapter and prevents effects', async () => fixture(async ({ store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const controller = new AbortController();
  const adapter = testApproval(); adapter.createProposal = () => new Promise(() => {});
  const gate = new Gate(store, adapter, controller.signal);
  const pending = gate.authorize(bindingFor(request, config, 'tool', { name: 'write' }));
  controller.abort(); assert.equal(await pending, false); assert.equal(adapter.consumed.size, 0);
}));
test('send binds exact recipient/body and reserves before SMTP; unknown outcome is not retried', async () => fixture(async ({ store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const owner = store.begin(request.id);
  store.finish(request.id, owner, 'reply_ready', null, { to: request.input.from, subject: 'Draft', body: 'Private fixture' });
  assert.equal((await reserveSend(store, request.id, config)).reason, 'approval_backend_unconfigured');
  const adapter = testApproval();
  const reservation = await reserveSend(store, request.id, config, adapter);
  assert.equal(reservation.status, 'send_reserved');
  const binding = adapter.proposals.get(reservation.reservation).binding;
  assert.equal(binding.operation.recipient, request.input.from); assert.equal(binding.operation.bodyDigest, digest('Private fixture'));
  assert.equal(finishSend(store, request.id, reservation.reservation, 'unknown').status, 'send_unknown');
  assert.equal((await reserveSend(store, request.id, config, adapter)).status, 'failed');
  assert.throws(() => finishSend(store, request.id, reservation.reservation, 'sent'));
}));
test('CLI uses strict transport and has no approval/provider/adapter loading flags', async () => fixture(async ({ directory }) => {
  assert.equal((await cli(['--help'])).status, 'UNCONFIGURED');
  assert.equal((await cli(['process', encodeEnvelope(rawFixture()), directory])).reason, 'UNCONFIGURED');
  await assert.rejects(cli(['process', 'no; bash', directory]));
  await assert.rejects(cli(['--approved', 'true']));
  await assert.rejects(cli(['process', encodeEnvelope({ ...rawFixture(), approved: true }), directory]));
  await assert.rejects(cli(['process', encodeEnvelope({ ...rawFixture(), body: 42 }), directory]));
  await assert.rejects(cli(['send-finish', encodeEnvelope({ requestId: 'a'.repeat(64), reservation: 'invalid', outcome: 'sent' })]));
}));

test('v1 ledger migrates without replaying consumed effects or inventing lost results', async () => fixture(async ({ directory, store, config }) => {
  const request = normalize(rawFixture(), config); store.claim(request);
  const binding = bindingFor(request, config, 'tool', { name: 'read', args: { path: '/fixture' } });
  const gate = new Gate(store, testApproval()); assert.equal(await gate.authorize(binding), true); gate.complete(binding, true);
  store.db.exec('ALTER TABLE operations DROP COLUMN result; PRAGMA user_version=1;');
  const migrated = new Store(directory);
  try {
    assert.equal(migrated.db.prepare('PRAGMA user_version').get().user_version, 2);
    assert.equal(await new Gate(migrated, testApproval()).authorize(binding), false);
    assert.throws(() => migrated.completedTools(request.id), /unavailable/);
  } finally { migrated.close(); }
  store.db.exec('PRAGMA user_version=99'); assert.throws(() => new Store(directory), /unsupported/);
}));
test('deterministic Re subject and bounded original quote precede disclosure hashing', () => {
  const request = normalize(rawFixture(), configFixture('/tmp'));
  const reply = formatReply(request, { subject: 'model ignored', body: 'Draft' });
  assert.equal(reply.subject, 'Re: Fixture'); assert.match(reply.body, /> Untrusted request$/);
  assert.equal(formatReply({ ...request, input: { ...request.input, subject: 'Re: Existing', body: 'x'.repeat(3000) } }, { subject: 'ignored', body: 'Draft' }).subject, 'Re: Existing');
  assert.match(formatReply({ ...request, input: { ...request.input, body: 'x'.repeat(3000) } }, { subject: 'ignored', body: 'Draft' }).body, /\[original truncated\]/);
});

test('candidate graph is inert, unbound, has no legacy identifiers, and validates runner JSON', async () => {
  const candidate = JSON.parse(await readFile(new URL('../mail/Mail.candidate.json', import.meta.url), 'utf8'));
  assert.equal(candidate.active, false); assert.equal(candidate.id, undefined); assert.equal(candidate.meta.approvalBackend, 'UNCONFIGURED');
  assert.equal(candidate.nodes.some(node => node.credentials || node.webhookId), false);
  for (const node of candidate.nodes.filter(node => ['n8n-nodes-base.emailReadImap', 'n8n-nodes-base.ssh', 'n8n-nodes-base.emailSend'].includes(node.type))) {
    assert.equal(node.disabled, true); assert.notEqual(node.retryOnFail, true);
  }
  assert.equal(candidate.nodes.find(node => node.name === 'IMAP UNBOUND').parameters.format, 'resolved');
  const normalizeCode = candidate.nodes.find(node => node.name === 'Normalize envelope').parameters.jsCode;
  const normalizeNode = new Function('$input', 'Buffer', normalizeCode);
  const input = { json: { from: { value: [{ address: 'sender@example.test' }] }, subject: 'Test', text: 'Body', messageId: '<fixture@example.test>', headers: {} } };
  const result = normalizeNode({ all: () => [input] }, Buffer)[0].json;
  assert.equal(decodeEnvelope(result.payload).body, 'Body');
  assert.throws(() => normalizeNode({ all: () => [{ ...input, binary: { attachment0: {} } }] }, Buffer), /attachments_unsupported/);
  const validateCode = candidate.nodes.find(node => node.name === 'Validate strict result').parameters.jsCode;
  const validate = new Function('$input', validateCode);
  const good = { version: 1, requestId: 'a'.repeat(64), status: 'reply_ready', reason: null, reply: { to: 'sender@example.test', subject: 'Test', body: 'Body' } };
  assert.equal(validate({ all: () => [{ json: { code: 0, stdout: JSON.stringify(good), stderr: '' } }] })[0].json.status, 'reply_ready');
  for (const value of [{ ...good, status: 'approved' }, { ...good, approved: true }, { ...good, reply: { ...good.reply, to: 'bad\n@example.test' } }]) assert.throws(() => validate({ all: () => [{ json: { code: 0, stdout: JSON.stringify(value), stderr: '' } }] }));
  assert.throws(() => validate({ all: () => [{ json: { code: 1, stdout: JSON.stringify(good) } }] }));
  const reserve = candidate.nodes.find(node => node.name === 'Reserve exact send');
  assert.match(reserve.parameters.command, /mail-assistant-runner send-reserve/);
  assert.deepEqual(candidate.connections['Strict status'].main[0].map(edge => edge.node), ['Prepare send reservation']);
  assert.deepEqual(candidate.connections['Strict status'].main[1].map(edge => edge.node), ['Approval wait UNCONFIGURED']);
});
