import { closeSync, constants, fstatSync, openSync, readFileSync } from 'node:fs';
import { isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import { canonical, closed, decodeEnvelope, deliveryRecipient, digest, finishSend, reserveSend, Store, text, validateConfig, validateRecipientPolicy } from './core.mjs';
import { equal, signDecision, validateProposal } from './approval-server.mjs';
import { cli as offlineCli, runMail, sdkModules } from './runner.mjs';

export function createApprovalAdapter({ token, endpoint = 'http://127.0.0.1:8765', fetchImpl = fetch }) {
  text(token, 256, 32);
  const url = new URL(endpoint);
  if (url.hostname !== '127.0.0.1' || url.protocol !== 'http:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash) throw new Error('invalid_approval_endpoint');
  async function request(path, value, outer) {
    const signal = outer ? AbortSignal.any([outer, AbortSignal.timeout(5000)]) : AbortSignal.timeout(5000);
    const res = await fetchImpl(`${url.origin}${path}`, { method: value ? 'POST' : 'GET', headers: { Authorization: `Bearer ${token}`, ...(value ? { 'Content-Type': 'application/json' } : {}) }, body: value ? canonical(value) : undefined, redirect: 'error', signal });
    if (!res.ok || !res.headers.get('content-type')?.startsWith('application/json')) throw new Error('approval_http_failed');
    const reader = res.body.getReader(); const chunks = []; let size = 0;
    try {
      while (true) { const { done, value: chunk } = await reader.read(); if (done) break; size += chunk.length; if (size > 131072) throw new Error('approval_response_limit'); chunks.push(chunk); }
      return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks)));
    } finally { await reader.cancel(); }
  }
  const id = value => { if (typeof value !== 'string' || !/^[a-f0-9]{64}$/.test(value)) throw new Error('invalid_proposal_id'); return value; };
  return { configured: true,
    async createProposal(value, signal) { validateProposal(value); const result = closed(await request('/api/v1/proposals', value, signal), ['id']); if (id(result.id) !== value.digest) throw new Error('proposal_id_mismatch'); return result.id; },
    async fetchDecision(proposal, signal) {
      const result = closed(await request(`/api/v1/proposals/${id(proposal)}/decision`, null, signal), ['decision', 'signature']);
      const d = closed(result.decision, ['status', 'digest', 'binding', 'grantId', 'expiresAt']);
      if (typeof result.signature !== 'string' || !equal(result.signature, signDecision(d, token)) || d.digest !== proposal || digest(d.binding) !== proposal || !['pending', 'approved', 'denied', 'expired', 'consumed'].includes(d.status) || !Number.isSafeInteger(d.expiresAt)) throw new Error('invalid_signed_decision');
      validateProposal({ digest: d.digest, binding: d.binding });
      if (d.status === 'approved') {
        if (typeof d.grantId !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(d.grantId) || d.expiresAt <= Date.now()) throw new Error('invalid_grant');
        return { status: d.status, digest: d.digest, grantId: d.grantId, expiresAt: d.expiresAt };
      }
      if (d.grantId !== null) throw new Error('unexpected_grant');
      return { status: d.status };
    },
    async consumeGrant({ proposal, digest: key, binding, grantId }, signal) {
      if (id(proposal) !== key) throw new Error('consume_mismatch'); validateProposal({ digest: key, binding });
      const result = closed(await request(`/api/v1/proposals/${proposal}/consume`, { digest: key, binding, grantId }, signal), ['consumed']);
      if (typeof result.consumed !== 'boolean') throw new Error('invalid_consumption'); return result.consumed;
    },
  };
}
export function productionProvider(authPath, sdkRoot) {
  if (authPath !== '/home/rakki/.pi/agent/auth.json') throw new Error('invalid_auth_path');
  return async signal => {
    const { sdk } = await sdkModules(sdkRoot);
    const modelRuntime = await sdk.ModelRuntime.create({ authPath, modelsPath: null, refreshOnCreate: false, allowModelNetwork: false, signal });
    const model = modelRuntime.getModel('openai-codex', 'gpt-6.1-sol');
    if (!model) throw new Error('configured_model_unavailable');
    return { modelRuntime, model };
  };
}
export function loadRecipientPolicy(path) {
  if (typeof path !== 'string' || !isAbsolute(path) || path.startsWith('/nix/store/')) throw new Error('runtime_recipient_policy_required');
  // sops-nix uses a symlink to its runtime generation: validate the opened target, not the link.
  const fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK);
  try {
    const stat = fstatSync(fd);
    if (!stat.isFile() || ![0, process.getuid()].includes(stat.uid) || (stat.mode & 0o077) || stat.size > 16384) throw new Error('insecure_recipient_policy');
    return validateRecipientPolicy(JSON.parse(readFileSync(fd, 'utf8')));
  } finally { closeSync(fd); }
}
export async function productionCli(args, host, dependencies = {}) {
  if (args.length === 1 && ['--help', '--selftest'].includes(args[0])) return args[0] === '--selftest' ? offlineCli(args) : { version: 1, status: 'configured', usage: 'mail-assistant-runner process CANONICAL_BASE64 | resume REQUEST_SHA256 | status REQUEST_SHA256 | send-reserve CANONICAL_BASE64 | send-finish CANONICAL_BASE64 | --selftest' };
  closed(host, ['config', 'stateDirectory', 'authPath', 'tokenFile', 'endpoint', 'recipientPolicyFile']); validateConfig(host.config);
  if (host.endpoint !== 'http://127.0.0.1:8765' || host.config.provider !== 'openai-codex/gpt-6.1-sol') throw new Error('invalid_production_config');
  if (args.length !== 2 || !['process', 'resume', 'status', 'send-reserve', 'send-finish'].includes(args[0])) throw new Error('invalid_cli_arguments');
  const store = new Store(host.stateDirectory);
  try {
    if (args[0] === 'status') return store.result(args[1]);
    // The secret policy is host-only data: never mail input, a model prompt, or a Nix-store value.
    const currentConfig = () => {
      const recipientPolicy = loadRecipientPolicy(host.recipientPolicyFile);
      // Runtime policy owns ALL automatic authority, including defaults-off legacy policies.
      return { ...host.config, recipientPolicy, safeCapabilities: recipientPolicy.safeCapabilities, automaticReplies: recipientPolicy.automaticReplies };
    };
    const config = currentConfig();
    // Credentials are loaded only for real commands, never help/selftest or status.
    const backend = dependencies.approval ?? createApprovalAdapter({ token: readFileSync(host.tokenFile, 'utf8').trim(), endpoint: host.endpoint });
    const currentRecipientAllowed = binding => binding.phase !== 'send' || deliveryRecipient(JSON.parse(store.get(binding.requestId).input), {
      recipientPolicy: loadRecipientPolicy(host.recipientPolicyFile),
    }) === binding.operation.recipient;
    const approval = { ...backend, async consumeGrant(value, signal) {
      // A policy revoked while awaiting the owner's decision must never consume a grant or reserve SMTP.
      if (!currentRecipientAllowed(value.binding)) return false;
      const consumed = await backend.consumeGrant(value, signal);
      // Also close the async backend-consumption window before committing the local reservation.
      return consumed === true && currentRecipientAllowed(value.binding);
    } };
    if (['process', 'resume'].includes(args[0])) {
      if (args[0] === 'resume') store.get(args[1]);
      return await runMail({ store, ...(args[0] === 'process' ? { raw: decodeEnvelope(args[1]) } : { id: args[1] }), config, approval, provider: dependencies.provider ?? productionProvider(host.authPath, dependencies.sdkRoot), sdkRoot: dependencies.sdkRoot, currentConfig, safeDependencies: dependencies.safeDependencies });
    }
    const payload = decodeEnvelope(args[1]);
    closed(payload, args[0] === 'send-reserve' ? ['requestId'] : ['requestId', 'reservation', 'outcome']);
    store.get(payload.requestId);
    if (args[0] === 'send-reserve') {
      const result = await reserveSend(store, payload.requestId, config, approval, AbortSignal.timeout(10000), { currentConfig });
      return { version: 1, requestId: payload.requestId, status: result.status, reason: result.reason ?? null, reply: result.reply ?? null, ...(result.reservation ? { reservation: result.reservation } : {}) };
    }
    if (!/^[a-f0-9]{64}$/.test(payload.reservation)) throw new Error('invalid_reservation');
    const result = finishSend(store, payload.requestId, payload.reservation, payload.outcome);
    return { version: 1, requestId: payload.requestId, status: result.status, reason: null, reply: null };
  } finally { store.close(); }
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv[2] !== '--config-file' || !process.argv[3]) throw new Error('host_config_required');
    const args = process.argv.slice(4);
    const host = args.length === 1 && ['--help', '--selftest'].includes(args[0]) ? null : JSON.parse(readFileSync(process.argv[3], 'utf8'));
    process.stdout.write(canonical(await productionCli(args, host)) + '\n');
  } catch { process.stdout.write(canonical({ version: 1, requestId: null, status: 'failed', reason: 'invalid_input_or_local_configuration', reply: null }) + '\n'); process.exitCode = 1; }
}
