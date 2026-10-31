import assert from 'node:assert/strict';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';
import { decodeEnvelope } from '../mail/core.mjs';
import { buildMailWorkflow, prepareEnvelope, prepareOutcome, prepareResume, prepareSend, retrySend, validateDraft, validateSend, workflowSdkCode } from '../mail/workflow.mjs';

const id = 'a'.repeat(64), reservation = 'b'.repeat(64);
const deadline = () => Date.now() + 60000;
const raw = () => ({ version: 1, messageId: '<workflow@example.test>', from: 'sender@example.test', subject: 'Test', body: 'Literal $(touch nope)', autoSubmitted: 'no', precedence: '', attachments: [] });
const run = (fn, value, lookup = () => ({ first: () => ({ json: { deadline: deadline() } }) })) =>
  new Function('$input', '$', 'Buffer', `return (${fn.toString()})();`)({ first: () => ({ json: value }), all: () => [{ json: value }] }, lookup, Buffer);
const ssh = value => ({ code: 0, stdout: JSON.stringify(value) });
const draft = () => ({ version: 1, requestId: id, status: 'reply_ready', reason: null, reply: { to: 'sender@example.test', subject: 'Re: Test', body: 'Test reply' } });

test('inactive graph has working manual entry, separately disabled IMAP, and bound references only', () => {
  const creds = { id: 'fixture', name: 'Fixture credential' };
  const graph = buildMailWorkflow({ ssh: creds, smtp: creds, imap: creds });
  assert.equal(graph.active, false); assert.equal(graph.id, undefined);
  const byName = new Map(graph.nodes.map(node => [node.name, node]));
  assert.equal(byName.get('Run approval test').type, 'n8n-nodes-base.manualTrigger');
  assert.equal(byName.get('IMAP — disabled while Mail is active').disabled, true);
  assert.equal(byName.get('IMAP — disabled while Mail is active').parameters.format, 'resolved');
  for (const node of graph.nodes.filter(node => node.type === 'n8n-nodes-base.ssh')) {
    assert.equal(node.disabled, undefined); assert.equal(node.retryOnFail, false);
    assert.deepEqual(node.credentials, { sshPrivateKey: creds });
    assert.match(node.parameters.command, /^=\/home\/rakki\/\.nix-profile\/bin\/mail-assistant-runner (process|resume|send-reserve|send-finish) '\{\{ \$json\.(payload|requestId) \}\}'$/);
  }
  assert.equal(byName.get('Send approved email').retryOnFail, false);
  assert.equal(byName.get('Send approved email').onError, 'continueErrorOutput');
  assert.equal(byName.get('Send approved email').parameters.fromEmail, 'ciel@ore.rs');
  const inbound = Object.entries(graph.connections).flatMap(([source, c]) => c.main.flat().filter(e => e.node === 'Send approved email').map(() => source));
  assert.deepEqual(inbound, ['Delivery status']);
  assert.deepEqual(graph.connections['Delivery status'].main[0].map(e => e.node), ['Send approved email']);
  assert.deepEqual(graph.connections['Delivery status'].main[1].map(e => e.node), ['Wait for disclosure approval']);
  assert.deepEqual(graph.connections['Draft status'].main[1].map(e => e.node), ['Wait for owner decision']);
  assert.deepEqual(graph.connections['Prepare uncertain receipt'].main[0].map(e => e.node), ['Record delivery outcome']);
  assert.equal(graph.nodes.some(n => /httpRequest|webhook/.test(n.type)), false);
  assert.match(workflowSdkCode(), /export default workflow\('mail-approval-test'/);
  assert.match(workflowSdkCode(), /\.connect\(n\d+,1,n\d+,0\)/);
  assert.doesNotMatch(workflowSdkCode(), /fromJSON/);
});

test('unbound source cannot execute SSH or SMTP by accidental import', () => {
  const graph = buildMailWorkflow();
  for (const n of graph.nodes.filter(n => ['n8n-nodes-base.ssh', 'n8n-nodes-base.emailSend'].includes(n.type))) assert.equal(n.disabled, true);
});

test('manual and real resolved envelopes use the same canonical inert transport', () => {
  assert.deepEqual(decodeEnvelope(run(prepareEnvelope, raw())[0].json.payload), raw());
  const resolved = { from: { value: [{ address: 'sender@example.test' }] }, messageId: '<workflow@example.test>', subject: 'Test', text: 'Literal $(touch nope)', headers: { 'auto-submitted': 'no' } };
  assert.deepEqual(decodeEnvelope(run(prepareEnvelope, resolved)[0].json.payload), raw());
  assert.throws(() => run(prepareEnvelope, { ...resolved, from: { value: [] } }));
  assert.throws(() => run(prepareEnvelope, { ...resolved, text: undefined }));
  const code = buildMailWorkflow().nodes.find(n => n.name === 'Prepare envelope').parameters.jsCode;
  assert.throws(() => new Function('$input', 'Buffer', code)({ all: () => [{ json: raw(), binary: { attachment: {} } }] }, Buffer), /attachments_unsupported/);
});

test('n8n cross-realm and null-prototype JSON inputs preserve canonical transport', () => {
  const otherRealm = runInNewContext(`JSON.parse(${JSON.stringify(JSON.stringify(raw()))})`);
  assert.notEqual(Object.getPrototypeOf(otherRealm), Object.prototype);
  assert.deepEqual(decodeEnvelope(run(prepareEnvelope, otherRealm)[0].json.payload), raw());
  const noPrototype = Object.assign(Object.create(null), raw());
  assert.deepEqual(decodeEnvelope(run(prepareEnvelope, noPrototype)[0].json.payload), raw());
  assert.throws(() => run(prepareEnvelope, { ...raw(), constructor: 'forbidden' }), /invalid_json/);
});

test('runner drafts and resume commands reject failure, invalid identifiers and expired waits', () => {
  const result = run(validateDraft, ssh(draft()))[0].json;
  assert.equal(result.status, 'reply_ready'); assert.equal(result.approvalUrl, 'http://127.0.0.1:8765/');
  for (const value of [{ ...draft(), status: 'approved' }, { ...draft(), requestId: "';whoami" }, { ...draft(), reply: { ...draft().reply, to: 'victim@example.test\nBcc:other@example.test' } }]) assert.throws(() => run(validateDraft, ssh(value)));
  assert.throws(() => run(validateDraft, { ...ssh(draft()), code: 1 }));
  assert.throws(() => run(validateDraft, ssh(draft()), () => ({ first: () => ({ json: { deadline: 0 } }) })));
  assert.equal(run(prepareResume, { status: 'approval_required', requestId: id, deadline: deadline() })[0].json.requestId, id);
  assert.throws(() => run(prepareResume, { status: 'approval_required', requestId: "';bash", deadline: deadline() }));
  assert.throws(() => run(prepareResume, { status: 'approval_required', requestId: id, deadline: 0 }));
});

test('send polling uses only canonical request identity, never unreviewed model recipient/body', () => {
  assert.deepEqual(decodeEnvelope(run(prepareSend, draft())[0].json.payload), { requestId: id });
  assert.deepEqual(decodeEnvelope(run(retrySend, { status: 'approval_required', requestId: id, deadline: deadline() })[0].json.payload), { requestId: id });
  const reserved = { version: 1, requestId: id, status: 'send_reserved', reservation, reply: draft().reply };
  assert.equal(run(validateSend, ssh(reserved))[0].json.reservation, reservation);
  assert.throws(() => run(validateSend, ssh({ ...reserved, status: 'approved' })));
  assert.throws(() => run(validateSend, ssh({ ...reserved, reservation: 'not-a-reservation' })));
  assert.throws(() => run(validateSend, ssh({ ...reserved, reply: { ...draft().reply, subject: 'Bad\r\nHeader' } })));
  assert.throws(() => run(retrySend, { status: 'send_reserved', requestId: id, deadline: deadline() }));
});

test('delivery receipts preserve reserved identity and conservatively record uncertain SMTP', () => {
  const reserved = [{ json: { status: 'send_reserved', requestId: id, reservation } }];
  for (const outcome of ['sent', 'unknown']) {
    const payload = prepareOutcome(outcome, reserved)[0].json.payload;
    assert.deepEqual(decodeEnvelope(payload), { outcome, requestId: id, reservation });
  }
  assert.throws(() => prepareOutcome('sent', [{ json: { status: 'approval_required', requestId: id } }]));
  assert.throws(() => prepareOutcome('retry', reserved));
  for (const invalid of [undefined, [], [...reserved, ...reserved]]) assert.throws(() => prepareOutcome('sent', invalid), /one_delivery_reservation_required/);
});

test('emitted receipts expose the literal dependency and use the latest poll without SMTP item lineage', () => {
  const graph = buildMailWorkflow();
  const pending = [{ json: { status: 'approval_required', requestId: id } }];
  const reserved = [{ json: { status: 'send_reserved', requestId: id, reservation } }];
  const history = [pending, pending, reserved];
  for (const [name, outcome] of [['Prepare sent receipt', 'sent'], ['Prepare uncertain receipt', 'unknown']]) {
    const source = graph.nodes.find(n => n.name === name).parameters.jsCode;
    assert.match(source, /\$\('Validate send reservation'\)\.all\(0, -1\)/);
    const lookup = node => {
      assert.equal(node, 'Validate send reservation');
      return {
        get item() { throw new Error('SMTP has no paired item'); },
        all(branch, runIndex) {
          assert.equal(branch, 0); assert.equal(runIndex, -1);
          return history.at(runIndex);
        },
      };
    };
    const result = new Function('$', 'Buffer', source)(lookup, Buffer);
    assert.deepEqual(decodeEnvelope(result[0].json.payload), { outcome, requestId: id, reservation });
    assert.throws(() => new Function('$', 'Buffer', source)(() => ({ all: () => pending }), Buffer), /invalid_delivery_reservation/);
  }
});
