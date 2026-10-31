import { createHash, randomUUID } from 'node:crypto';
import { constants, closeSync, lstatSync, mkdirSync, openSync, realpathSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { SAFE_NAMES, safeFresh, safePlan } from './safe.mjs';

export const LIMIT = Object.freeze({ input: 131072, body: 65536, reply: 16384, attachments: 8, attachmentBytes: 10485760 });
export function canonical(value) {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return JSON.stringify(value);
  if (typeof value === 'number' && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    if (Object.keys(value).some(k => ['__proto__', 'constructor', 'prototype'].includes(k))) throw new Error('invalid_key');
    return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${canonical(value[k])}`).join(',')}}`;
  }
  throw new Error('invalid_json');
}
export const digest = value => createHash('sha256').update(canonical(value)).digest('hex');
export async function bounded(promise, signal) {
  if (!signal) return promise;
  signal.throwIfAborted();
  let abort;
  const stopped = new Promise((_, reject) => { abort = () => reject(new Error('aborted')); signal.addEventListener('abort', abort, { once: true }); });
  try { return await Promise.race([promise, stopped]); }
  finally { signal.removeEventListener('abort', abort); }
}
export function closed(value, required, optional = []) {
  if (!value || Object.getPrototypeOf(value) !== Object.prototype || required.some(k => !Object.hasOwn(value, k)) ||
      Object.keys(value).some(k => ![...required, ...optional].includes(k))) throw new Error('invalid_schema');
  canonical(value);
  return value;
}
export function text(value, max, min = 0) {
  if (typeof value !== 'string' || value.length < min || Buffer.byteLength(value) > max || value.includes('\0')) throw new Error('invalid_text');
  return value;
}
export function address(value) {
  text(value, 254, 3);
  if (!/^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$/.test(value)) throw new Error('invalid_address');
  return value.toLowerCase();
}
export function decodeEnvelope(encoded) {
  text(encoded, LIMIT.input * 2, 4);
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) throw new Error('invalid_base64');
  const bytes = Buffer.from(encoded, 'base64');
  if (bytes.length > LIMIT.input || bytes.toString('base64') !== encoded) throw new Error('invalid_base64');
  const json = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  const value = JSON.parse(json);
  // Canonical transport rejects duplicate keys, extraneous JSON, whitespace and ambiguous representations.
  if (canonical(value) !== json) throw new Error('noncanonical_json');
  return value;
}
export const encodeEnvelope = value => Buffer.from(canonical(value)).toString('base64');
export function classify(raw, allowSafe = false) {
  const parsed = JSON.parse(text(raw, 1024, 1));
  if (allowSafe && parsed?.kind === 'safe') return safePlan(parsed);
  const value = closed(parsed, ['kind']);
  if (!['reply', 'personal', 'reject'].includes(value.kind)) throw new Error('invalid_classification');
  return value.kind;
}

function validateSafeAuthority(config) {
  if (config.automaticReplies !== undefined && typeof config.automaticReplies !== 'boolean') throw new Error('invalid_host_config');
  if (config.safeCapabilities !== undefined && (!Array.isArray(config.safeCapabilities) || config.safeCapabilities.length > 2 || new Set(config.safeCapabilities).size !== config.safeCapabilities.length || config.safeCapabilities.some(name => !SAFE_NAMES.includes(name)))) throw new Error('invalid_host_config');
}
export function validateRecipientPolicy(policy) {
  closed(policy, ['version', 'allowedRecipients', 'defaultRecipient'], ['safeCapabilities', 'automaticReplies']);
  validateSafeAuthority(policy);
  if (policy.version !== 1 || !Array.isArray(policy.allowedRecipients) || policy.allowedRecipients.length < 1 || policy.allowedRecipients.length > 32) throw new Error('invalid_recipient_policy');
  const allowedRecipients = policy.allowedRecipients.map(address);
  const defaultRecipient = address(policy.defaultRecipient);
  if (new Set(allowedRecipients).size !== allowedRecipients.length || !allowedRecipients.includes(defaultRecipient)) throw new Error('invalid_recipient_policy');
  return Object.freeze({ version: 1, allowedRecipients: Object.freeze(allowedRecipients), defaultRecipient,
    safeCapabilities: Object.freeze([...(policy.safeCapabilities ?? [])]), automaticReplies: policy.automaticReplies ?? false });
}
export function deliveryRecipient(request, config) {
  // Offline fixtures may omit a policy. Production always loads its required runtime secret.
  const from = address(request.input.from);
  if (!config?.recipientPolicy) return from;
  const policy = validateRecipientPolicy(config.recipientPolicy);
  return policy.allowedRecipients.includes(from) ? from : policy.defaultRecipient;
}
export function validateConfig(config) {
  closed(config, ['mailbox', 'selfAddress', 'provider', 'scope', 'cwd', 'contextPaths'], ['recipientPolicy', 'safeCapabilities', 'automaticReplies']);
  validateSafeAuthority(config);
  if (config.recipientPolicy) validateRecipientPolicy(config.recipientPolicy);
  text(config.mailbox, 128, 1); address(config.selfAddress);
  for (const key of ['provider', 'scope']) text(config[key], 200, 1);
  if (!isAbsolute(config.cwd) || !Array.isArray(config.contextPaths) || config.contextPaths.length > 8 || config.contextPaths.some(path => typeof path !== 'string' || !isAbsolute(path))) throw new Error('invalid_host_config');
}
export function formatReply(request, draft, config, now = Date.now()) {
  closed(draft, ['subject', 'body']); text(draft.subject, 512, 1); text(draft.body, LIMIT.reply, 1);
  if (/[\r\n]/.test(draft.subject)) throw new Error('invalid_reply_subject');
  const original = request.input;
  const subject = /^re:/i.test(original.subject) ? original.subject : `Re: ${original.subject}`;
  text(subject, 512, 1);
  const quote = original.body.slice(0, 2048).replace(/\r\n?/g, '\n').split('\n').map(line => `> ${line}`).join('\n');
  const to = deliveryRecipient(request, config);
  const ownerCopy = to !== original.from;
  const context = ownerCopy ? `Owner copy — NOT sent to the original sender.\nOriginal sender (unverified From): ${original.from}\nOriginal subject: ${original.subject}\nMessage date (sender supplied): ${original.sentAt ?? 'not provided'}\nProcessed by assistant (UTC): ${new Date(now).toISOString()}\n\n--- Draft answer ---\n` : '';
  const body = `${context}${draft.body}\n\n--- Original message from ${original.from} ---\n${quote}${original.body.length > 2048 ? '\n> [original truncated]' : ''}`;
  text(body, LIMIT.reply, 1);
  return { to, subject, body };
}
export function normalize(raw, config) {
  closed(raw, ['version', 'messageId', 'from', 'subject', 'body', 'autoSubmitted', 'precedence', 'attachments'], ['sentAt']);
  if (raw.sentAt !== undefined && raw.sentAt !== null && (typeof raw.sentAt !== 'string' || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(raw.sentAt) || !Number.isFinite(Date.parse(raw.sentAt)) || new Date(raw.sentAt).toISOString() !== raw.sentAt)) throw new Error('invalid_message_date');
  if (raw.version !== 1) throw new Error('invalid_version');
  text(config.mailbox, 128, 1);
  const self = address(config.selfAddress);
  const from = address(raw.from);
  text(raw.subject, 512); text(raw.body, LIMIT.body);
  if (/[\r\n]/.test(raw.subject)) throw new Error('invalid_subject');
  if (raw.messageId !== null && !/^<[^<>\s\x00-\x1f\x7f]{1,250}@[^<>\s\x00-\x1f\x7f]{1,250}>$/.test(raw.messageId)) throw new Error('invalid_message_id');
  text(raw.autoSubmitted, 100); text(raw.precedence, 100);
  if (!Array.isArray(raw.attachments) || raw.attachments.length > LIMIT.attachments) throw new Error('invalid_attachments');
  let total = 0;
  for (const item of raw.attachments) {
    closed(item, ['name', 'size', 'mime']);
    text(item.name, 255, 1); text(item.mime, 128, 1);
    if (!Number.isSafeInteger(item.size) || item.size < 0) throw new Error('invalid_attachment_size');
    total += item.size;
  }
  if (total > LIMIT.attachmentBytes) throw new Error('attachments_too_large');
  const input = { ...raw, from };
  // No reliable IMAP UID is assumed. Content identity is a conservative dedup fallback, not sender authentication.
  // Even a reused Message-ID cannot overwrite a claimed request. Separate content becomes a separate request.
  // Optional display metadata must not turn an already-processed legacy email into a fresh request.
  const { sentAt, ...identityInput } = input;
  const source = digest(identityInput);
  const id = digest({ mailbox: config.mailbox, source });
  let rejection = null;
  if (from === self || (raw.autoSubmitted && raw.autoSubmitted.toLowerCase() !== 'no') || /^(bulk|list|junk)$/i.test(raw.precedence)) rejection = 'loop_suppressed';
  // No attachment is written, extracted, silently discarded or executed. A configured approved extractor is a future gate.
  if (raw.attachments.length) rejection = 'attachments_unsupported';
  return { id, source, mailbox: config.mailbox, input, rejection };
}

function privatePath(path, directory) {
  const stat = lstatSync(path);
  if (stat.isSymbolicLink() || (directory ? !stat.isDirectory() : !stat.isFile()) || stat.uid !== process.getuid() || (stat.mode & 0o777) !== (directory ? 0o700 : 0o600)) throw new Error('insecure_state_permissions');
}
export class Store {
  constructor(directory) {
    if (!isAbsolute(directory)) throw new Error('absolute_state_required');
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    privatePath(directory, true);
    if (realpathSync(directory) !== directory) throw new Error('symlink_state_parent');
    const path = join(directory, 'state.sqlite');
    const fd = openSync(path, constants.O_CREAT | constants.O_RDWR | constants.O_NOFOLLOW, 0o600);
    closeSync(fd); privatePath(path, false);
    this.db = new DatabaseSync(path);
    if (![0, 1, 2].includes(this.db.prepare('PRAGMA user_version').get().user_version)) { this.db.close(); throw new Error('unsupported_state_version'); }
    this.db.exec(`PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS requests(id TEXT PRIMARY KEY, digest TEXT NOT NULL, input TEXT NOT NULL,
        status TEXT NOT NULL, reason TEXT, reply TEXT, owner TEXT, context TEXT, kind TEXT);
      CREATE TABLE IF NOT EXISTS operations(key TEXT PRIMARY KEY, request TEXT NOT NULL, binding TEXT NOT NULL,
        state TEXT NOT NULL, proposal TEXT, grant TEXT UNIQUE, result TEXT);`);
    // v1 rows retain one-use states; missing legacy result snapshots cannot be reconstructed safely.
    if (!this.db.prepare('PRAGMA table_info(operations)').all().some(column => column.name === 'result')) this.db.exec('ALTER TABLE operations ADD COLUMN result TEXT');
    this.db.exec('PRAGMA user_version=2;');
  }
  close() { this.db.close(); }
  claim(request) {
    this.db.prepare('INSERT OR IGNORE INTO requests(id,digest,input,status,reason) VALUES(?,?,?,?,?)')
      .run(request.id, digest(request), canonical(request), request.rejection ? 'rejected' : 'approval_required', request.rejection);
    const row = this.get(request.id);
    if (row.digest !== digest(request)) throw new Error('immutable_request_mismatch');
    return row;
  }
  get(id) {
    if (!/^[a-f0-9]{64}$/.test(id)) throw new Error('invalid_request_id');
    const row = this.db.prepare('SELECT * FROM requests WHERE id=?').get(id);
    if (!row) throw new Error('unknown_request');
    return row;
  }
  begin(id) {
    const owner = randomUUID();
    const result = this.db.prepare("UPDATE requests SET status='running',owner=?,reason=NULL WHERE id=? AND status='approval_required' AND owner IS NULL").run(owner, id);
    return result.changes ? owner : null;
  }
  finish(id, owner, status, reason = null, reply = null) {
    if (!['approval_required', 'reply_ready', 'rejected', 'failed'].includes(status)) throw new Error('invalid_status');
    const result = this.db.prepare('UPDATE requests SET status=?,reason=?,reply=?,owner=NULL WHERE id=? AND owner=? AND status=\'running\'').run(status, reason, reply && canonical(reply), id, owner);
    if (!result.changes) throw new Error('lost_request_claim');
    return this.result(id);
  }
  result(id) {
    const row = this.get(id);
    // A concurrent or interrupted running request is uncertain, never reclaimable automatically.
    return { version: 1, requestId: id, status: row.status === 'running' ? 'failed' : row.status,
      reason: row.status === 'running' ? 'run_in_progress_or_uncertain' : row.reason,
      reply: row.status === 'reply_ready' && row.reply ? JSON.parse(row.reply) : null };
  }
  operation(binding) {
    const key = digest(binding);
    if (binding.phase === 'tool' && !this.db.prepare('SELECT key FROM operations WHERE key=?').get(key) &&
        this.db.prepare("SELECT COUNT(*) AS n FROM operations WHERE request=? AND json_extract(binding,'$.phase')='tool'").get(binding.requestId).n >= 32) throw new Error('request_tool_bound_reached');
    this.db.prepare("INSERT OR IGNORE INTO operations(key,request,binding,state) VALUES(?,?,?,'pending')").run(key, binding.requestId, canonical(binding));
    return this.db.prepare('SELECT * FROM operations WHERE key=?').get(key);
  }
  completedTools(requestId) {
    const rows = this.db.prepare("SELECT binding,result FROM operations WHERE request=? AND state='complete' ORDER BY rowid").all(requestId)
      .filter(row => JSON.parse(row.binding).phase === 'tool');
    if (rows.length > 32 || rows.some(row => !row.result)) throw new Error('completed_result_unavailable');
    const results = rows.map(row => ({ binding: JSON.parse(row.binding), result: JSON.parse(row.result) }));
    if (Buffer.byteLength(canonical(results)) > 131072) throw new Error('completed_results_too_large');
    return results;
  }
  transition(key, from, to, grant = null) {
    return this.db.prepare('UPDATE operations SET state=?,grant=COALESCE(?,grant) WHERE key=? AND state=?').run(to, grant, key, from).changes === 1;
  }
}

// This is deliberately NOT an email/caller-supplied decision. Only trusted host code may inject an adapter.
// A real adapter MUST authenticate its backend, validate its signed schema/expiry/binding and atomically
// consume the backend's one-use grant. The production adapter lives in production.mjs.
export const unconfiguredApproval = Object.freeze({ configured: false,
  async createProposal() { return null; }, async fetchDecision() { return { status: 'unconfigured' }; }, async consumeGrant() { return false; } });
export class Gate {
  constructor(store, adapter, signal) { this.store = store; this.adapter = adapter; this.signal = signal; this.pending = false; this.failed = false; this.reason = null; }
  stop(reason, failed = false) { this.pending = !failed; this.failed = failed; this.reason = reason; return false; }
  async authorize(binding) {
    this.signal?.throwIfAborted();
    if (this.pending || this.failed) return false;
    const row = this.store.operation(binding);
    if (row.state !== 'pending') return this.stop('operation_replayed_or_uncertain', true);
    if (!this.adapter?.configured) return this.stop('approval_backend_unconfigured');
    try {
      if (!row.proposal) {
        const proposal = text(await bounded(this.adapter.createProposal(Object.freeze({ digest: row.key, binding: JSON.parse(row.binding) }), this.signal), this.signal), 256, 1);
        this.signal?.throwIfAborted();
        this.store.db.prepare("UPDATE operations SET proposal=? WHERE key=? AND state='pending' AND proposal IS NULL").run(proposal, row.key);
        row.proposal = proposal;
      }
      const decision = closed(await bounded(this.adapter.fetchDecision(row.proposal, this.signal), this.signal), ['status'], ['digest', 'grantId', 'expiresAt']);
      this.signal?.throwIfAborted();
      if (decision.status === 'pending' || decision.status === 'unconfigured') return this.stop(`approval_${decision.status}`);
      if (decision.status !== 'approved') {
        this.store.transition(row.key, 'pending', 'denied');
        return this.stop('approval_denied_or_unknown', true);
      }
      if (decision.digest !== row.key || typeof decision.grantId !== 'string' || !/^[A-Za-z0-9_-]{1,200}$/.test(decision.grantId) || !Number.isSafeInteger(decision.expiresAt) || decision.expiresAt <= Date.now()) return this.stop('invalid_or_expired_grant', true);
      // Durable reservation BEFORE backend consumption or local effects; crashes here never automatically retry.
      if (!this.store.transition(row.key, 'pending', 'reserving', decision.grantId)) return this.stop('operation_replayed_or_uncertain', true);
      const consumed = await bounded(this.adapter.consumeGrant({ proposal: row.proposal, grantId: decision.grantId, digest: row.key, binding: JSON.parse(row.binding) }, this.signal), this.signal);
      this.signal?.throwIfAborted();
      if (consumed !== true || !this.store.transition(row.key, 'reserving', 'executing')) return this.stop('grant_consumption_failed', true);
      return true;
    } catch { return this.stop('approval_backend_failed', true); }
  }
  complete(binding, ok, result = null) {
    const snapshot = result === null ? null : canonical(result);
    if (snapshot && Buffer.byteLength(snapshot) > 32768) throw new Error('result_snapshot_too_large');
    if (!this.store.db.prepare("UPDATE operations SET state=?,result=? WHERE key=? AND state='executing'").run(ok ? 'complete' : 'unknown', snapshot, digest(binding)).changes) throw new Error('operation_state_mismatch');
    if (!ok) this.stop('tool_failed_or_uncertain', true);
  }
}

export function bindingFor(request, config, phase, operation) {
  return { version: 3, requestId: request.id, mailbox: request.mailbox, source: request.source,
    provider: config.provider, scope: config.scope, cwd: config.cwd, phase, operation,
    requestPreview: { from: request.input.from, subject: request.input.subject, body: Buffer.byteLength(request.input.body) > 8190 ? Buffer.from(request.input.body).subarray(0, 8170).toString('utf8') + '\n[truncated]' : request.input.body } };
}
// Policy grants are generated only by the host, never accepted from mail or model output.
export const policyGrant = binding => `host-safe-v1:${digest(binding)}`;
export function ownerSafe(request, config, operations = []) {
  validateConfig(config);
  return config.automaticReplies === true && Array.isArray(config.safeCapabilities) && Boolean(config.recipientPolicy) &&
    validateRecipientPolicy(config.recipientPolicy).allowedRecipients.includes(request.input.from) &&
    deliveryRecipient(request, config) === request.input.from && operations.every(op => config.safeCapabilities.includes(op.name));
}
export function automaticEligible(store, request, config, reply, now = Date.now()) {
  if (!ownerSafe(request, config) || reply.to !== request.input.from) return false;
  const row = store.get(request.id);
  if (row.context !== null || !['safe', 'reply'].includes(row.kind)) return false;
  const operations = store.db.prepare('SELECT * FROM operations WHERE request=?').all(request.id);
  if (operations.some(op => !['safe_plan', 'safe_tool', 'safe_reply', 'send'].includes(JSON.parse(op.binding).phase))) return false;
  const provenance = operations.filter(op => JSON.parse(op.binding).phase !== 'send');
  const plans = provenance.filter(op => JSON.parse(op.binding).phase === 'safe_plan');
  let plan = null;
  if (row.kind === 'safe') {
    if (plans.length !== 1) return false;
    plan = safePlan(JSON.parse(plans[0].binding).operation);
    if (!ownerSafe(request, config, plan.operations)) return false;
  } else if (plans.length || provenance.some(op => JSON.parse(op.binding).phase === 'safe_tool')) return false;
  const expected = [
    ...(plan ? [bindingFor(request, config, 'safe_plan', plan), ...plan.operations.map(op => bindingFor(request, config, 'safe_tool', { planDigest: digest(plan), ...op }))] : []),
    bindingFor(request, config, 'safe_reply', { kind: row.kind, planDigest: plan ? digest(plan) : null, replyDigest: digest(reply) }),
  ];
  if (provenance.length !== expected.length) return false;
  return expected.every(binding => {
    const op = provenance.find(entry => entry.key === digest(binding));
    if (!op || op.binding !== canonical(binding) || op.grant !== policyGrant(binding) || op.state !== 'complete') return false;
    if (binding.phase === 'safe_tool') {
      if (!op.result) return false;
      if (!safeFresh(binding.operation, JSON.parse(op.result), now)) return false;
    }
    return true;
  });
}
export async function reserveSend(store, id, config, adapter = unconfiguredApproval, signal, { currentConfig = () => config, now = Date.now } = {}) {
  config = currentConfig();
  validateConfig(config);
  const row = store.get(id);
  if (row.status !== 'reply_ready' || !row.reply) return { status: 'failed', reason: 'reply_not_ready' };
  const request = JSON.parse(row.input);
  if (request.mailbox !== config.mailbox) throw new Error('mailbox_mismatch');
  const reply = JSON.parse(row.reply);
  // Revalidate against CURRENT policy before even proposing/consuming a grant. Never silently reroute a persisted draft.
  if (config.recipientPolicy && reply.to !== deliveryRecipient(request, config)) return { status: 'failed', reason: 'recipient_policy_mismatch' };
  const binding = bindingFor(request, config, 'send', { sender: address(config.selfAddress), recipient: reply.to, subject: reply.subject, body: reply.body, bodyDigest: digest(reply.body) });
  // Never override ANY existing site proposal or non-pending delivery, even if safe mode was enabled later.
  const deliveries = store.db.prepare('SELECT * FROM operations WHERE request=?').all(id).filter(op => JSON.parse(op.binding).phase === 'send');
  if (deliveries.some(op => op.state !== 'pending')) return { status: 'failed', reason: 'operation_replayed_or_uncertain' };
  if (!deliveries.length && automaticEligible(store, request, config, reply, now())) {
    signal?.throwIfAborted();
    const fresh = currentConfig();
    if (!automaticEligible(store, request, fresh, reply, now()) || digest(bindingFor(request, fresh, 'send', binding.operation)) !== digest(binding)) return { status: 'failed', reason: 'automatic_policy_changed' };
    // One atomic insert also excludes concurrent/manual deliveries with a DIFFERENT binding. An existing
    // pending row without a proposal may be awaiting its backend response; it is never auto-adopted.
    const key = digest(binding);
    const reserved = store.db.prepare(`INSERT OR IGNORE INTO operations(key,request,binding,state,grant)
      SELECT ?,?,?,'reserving',? WHERE NOT EXISTS
      (SELECT 1 FROM operations WHERE request=? AND json_extract(binding,'$.phase')='send')`)
      .run(key, id, canonical(binding), policyGrant(binding), id).changes;
    if (!reserved) return { status: 'failed', reason: 'operation_replayed_or_uncertain' };
    // Re-read runtime policy at the reservation boundary too. Failed/uncertain reservations are terminal.
    if (!automaticEligible(store, request, currentConfig(), reply, now()) || !store.transition(key, 'reserving', 'executing')) return { status: 'failed', reason: 'automatic_policy_changed' };
    return { status: 'send_reserved', reservation: key, requestId: id, reply };
  }
  // Legacy, non-owner, private and previously proposed replies retain exact disclosure approval.
  const gate = new Gate(store, adapter, signal);
  if (!await gate.authorize(binding)) return { status: gate.failed ? 'failed' : 'approval_required', reason: gate.reason };
  return { status: 'send_reserved', reservation: digest(binding), requestId: id, reply };
}
export function finishSend(store, id, reservation, outcome) {
  if (!['sent', 'unknown'].includes(outcome)) throw new Error('invalid_send_outcome');
  const row = store.db.prepare('SELECT * FROM operations WHERE key=? AND request=?').get(reservation, id);
  if (!row || JSON.parse(row.binding).phase !== 'send' || !store.transition(reservation, 'executing', outcome === 'sent' ? 'sent' : 'send_unknown')) throw new Error('send_replayed_or_uncertain');
  return { status: outcome === 'sent' ? 'sent' : 'send_unknown', requestId: id };
}
