// Builds a separate inactive workflow. Credential references are supplied by the authenticated
// installer, never exported credential secrets. IMAP starts disabled to avoid processing Mail's inbox twice.
const runner = '/home/rakki/.nix-profile/bin/mail-assistant-runner';
const code = fn => `return (${fn.toString()})();`;

export function prepareEnvelope() {
  const items = $input.all();
  if (items.length !== 1) throw new Error('one_email_required');
  const item = items[0], v = item.json;
  if (Object.keys(item.binary || {}).length) throw new Error('attachments_unsupported');
  let raw;
  if (v.version === 1) raw = v;
  else {
    if (!Array.isArray(v.from?.value) || v.from.value.length !== 1 || typeof v.text !== 'string') throw new Error('resolved_plain_email_required');
    raw = { version: 1, messageId: v.messageId ?? null, from: v.from.value[0].address,
      subject: v.subject ?? '', body: v.text, autoSubmitted: v.headers?.['auto-submitted'] ?? '',
      precedence: v.headers?.precedence ?? '', attachments: [] };
  }
  function canonical(v) {
    if (v === null || typeof v === 'boolean' || typeof v === 'string' || (typeof v === 'number' && Number.isFinite(v))) return JSON.stringify(v);
    if (Array.isArray(v)) return '[' + v.map(canonical).join(',') + ']';
    // n8n's task-runner inputs may come from another VM realm; prototype identity is not a JSON validity check.
    if (v && typeof v === 'object' && !Object.keys(v).some(k => ['__proto__', 'prototype', 'constructor'].includes(k))) return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canonical(v[k])).join(',') + '}';
    throw new Error('invalid_json');
  }
  const json = canonical(raw);
  if (Buffer.byteLength(json) > 131072) throw new Error('email_too_large');
  return [{ json: { payload: Buffer.from(json).toString('base64'), deadline: Date.now() + 16 * 60 * 1000 } }];
}

export function validateDraft() {
  const input = $input.all();
  if (input.length !== 1) throw new Error('one_result_required');
  const { code: exit, stdout } = input[0].json;
  if (exit !== 0 || typeof stdout !== 'string' || Buffer.byteLength(stdout) > 131072) throw new Error('runner_failed');
  const v = JSON.parse(stdout);
  if (!v || v.version !== 1 || !['approval_required', 'reply_ready', 'failed', 'rejected'].includes(v.status) || !/^[a-f0-9]{64}$/.test(v.requestId)) throw new Error('invalid_runner_result');
  if (v.status === 'reply_ready') {
    const e = v.reply;
    if (!e || typeof e.to !== 'string' || !/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(e.to) || /[\r\n\0]/.test(e.to) || typeof e.subject !== 'string' || /[\r\n\0]/.test(e.subject) || typeof e.body !== 'string' || e.body.includes('\0') || Buffer.byteLength(e.body) > 16384) throw new Error('invalid_reply');
  } else if (v.reply !== null) throw new Error('unexpected_reply');
  const deadline = $('Prepare envelope').first().json.deadline;
  if (!Number.isSafeInteger(deadline) || Date.now() >= deadline) throw new Error('approval_window_expired');
  return [{ json: { ...v, deadline, approvalUrl: 'http://127.0.0.1:8765/' } }];
}

export function prepareResume() {
  const v = $input.first().json;
  if (!/^[a-f0-9]{64}$/.test(v.requestId) || v.status !== 'approval_required' || Date.now() >= v.deadline) throw new Error('invalid_or_expired_resume');
  return [{ json: { requestId: v.requestId } }];
}

export function prepareSend() {
  const v = $input.first().json;
  if (v.status !== 'reply_ready' || !/^[a-f0-9]{64}$/.test(v.requestId)) throw new Error('draft_not_ready');
  return [{ json: { payload: Buffer.from(JSON.stringify({ requestId: v.requestId })).toString('base64') } }];
}

export function validateSend() {
  const input = $input.all();
  if (input.length !== 1) throw new Error('one_result_required');
  const r = input[0].json;
  if (r.code !== 0 || typeof r.stdout !== 'string' || Buffer.byteLength(r.stdout) > 131072) throw new Error('send_reservation_failed');
  const v = JSON.parse(r.stdout);
  if (v.version !== 1 || !/^[a-f0-9]{64}$/.test(v.requestId) || !['approval_required', 'send_reserved', 'failed'].includes(v.status)) throw new Error('invalid_send_result');
  if (v.status === 'send_reserved') {
    const e = v.reply;
    if (!/^[a-f0-9]{64}$/.test(v.reservation) || !e || typeof e.to !== 'string' || !/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(e.to) || /[\r\n\0]/.test(e.to) || typeof e.subject !== 'string' || /[\r\n\0]/.test(e.subject) || typeof e.body !== 'string' || e.body.includes('\0') || Buffer.byteLength(e.body) > 16384) throw new Error('invalid_reserved_reply');
  }
  const deadline = $('Prepare envelope').first().json.deadline;
  if (!Number.isSafeInteger(deadline) || Date.now() >= deadline) throw new Error('approval_window_expired');
  return [{ json: { ...v, deadline, approvalUrl: 'http://127.0.0.1:8765/' } }];
}

export function retrySend() {
  const v = $input.first().json;
  if (v.status !== 'approval_required' || !/^[a-f0-9]{64}$/.test(v.requestId) || Date.now() >= v.deadline) throw new Error('invalid_or_expired_send_poll');
  return [{ json: { payload: Buffer.from(JSON.stringify({ requestId: v.requestId })).toString('base64') } }];
}

export function prepareOutcome(outcome, reservations) {
  if (!Array.isArray(reservations) || reservations.length !== 1) throw new Error('one_delivery_reservation_required');
  const v = reservations[0].json;
  if (v.status !== 'send_reserved' || !/^[a-f0-9]{64}$/.test(v.requestId) || !/^[a-f0-9]{64}$/.test(v.reservation) || !['sent', 'unknown'].includes(outcome)) throw new Error('invalid_delivery_reservation');
  const payload = JSON.stringify({ outcome, requestId: v.requestId, reservation: v.reservation });
  return [{ json: { payload: Buffer.from(payload).toString('base64') } }];
}

export function buildMailWorkflow({ ssh, imap, smtp, recipient = 'me@ore.rs' } = {}) {
  const nodes = [], connections = {};
  const add = (name, type, typeVersion, parameters, position, extra = {}) => {
    nodes.push({ id: name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), name, type, typeVersion, parameters, position, ...extra });
  };
  const link = (source, target, output = 0) => {
    const main = (connections[source] ??= { main: [] }).main;
    while (main.length <= output) main.push([]);
    main[output].push({ node: target, type: 'main', index: 0 });
  };
  const js = (name, source, position) => add(name, 'n8n-nodes-base.code', 2, { jsCode: source }, position);
  const sshNode = (name, command, position) => add(name, 'n8n-nodes-base.ssh', 1,
    { authentication: 'privateKey', command }, position, { retryOnFail: false, ...(ssh ? { credentials: { sshPrivateKey: ssh } } : { disabled: true }) });
  const route = (name, expression, position) => add(name, 'n8n-nodes-base.switch', 3.4,
    { mode: 'expression', numberOutputs: 3, output: expression }, position);
  const wait = (name, position) => add(name, 'n8n-nodes-base.wait', 1.1, { resume: 'timeInterval', amount: 5, unit: 'seconds' }, position);
  add('Run approval test', 'n8n-nodes-base.manualTrigger', 1, {}, [0, 0]);
  js('Sample email — edit to test', `return [{json:{version:1,messageId:'<approval-test-'+$execution.id+'-'+Date.now()+'@local.invalid>',from:${JSON.stringify(recipient)},subject:'Mail assistant approval test',body:'Please reply with a short confirmation that this approval test worked. Do not read private files or perform computer actions.',autoSubmitted:'no',precedence:'',attachments:[]}}];`, [220, 0]);
  add('IMAP — disabled while Mail is active', 'n8n-nodes-base.emailReadImap', 2.2,
    { format: 'resolved', options: { trackLastMessageId: true } }, [0, 260], { disabled: true, ...(imap ? { credentials: { imap } } : {}) });
  js('Prepare envelope', code(prepareEnvelope), [440, 0]);
  sshNode('Run isolated assistant', `=${runner} process '{{ $json.payload }}'`, [660, 0]);
  js('Validate draft', code(validateDraft), [880, 0]);
  route('Draft status', "={{ $json.status === 'reply_ready' ? 0 : $json.status === 'approval_required' ? 1 : 2 }}", [1100, 0]);
  wait('Wait for owner decision', [1100, 260]);
  js('Prepare resume', code(prepareResume), [880, 260]);
  sshNode('Resume approved request', `=${runner} resume '{{ $json.requestId }}'`, [660, 260]);
  js('Prepare send request', code(prepareSend), [1320, 0]);
  sshNode('Reserve approved delivery', `=${runner} send-reserve '{{ $json.payload }}'`, [1540, 0]);
  js('Validate send reservation', code(validateSend), [1760, 0]);
  route('Delivery status', "={{ $json.status === 'send_reserved' ? 0 : $json.status === 'approval_required' ? 1 : 2 }}", [1980, 0]);
  wait('Wait for disclosure approval', [1980, 260]);
  js('Prepare delivery poll', code(retrySend), [1760, 260]);
  add('Send approved email', 'n8n-nodes-base.emailSend', 2.1,
    { fromEmail: 'ciel@ore.rs', toEmail: '={{ $json.reply.to }}', subject: '={{ $json.reply.subject }}', emailFormat: 'text', text: '={{ $json.reply.body }}', options: { appendAttribution: false } },
    [2200, 0], { retryOnFail: false, onError: 'continueErrorOutput', ...(smtp ? { credentials: { smtp } } : { disabled: true }) });
  // Keep the literal $ selector visible to n8n's task-runner dependency scanner.
  // The latest run (-1) is the reservation, not the first pending approval poll; SMTP drops paired-item lineage.
  js('Prepare sent receipt', `return (${prepareOutcome.toString()})('sent', $('Validate send reservation').all(0, -1));`, [2420, 0]);
  js('Prepare uncertain receipt', `return (${prepareOutcome.toString()})('unknown', $('Validate send reservation').all(0, -1));`, [2420, 260]);
  sshNode('Record delivery outcome', `=${runner} send-finish '{{ $json.payload }}'`, [2640, 0]);
  add('Stopped — inspect status', 'n8n-nodes-base.noOp', 1, {}, [1320, 500]);
  add('How to test', 'n8n-nodes-base.stickyNote', 1, { content: '## Mail approval test\nClick **Run approval test**. Open http://127.0.0.1:8765/ and log in to review pending requests. Nothing sends until the exact delivery is approved. Edit the sample email to request a personal action; investigation and each tool require separate approval.\n\nIMAP remains disabled because the existing Mail workflow still processes that inbox. This workflow remains unpublished. Denied or expired requests stop; uncertain actions/delivery never retry automatically.', height: 280, width: 600 }, [0, -350]);
  link('Run approval test', 'Sample email — edit to test'); link('Sample email — edit to test', 'Prepare envelope');
  link('IMAP — disabled while Mail is active', 'Prepare envelope'); link('Prepare envelope', 'Run isolated assistant');
  link('Run isolated assistant', 'Validate draft'); link('Validate draft', 'Draft status');
  link('Draft status', 'Prepare send request', 0); link('Draft status', 'Wait for owner decision', 1); link('Draft status', 'Stopped — inspect status', 2);
  link('Wait for owner decision', 'Prepare resume'); link('Prepare resume', 'Resume approved request'); link('Resume approved request', 'Validate draft');
  link('Prepare send request', 'Reserve approved delivery'); link('Reserve approved delivery', 'Validate send reservation'); link('Validate send reservation', 'Delivery status');
  link('Delivery status', 'Send approved email', 0); link('Delivery status', 'Wait for disclosure approval', 1); link('Delivery status', 'Stopped — inspect status', 2);
  link('Wait for disclosure approval', 'Prepare delivery poll'); link('Prepare delivery poll', 'Reserve approved delivery');
  link('Send approved email', 'Prepare sent receipt', 0); link('Send approved email', 'Prepare uncertain receipt', 1);
  link('Prepare sent receipt', 'Record delivery outcome'); link('Prepare uncertain receipt', 'Record delivery outcome');
  return { name: 'Mail_Approval_Test', active: false, nodes, connections,
    settings: { executionOrder: 'v1', availableInMCP: true, saveDataSuccessExecution: 'none', saveDataErrorExecution: 'none', executionTimeout: 1020 } };
}

export function workflowSdkCode(options) {
  const graph = buildMailWorkflow(options);
  const literal = value => {
    if (typeof value === 'string' && value.startsWith('=')) return `expr(${JSON.stringify(value)})`;
    if (Array.isArray(value)) return `[${value.map(literal).join(',')}]`;
    if (value && typeof value === 'object') return `{${Object.entries(value).map(([k, v]) => `${JSON.stringify(k)}:${literal(v)}`).join(',')}}`;
    return JSON.stringify(value);
  };
  const lines = ["import { workflow, node, trigger, expr, newCredential } from '@n8n/workflow-sdk';"];
  const names = new Map(graph.nodes.map((n, i) => [n.name, `n${i}`]));
  for (const n of graph.nodes) {
    const { type, typeVersion, id, ...config } = n;
    const credentials = config.credentials;
    delete config.credentials;
    let source = literal(config);
    if (credentials) source = source.slice(0, -1) + ',credentials:{' + Object.entries(credentials).map(([type, ref]) => `${JSON.stringify(type)}:newCredential(${JSON.stringify(ref.name)},${JSON.stringify(ref.id)})`).join(',') + '}}';
    const factory = ['n8n-nodes-base.manualTrigger', 'n8n-nodes-base.emailReadImap'].includes(type) ? 'trigger' : 'node';
    lines.push(`const ${names.get(n.name)} = ${factory}({type:${JSON.stringify(type)},version:${typeVersion},config:${source}});`);
  }
  lines.push(`export default workflow('mail-approval-test',${JSON.stringify(graph.name)},${literal(graph.settings)})`);
  for (const n of graph.nodes) lines.push(`.add(${names.get(n.name)})`);
  for (const [source, connections] of Object.entries(graph.connections)) for (const [output, targets] of connections.main.entries()) for (const target of targets) lines.push(`.connect(${names.get(source)},${output},${names.get(target.node)},${target.index})`);
  lines.push(';');
  return lines.join('\n');
}
