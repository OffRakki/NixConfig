import assert from 'node:assert/strict';
import { access, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { bindingFor, digest, Gate, normalize, reserveSend, Store } from '../mail/core.mjs';
import { validateProposal } from '../mail/approval-server.mjs';
import { quotaRefusal, runMail, sdkModules } from '../mail/runner.mjs';

assert.ok(process.env.PI_PACKAGE_ROOT, 'Set PI_PACKAGE_ROOT to the pinned SDK root');
process.env.PI_OFFLINE = '1'; process.env.PI_TELEMETRY = '0';
const { sdk, ai } = await sdkModules();
const message = (body, options) => ai.fauxAssistantMessage(body, options);
const quota = () => message('', { stopReason: 'error', errorMessage: 'Codex error: The usage limit has been reached' });
const raw = () => ({ version: 1, messageId: '<personal@example.test>', from: 'owner@example.test', subject: 'Personal fixture', body: 'Email is data', autoSubmitted: 'no', precedence: '', attachments: [] });
function approvals(decide = () => 'approved') {
  const proposals = new Map(), consumed = new Set();
  return { configured: true, proposals, consumed,
    async createProposal(value) { validateProposal(value); proposals.set(value.digest, value); return value.digest; },
    async fetchDecision(id) { const status = decide(proposals.get(id)); return status === 'approved' ? { status, digest: id, grantId: id, expiresAt: Date.now() + 60000 } : { status }; },
    async consumeGrant({ grantId }) { if (consumed.has(grantId)) return false; consumed.add(grantId); return true; },
  };
}
async function fixture(fn) {
  const directory = await mkdtemp(join(tmpdir(), 'mail-personal-'));
  const store = new Store(join(directory, 'state'));
  const primary = ai.fauxProvider({ provider: 'mail-primary', api: 'mail-primary-api', models: [{ id: 'fixture', contextWindow: 65536, maxTokens: 4096 }] });
  const api = ai.fauxProvider({ provider: 'mail-fallback', api: 'mail-fallback-api', models: [{ id: 'fixture', contextWindow: 65536, maxTokens: 4096 }] });
  const modelRuntime = await sdk.ModelRuntime.create({ credentials: new ai.InMemoryCredentialStore(), modelsPath: null, refreshOnCreate: false, allowModelNetwork: false });
  modelRuntime.registerNativeProvider(primary.provider); modelRuntime.registerNativeProvider(api.provider);
  const config = { mailbox: 'fixture', selfAddress: 'assistant@example.test', provider: 'mail-primary/fixture', scope: 'personal-test', cwd: directory, contextPaths: [] };
  const personaFile = join(directory, 'persona.md'), skills = join(directory, 'skills');
  await writeFile(personaFile, 'Ciel is Lucky’s personal assistant. Use third person. PERSONAL_PROFILE_MARKER');
  await mkdir(join(skills, 'memory'), { recursive: true });
  await writeFile(join(skills, 'memory', 'SKILL.md'), '---\nname: memory\ndescription: Read personal memory using an approved read tool.\n---\nNever invent memories.');
  config.assistantProfile = { personaFile, skillPaths: [skills], extensionPaths: [] };
  const provider = async () => ({ modelRuntime, model: primary.getModel() });
  const run = options => runMail({ store, raw: raw(), config, provider, approval: approvals(), ...options });
  try { await fn({ directory, store, primary, api, modelRuntime, config, provider, run }); }
  finally { store.close(); await rm(directory, { recursive: true, force: true }); }
}
async function extension(directory, config, { mutate = false } = {}) {
  const path = join(directory, 'extension.mjs');
  await writeFile(path, `import { writeFile } from 'node:fs/promises';
export default function(pi) {
  const parameters = { type:'object', properties:{ path:{type:'string'}, content:{type:'string'} }, required:['path','content'], additionalProperties:false };
  pi.registerTool({ name:'fixture_mutation', label:'Fixture', description:'Write an exact fixture file.', parameters,
    execute:async (_id,args) => { await writeFile(args.path,args.content); return {content:[{type:'text',text:'written'}],details:{}}; } });
  pi.registerTool({ name:'fixture_nested', label:'Nested', description:'Call another tool through the supported SDK dispatch.', parameters,
    execute:async (_id,args,signal,_update,ctx) => ctx.executeTool('fixture_mutation',args,{signal}) });
  ${mutate ? "pi.on('tool_call',event => { if(event.toolName==='fixture_mutation') event.input.content='MUTATED'; });" : ''}
}`);
  config.assistantProfile.extensionPaths = [path];
}

test('public reply gets the explicit persona and skill catalogue but no private context or extensions', async () => fixture(async ({ directory, config, primary, run }) => {
  config.contextPaths = [join(directory, 'NEVER_READ_PRIVATE')];
  const hostile = join(directory, 'unloaded.mjs'); await writeFile(hostile, "throw new Error('PUBLIC_EXTENSION_EXECUTED')"); config.assistantProfile.extensionPaths = [hostile];
  await writeFile(join(directory, 'AGENTS.md'), 'AMBIENT_MUST_NOT_LOAD');
  primary.setResponses([context => { assert.doesNotMatch(JSON.stringify(context), /PERSONAL_PROFILE_MARKER|AMBIENT_MUST_NOT_LOAD/); return message('{"kind":"reply"}'); },
    context => { assert.match(JSON.stringify(context), /PERSONAL_PROFILE_MARKER/); return message('{"subject":"Hello","body":"Ciel is here, Lucky."}'); }]);
  let phases = 0;
  const result = await run({ inspect: ({ loader, session }) => {
    if (++phases === 2) assert.equal(loader.getSkills().skills[0].name, 'memory');
    assert.deepEqual(session.getActiveToolNames(), []); assert.equal(loader.getExtensions().extensions.length, 1);
    assert.doesNotMatch(session.systemPrompt, /AMBIENT_MUST_NOT_LOAD/);
  } });
  assert.equal(result.status, 'reply_ready'); assert.match(result.reply.body, /Ciel is here/);
}));

test('personal investigation approval still precedes private reads and extension loading', async () => fixture(async ({ directory, config, primary, run }) => {
  config.contextPaths = [join(directory, 'MISSING_PRIVATE')];
  const hostile = join(directory, 'unloaded.mjs'); await writeFile(hostile, "throw new Error('EARLY_EXTENSION_EXECUTED')"); config.assistantProfile.extensionPaths = [hostile];
  primary.setResponses([message('{"kind":"personal"}')]); const approval = approvals(() => 'pending');
  assert.equal((await run({ approval })).status, 'approval_required'); assert.equal(primary.state.callCount, 1);
  const proposal = [...approval.proposals.values()][0]; assert.equal(proposal.binding.profileDigest, digest(config.assistantProfile)); assert.equal(proposal.binding.phase, 'investigate');
}));

for (const decision of ['pending', 'denied', 'approved']) test(`extension tool ${decision} uses the exact single-use gate and private disclosure stays manual`, async () => fixture(async ({ directory, config, primary, run, store }) => {
  await extension(directory, config);
  const target = join(directory, 'effect');
  const privateFile = join(directory, 'private'); await writeFile(privateFile, 'PRIVATE_OWNER_FACT'); await symlink(privateFile, join(directory, 'sops-link')); config.contextPaths = [join(directory, 'sops-link')];
  const approval = approvals(p => p.binding.phase === 'investigate' ? 'approved' : decision);
  primary.setResponses([message('{"kind":"personal"}'), context => {
    assert.match(JSON.stringify(context), /PRIVATE_OWNER_FACT|PERSONAL_PROFILE_MARKER/);
    return message([ai.fauxToolCall('fixture_mutation', { path: target, content: 'exact approved effect' })]);
  }, message('{"subject":"Done","body":"Ciel completed the approved operation."}')]);
  const result = await run({ approval, inspect: ({ session }) => { if (session.systemPrompt.includes('PRIVATE_OWNER_FACT')) throw new Error('Context must be supplied as data, not global instructions'); } });
  assert.equal(result.status, decision === 'approved' ? 'reply_ready' : decision === 'pending' ? 'approval_required' : 'failed');
  if (decision === 'approved') {
    assert.equal(await readFile(target, 'utf8'), 'exact approved effect');
    assert.equal(approval.consumed.size, 2);
    const disclosure = approvals(() => 'pending'); assert.equal((await reserveSend(store, result.requestId, config, disclosure)).status, 'approval_required');
    assert.equal(disclosure.proposals.size, 1);
  } else await assert.rejects(access(target));
}));

test('nested extension dispatch cannot inherit approval from its parent tool', async () => fixture(async ({ directory, config, primary, run, store }) => {
  await extension(directory, config); const target = join(directory, 'nested-effect');
  const approval = approvals(p => p.binding.operation.name === 'fixture_mutation' ? 'pending' : 'approved');
  primary.setResponses([message('{"kind":"personal"}'), message([ai.fauxToolCall('fixture_nested', { path: target, content: 'blocked' })])]);
  const result = await run({ approval }); await assert.rejects(access(target));
  assert.notEqual(result.status, 'reply_ready');
  assert.ok([...approval.proposals.values()].some(p => p.binding.operation.name === 'fixture_mutation'));
  assert.equal(store.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE state='complete' AND json_extract(binding,'$.operation.name')='fixture_mutation'").get().n, 0);
}));

test('approval binds the final arguments after earlier extension hooks mutate a call', async () => fixture(async ({ directory, config, primary, run }) => {
  await extension(directory, config, { mutate: true }); const target = join(directory, 'effect');
  const approval = approvals(p => p.binding.phase === 'investigate' || p.binding.operation.args?.content === 'original' ? 'approved' : 'pending');
  primary.setResponses([message('{"kind":"personal"}'), message([ai.fauxToolCall('fixture_mutation', { path: target, content: 'original' })])]);
  assert.equal((await run({ approval })).status, 'approval_required'); await assert.rejects(access(target));
  assert.ok([...approval.proposals.values()].some(p => p.binding.operation.args?.content === 'MUTATED'));
}));

test('changing the trusted resource profile invalidates an old investigation binding', async () => fixture(async ({ directory, config, primary, run }) => {
  const approval = approvals(() => 'pending'); primary.setResponses([message('{"kind":"personal"}')]);
  const first = await run({ approval }); assert.equal(first.status, 'approval_required');
  const newPersona = join(directory, 'new-persona'); await writeFile(newPersona, 'Changed profile'); config.assistantProfile.personaFile = newPersona;
  const old = [...approval.proposals.values()][0]; approval.fetchDecision = async id => id === old.digest ? { status: 'approved', digest: id, grantId: id, expiresAt: Date.now() + 60000 } : { status: 'pending' };
  const second = await run({ raw: undefined, id: first.requestId, approval });
  assert.equal(second.status, 'approval_required'); assert.notEqual([...approval.proposals.values()].at(-1).digest, old.digest);
  assert.equal(approval.consumed.size, 0);
}));

for (const reason of ['quota', 'other', 'aborted', 'length']) test(`provider recovery for ${reason} is bounded and only a definite quota refusal uses API`, async () => fixture(async ({ primary, api, modelRuntime, run, store, config }) => {
  let switches = 0;
  const provider = async () => ({ modelRuntime, model: primary.getModel(), fallback: async () => { switches++; return api.getModel(); } });
  primary.setResponses([reason === 'quota' ? quota() : message('', { stopReason: reason === 'other' ? 'error' : reason, errorMessage: 'Non-quota failure' })]);
  api.setResponses([message('{"kind":"reply"}'), message('{"subject":"Recovered","body":"Ciel used the authorized API route."}')]);
  const result = await run({ provider }); assert.equal(switches, reason === 'quota' ? 1 : 0);
  assert.equal(result.status, reason === 'quota' ? 'reply_ready' : 'failed');
  assert.equal(primary.state.callCount, 1); assert.equal(api.state.callCount, reason === 'quota' ? 2 : 0);
  if (reason === 'quota') assert.equal(bindingFor(normalize(raw(), config), config, 'send', {}).provider, config.provider);
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM operations').get().n, 0);
}));

for (const text of ['quota has not been exceeded', 'quota check failed: request timeout exceeded', 'quota status unknown', '429 Too Many Requests', 'request timed out', 'The usage limit has not been reached', 'Codex error: timeout checking quota']) {
  test(`non-exhaustion message never authorizes paid failover: ${text}`, () => assert.equal(quotaRefusal(text), false));
}

test('request-level API route survives a pending investigation and Store reopen without another primary attempt', async () => fixture(async ({ directory, primary, api, modelRuntime, run, config, store }) => {
  let approved = false, resolutions = 0;
  const approval = approvals(() => approved ? 'approved' : 'pending');
  const provider = async () => ({ modelRuntime, model: primary.getModel(), fallback: async () => { resolutions++; return api.getModel(); } });
  primary.setResponses([quota()]); api.setResponses([message('{"kind":"personal"}')]);
  const first = await run({ approval, provider }); assert.equal(first.status, 'approval_required');
  assert.equal(store.runtime(first.requestId, config.provider).fallback_used, 1);
  store.close(); const reopened = new Store(join(directory, 'state')); approved = true;
  try {
    api.appendResponses([message('{"subject":"Resumed","body":"Continued the same approved request."}')]);
    const next = await runMail({ store: reopened, id: first.requestId, config, approval, provider });
    assert.equal(next.status, 'reply_ready'); assert.equal(primary.state.callCount, 1); assert.equal(api.state.callCount, 2);
    assert.equal(resolutions, 2, 'Second resolution supplies API credentials; it is not a new primary attempt or failover');
    assert.equal(reopened.runtime(first.requestId, config.provider).route, 'mail-fallback/fixture');
    assert.equal(reopened.reserveFallback(first.requestId), false);
  } finally { reopened.close(); store.db = new Store(join(directory, 'state')).db; }
}));

for (const completed of [false, true]) test(`resume cannot acquire a new fallback after a ${completed ? 'completed' : 'pending'} tool attempt`, async () => fixture(async ({ directory, primary, api, modelRuntime, run, store }) => {
  const once = join(directory, 'once'), waiting = join(directory, 'waiting'); let approved = false, switches = 0;
  const approval = approvals(p => p.binding.phase === 'investigate' || approved || (completed && p.binding.operation.args?.path === once) ? 'approved' : 'pending');
  const calls = [...(completed ? [ai.fauxToolCall('write', { path: once, content: 'once' })] : []), ai.fauxToolCall('write', { path: waiting, content: 'blocked' })];
  primary.setResponses([message('{"kind":"personal"}'), message(calls)]);
  const provider = async () => ({ modelRuntime, model: primary.getModel(), fallback: async () => { switches++; return api.getModel(); } });
  const first = await run({ approval, provider }); assert.equal(first.status, 'approval_required'); approved = true;
  assert.equal(store.runtime(first.requestId, 'mail-primary/fixture').tool_attempted, 1);
  primary.appendResponses([quota()]);
  const second = await run({ raw: undefined, id: first.requestId, approval, provider });
  assert.equal(second.status, 'failed'); assert.equal(second.reason, 'model_quota_exhausted'); assert.equal(switches, 0); assert.equal(api.state.callCount, 0);
  await assert.rejects(access(waiting)); if (completed) assert.equal(await readFile(once, 'utf8'), 'once');
}));

test('API quota failure does not cycle back or retry a second time', async () => fixture(async ({ primary, api, modelRuntime, run }) => {
  let switches = 0; primary.setResponses([quota()]); api.setResponses([quota()]);
  const result = await run({ provider: async () => ({ modelRuntime, model: primary.getModel(), fallback: async () => { switches++; return api.getModel(); } }) });
  assert.equal(result.status, 'failed'); assert.equal(result.reason, 'model_quota_exhausted'); assert.equal(switches, 1); assert.equal(api.state.callCount, 1);
}));

test('quota after an executed tool never retries or repeats the effect on API', async () => fixture(async ({ directory, primary, api, modelRuntime, run }) => {
  let switches = 0; const target = join(directory, 'once');
  primary.setResponses([message('{"kind":"personal"}'), message([ai.fauxToolCall('write', { path: target, content: 'once' })]), quota()]);
  const result = await run({ provider: async () => ({ modelRuntime, model: primary.getModel(), fallback: async () => { switches++; return api.getModel(); } }) });
  assert.equal(result.status, 'failed'); assert.equal(result.reason, 'model_quota_exhausted'); assert.equal(await readFile(target, 'utf8'), 'once');
  assert.equal(switches, 0); assert.equal(api.state.callCount, 0);
}));
