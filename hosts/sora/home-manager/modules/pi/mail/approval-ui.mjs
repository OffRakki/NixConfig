const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const pageSizes = [16, 32, 64, 128];
export const states = ['pending', 'approved', 'denied', 'consumed', 'expired'];

export function viewURL({ index = 0, size = 32, q = '', status = 'all' }) {
  const params = new URLSearchParams();
  if (q) params.set('q', q);
  if (status !== 'all') params.set('status', status);
  if (size !== 32) params.set('size', String(size));
  return `${index ? `/page/${index}` : '/'}${params.size ? `?${params}` : ''}`;
}

const style = `
:root{color-scheme:dark;--bg:#0b0e0f;--panel:#111617;--raised:#171e20;--line:#293335;--muted:#93a2a3;--text:#e2e8e5;--green:#b5e48b;--amber:#e4bd75;--red:#e99c96;--mono:ui-monospace,SFMono-Regular,Consolas,monospace;font:15px/1.6 system-ui,sans-serif;background:var(--bg);color:var(--text)}
*{box-sizing:border-box;border-radius:0!important}body{margin:0}button,input,select{font:inherit}button,a,input,select,summary{touch-action:manipulation}a{color:inherit;text-decoration:none}a:hover{color:var(--green)}button,.button{display:inline-flex;align-items:center;justify-content:center;gap:.6rem;border:1px solid var(--line);background:var(--raised);color:var(--text);padding:.65rem 1rem;cursor:pointer;font:12px/1.4 var(--mono)}button:hover,.button:hover{border-color:var(--green);color:var(--green)}:focus-visible{outline:2px solid var(--green);outline-offset:4px}button:disabled{opacity:.5;cursor:wait}.appbar{border-bottom:1px solid var(--line);background:#101516}.bar-inner{max-width:1200px;margin:auto;display:flex;justify-content:space-between;align-items:center;gap:1rem;padding:1rem 2rem}.brand{display:flex;gap:.85rem;align-items:center;font:12px var(--mono);letter-spacing:.08em}.brand-mark{border:1px solid var(--green);color:var(--green);padding:.45rem .55rem}.local-label{font:10px var(--mono);color:var(--muted);letter-spacing:.1em}.bar-actions{display:flex;align-items:center;gap:1.2rem}main{max-width:1200px;padding:2.75rem 2rem 4rem;margin:auto}.eyebrow{font:10px var(--mono);letter-spacing:.16em;text-transform:uppercase;color:var(--green);margin:0 0 .6rem}h1{font-size:clamp(2rem,4vw,3rem);line-height:1.15;letter-spacing:-.045em;font-weight:600;margin:0 0 .8rem}h2,h3,p{margin-top:0}.intro{display:flex;align-items:flex-end;justify-content:space-between;gap:2rem;margin-bottom:2rem}.intro p:last-child{margin-bottom:0}.muted,.hint{color:var(--muted)}.hint{font:11px/1.65 var(--mono)}.connection{font:11px var(--mono);color:var(--green);display:flex;align-items:center;gap:.6rem;white-space:nowrap}.connection:before{content:'';display:inline-block;width:6px;height:6px;background:currentColor}.connection[data-error=true]{color:var(--amber)}.metrics{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));border:1px solid var(--line);margin-bottom:1.5rem}.metric{padding:1rem 1.25rem;border-right:1px solid var(--line);position:relative}.metric:last-child{border-right:0}.metric[aria-current=true]{background:#18211a;box-shadow:inset 0 -2px var(--green)}.metric-label{display:block;color:var(--muted);font:10px var(--mono);letter-spacing:.08em;text-transform:uppercase}.metric-value{font:27px/1.6 var(--mono)}.metric[data-status=pending] .metric-value{color:var(--amber)}.filters{display:grid;grid-template-columns:minmax(0,1fr) 160px 140px auto;align-items:end;gap:.8rem;padding:1.25rem;background:var(--panel);border:1px solid var(--line)}label{display:block;font:10px var(--mono);color:var(--muted);text-transform:uppercase;letter-spacing:.07em}input,select{width:100%;display:block;min-height:42px;margin-top:.55rem;padding:.65rem .8rem;border:1px solid #354143;background:var(--bg);color:var(--text);font:13px var(--mono);letter-spacing:0;text-transform:none}input::placeholder{color:#788789}input[type=hidden]{display:none}select{cursor:pointer}.filter-actions{display:flex;align-items:center;gap:.5rem}.filter-actions button{min-height:42px}.filter-actions a{font:11px var(--mono);padding:.7rem .4rem}.search-help{margin:.65rem 0 1.8rem}.queue-summary{display:flex;justify-content:space-between;align-items:center;gap:1rem;margin-bottom:1rem;font:11px var(--mono);color:var(--muted)}.pagination{display:flex;align-items:center;gap:.4rem}.pagination a,.pagination span{padding:.4rem .65rem;border:1px solid var(--line)}.pagination span[aria-disabled=true]{opacity:.35}.queue{display:grid;gap:1rem}.request{border:1px solid var(--line);background:var(--panel);min-width:0}.request[data-state=pending]{border-left:2px solid var(--amber)}.request-top{display:flex;align-items:center;justify-content:space-between;gap:1rem;padding:.8rem 1.25rem;border-bottom:1px solid var(--line);background:#141a1c}.request-tags{display:flex;gap:.8rem;align-items:center;flex-wrap:wrap}.badge{font:10px/1.4 var(--mono);text-transform:uppercase;letter-spacing:.08em;border:1px solid #52605d;padding:.3rem .5rem;color:var(--muted)}[data-state=pending] .badge{color:var(--amber);border-color:#685538;background:#252117}[data-state=approved] .badge,[data-state=consumed] .badge{color:var(--green);border-color:#425c36;background:#1a2417}[data-state=denied] .badge{color:var(--red);border-color:#65433f;background:#261b1b}.phase{font:10px var(--mono);text-transform:uppercase;letter-spacing:.07em;color:var(--muted)}.expires{font:10px var(--mono);color:var(--muted)}.request-body{padding:1.4rem 1.25rem}.request h2{font-size:1.2rem;line-height:1.4;margin:0 0 .65rem;overflow-wrap:anywhere}.request-meta{display:flex;gap:1.2rem;flex-wrap:wrap;color:var(--muted);font:11px var(--mono);margin-bottom:1rem;overflow-wrap:anywhere}.request-meta b{font-weight:400;color:var(--text)}.identity{display:flex;align-items:center;gap:1rem;padding:.65rem .8rem;border:1px solid var(--line);background:var(--bg);margin-bottom:1.3rem;min-width:0}.identity code{font:10px/1.7 var(--mono);overflow-wrap:anywhere;flex:1;min-width:0;color:var(--muted)}.identity button{flex-shrink:0;font-size:10px;padding:.35rem .55rem}.field-label{font:10px var(--mono);letter-spacing:.1em;text-transform:uppercase;color:var(--muted)}h3{font:10px var(--mono);text-transform:uppercase;letter-spacing:.1em;color:var(--muted);margin:1rem 0 .7rem}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:var(--bg);border:1px solid #263133;padding:1rem;font:12px/1.8 var(--mono);max-height:420px;overflow:auto;margin:.7rem 0 0}details{border-top:1px solid var(--line);margin-top:1.1rem;padding-top:.9rem}summary{cursor:pointer;color:var(--muted);font:11px var(--mono)}summary:hover{color:var(--text)}details p{font:12px var(--mono);margin-top:1rem;overflow-wrap:anywhere}.actions{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:1rem;padding:1rem 1.25rem;border-top:1px solid var(--line);background:#12191a}.decision-form{display:flex;flex-wrap:wrap;gap:.6rem}.approve{background:var(--green);color:#162110;border-color:var(--green)}.approve:hover{background:#c7eea5;color:#162110}.deny:hover{border-color:var(--red);color:var(--red)}.empty{border:1px dashed #3a4849;padding:3rem 1.5rem;text-align:center;background:var(--panel)}.empty p{color:var(--muted);font:12px var(--mono);margin-bottom:0}.empty h2{font-size:1.15rem}.footer{margin-top:2rem;padding-top:1rem;border-top:1px solid var(--line);display:flex;justify-content:space-between;gap:1rem;color:var(--muted);font:10px var(--mono);letter-spacing:.05em}.login{max-width:460px;margin:3rem auto}.login-panel{border:1px solid var(--line);background:var(--panel);padding:1.75rem}.login-panel label{margin:1.2rem 0}.login-panel button{width:100%;margin-top:.5rem}.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap}
@media(max-width:760px){.bar-inner{padding:1rem}.local-label{display:none}main{padding:1.8rem 1rem 3rem}.intro{display:block}.connection{margin-top:1rem}.metrics{grid-template-columns:repeat(5,minmax(0,1fr))}.metric{padding:.7rem .45rem}.metric-value{font-size:22px}.metric-label{font-size:8px}.filters{grid-template-columns:1fr 1fr;padding:1rem}.search-field{grid-column:1/-1}.filter-actions{grid-column:1/-1;justify-content:flex-end}.request-top{align-items:flex-start;flex-direction:column;gap:.5rem}.request-body{padding:1rem}.request-meta{gap:.5rem}.queue-summary{align-items:flex-start;flex-direction:column}.actions{padding:1rem}.footer{flex-direction:column}.brand{font-size:10px}.bar-actions{gap:.5rem}}
`;

function shell(title, body, logout = '') {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(title)}</title><style>${style}</style></head><body><header class="appbar"><div class="bar-inner"><a class="brand" href="/"><span class="brand-mark">A/</span>APPROVAL CONSOLE</a><div class="bar-actions"><span class="local-label">LOCAL ACCESS ONLY</span>${logout}</div></div></header><main>${body}</main></body></html>`;
}
function form(action, csrf, fields, buttons, className = '') {
  return `<form method="post" action="${action}" class="${className}"><input type="hidden" name="csrf" value="${escape(csrf)}">${fields}${buttons}</form>`;
}
export function renderLogin(csrf) {
  return shell('Mail approval — owner login', `<div class="login"><p class="eyebrow">Owner authentication</p><h1>Access the queue.</h1><p class="muted">A private checkpoint for exact-operation approvals.</p><div class="login-panel">${form('/login', csrf, '<label>Username<input name="username" autocomplete="username" required maxlength="32"></label><label>Password<input type="password" name="password" autocomplete="current-password" required maxlength="256"></label>', '<button class="approve">Log in</button>')}<p class="hint" style="margin-top:1.3rem;margin-bottom:0">OWNER / lucky<br>Password managed through SOPS.</p></div></div>`);
}
function preview(binding) {
  const op = binding.operation;
  const operation = binding.phase === 'send'
    ? `<h3>Email to send</h3><div class="request-meta"><span>From <b>${escape(op.sender)}</b></span><span>To <b>${escape(op.recipient)}</b></span></div><p>${escape(op.subject)}</p><pre>${escape(op.body)}</pre>`
    : `<h3>${binding.phase === 'investigate' ? 'Personal-context investigation' : 'Exact tool operation'}</h3><pre>${escape(JSON.stringify(op, null, 2))}</pre>`;
  return `${operation}<details><summary>Original request</summary><p>From: ${escape(binding.requestPreview.from)}<br>Subject: ${escape(binding.requestPreview.subject)}</p><pre>${escape(binding.requestPreview.body)}</pre></details><details><summary>Full immutable authorization binding</summary><pre>${escape(JSON.stringify(binding, null, 2))}</pre></details>`;
}
function card(row, csrf, returnTo) {
  const binding = JSON.parse(row.binding);
  const phase = { send: 'Email delivery', tool: 'Tool execution', investigate: 'Context access' }[binding.phase] ?? binding.phase;
  const expires = new Date(row.expires).toISOString();
  const fields = `<input type="hidden" name="id" value="${row.id}"><input type="hidden" name="returnTo" value="${escape(returnTo)}">`;
  const actions = row.state === 'pending' ? `<div class="actions"><span class="hint">Exact operation. One use only.</span>${form('/decide', csrf, fields, '<button class="approve" name="decision" value="approved">Approve exact operation once</button><button class="deny" name="decision" value="denied">Deny</button>', 'decision-form')}</div>` : '';
  return `<section class="request" id="proposal-${row.id}" data-state="${escape(row.state)}"><header class="request-top"><div class="request-tags"><span class="badge">${escape(row.state)}</span><span class="phase">${escape(phase)}</span></div><span class="expires">Expires <time datetime="${expires}">${escape(expires.replace('T', ' ').replace('.000Z', ' UTC'))}</time></span></header><div class="request-body"><h2>${escape(binding.requestPreview.subject || 'Untitled request')}</h2><div class="request-meta"><span>FROM <b>${escape(binding.requestPreview.from)}</b></span><span>PROVIDER <b>${escape(binding.provider)}</b></span></div><div class="identity"><code><span class="field-label">SHA256 / </span>${row.id}</code><button type="button" data-copy="${row.id}" aria-label="Copy request hash">Copy hash</button></div>${preview(binding)}</div>${actions}</section>`;
}
export function renderDashboard({ rows, counts, total, index, size, q, status, csrf }) {
  const view = { index, size, q, status };
  const url = viewURL(view);
  const count = state => state === 'all' ? Object.values(counts).reduce((sum, n) => sum + n, 0) : counts[state] ?? 0;
  const metrics = ['all', 'pending', 'approved', 'denied', 'expired'].map(state => `<a class="metric" data-status="${state}" aria-current="${status === state}" href="${escape(viewURL({ ...view, index: 0, status: state }))}"><span class="metric-label">${state === 'all' ? 'All requests' : state}</span><span class="metric-value">${count(state)}</span></a>`).join('');
  const option = (value, selected, label = value) => `<option value="${value}"${value === selected ? ' selected' : ''}>${escape(label)}</option>`;
  const first = total && rows.length ? index * size + 1 : 0;
  const last = rows.length ? index * size + rows.length : 0;
  const pages = Math.max(1, Math.ceil(total / size));
  const link = (label, target, enabled) => enabled ? `<a href="${escape(viewURL({ ...view, index: target }))}">${label}</a>` : `<span aria-disabled="true">${label}</span>`;
  const summary = `<div class="queue-summary" id="queue-summary"><span>${first}–${last} of ${total} matching requests${q ? ' · ranked by relevance' : ' · newest first'}</span><nav class="pagination" aria-label="Request pages">${link('Latest', 0, index > 0)}${link('Newer', Math.max(0, index - 1), index > 0)}<span>Page ${index + 1} / ${pages}</span>${link('Older', Math.min(999999, index + 1), (index + 1) * size < total)}</nav></div>`;
  const filters = `<form method="get" action="/" id="queue-filters" class="filters"><label class="search-field">Fuzzy search<input type="search" name="q" value="${escape(q)}" placeholder="Hash, sender, subject, command, or content…" maxlength="256" autocomplete="off" spellcheck="false"></label><label>Status<select name="status">${['all', ...states].map(state => option(state, status, state === 'all' ? 'All statuses' : state[0].toUpperCase() + state.slice(1))).join('')}</select></label><label>Per page<select name="size">${pageSizes.map(n => option(String(n), String(size), `${n} requests`)).join('')}</select></label><div class="filter-actions"><button type="submit">Apply filters</button><a href="/">Reset</a></div></form><p class="hint search-help">Fuzzy, case-insensitive search across every request—not just this page. Multiple terms narrow the results.</p>`;
  const content = `<div class="intro"><div><p class="eyebrow">Owner workspace / mail operations</p><h1>Request queue.</h1><p class="muted">Review the intent. Authorize the exact operation.</p></div><span id="live-status" class="connection" role="status">Live · 3s updates</span></div><div class="metrics" id="queue-counts">${metrics}</div>${filters}${summary}<div id="proposals" class="queue">${rows.map(row => card(row, csrf, url)).join('')}</div><div id="queue-empty">${rows.length ? '' : '<div class="empty"><p class="eyebrow">QUEUE / EMPTY</p><h2>No requests in this view.</h2><p>Try another search, clear the status filter, or return to the latest page.</p></div>'}</div><noscript><p class="hint">JavaScript is disabled. Apply filters and refresh manually for updates.</p></noscript><footer class="footer"><span>AUTHORIZATION / EXACT BINDING / SINGLE USE</span><span>No action runs without its required approval.</span></footer><script src="/dashboard.js" defer></script>`;
  return shell('Mail approval — lucky', content, form('/logout', csrf, '', '<button>Log out</button>'));
}

export const dashboardScript = `
const list = document.getElementById('proposals');
const status = document.getElementById('live-status');
const filters = document.getElementById('queue-filters');
let busy = false, pendingFilters = false, generation = 0, debounce, controller;
let desiredURL = location.pathname + location.search;
async function refresh(url = desiredURL, updateURL = false) {
  if (!updateURL && (busy || pendingFilters || document.hidden)) return;
  const current = ++generation;
  controller?.abort(); controller = new AbortController();
  busy = true; list.setAttribute('aria-busy', 'true');
  try {
    const response = await fetch(url, { cache: 'no-store', signal: AbortSignal.any([controller.signal, AbortSignal.timeout(10000)]) });
    if (current !== generation) return;
    if (response.redirected) { location.assign('/login'); return; }
    if (!response.ok) throw new Error('refresh_failed');
    const page = new DOMParser().parseFromString(await response.text(), 'text/html');
    if (current !== generation) return;
    const next = page.getElementById('proposals');
    if (!next) throw new Error('invalid_dashboard');
    // Immutable cards keep their DOM, open details, and keyboard focus unless their state changed.
    const keep = new Set();
    let cursor = list.firstElementChild;
    for (const incoming of [...next.children]) {
      const existing = document.getElementById(incoming.id);
      let card = existing;
      if (!existing || existing.dataset.state !== incoming.dataset.state) {
        if (existing) {
          const open = [...existing.querySelectorAll('details')].map(detail => detail.open);
          incoming.querySelectorAll('details').forEach((detail, index) => { detail.open = open[index]; });
          existing.replaceWith(incoming);
          if (cursor === existing) cursor = incoming;
        }
        card = incoming;
      }
      // A decision's redirect must follow the current filtered view, even on retained cards.
      const returnTo = card.querySelector('input[name=returnTo]');
      if (returnTo) returnTo.value = url;
      if (card !== cursor) list.insertBefore(card, cursor);
      cursor = card.nextElementSibling;
      keep.add(card.id);
    }
    for (const card of [...list.children]) if (!keep.has(card.id)) card.remove();
    for (const id of ['queue-summary', 'queue-counts', 'queue-empty']) {
      const existing = document.getElementById(id), incoming = page.getElementById(id);
      if (!incoming) throw new Error('invalid_dashboard');
      if (existing.innerHTML !== incoming.innerHTML) existing.replaceChildren(...incoming.childNodes);
    }
    if (url !== location.pathname + location.search) history.pushState(null, '', url);
    status.textContent = 'Live · 3s updates'; status.dataset.error = 'false';
  } catch (error) {
    if (current === generation && error.name !== 'AbortError') {
      status.textContent = 'Update failed · retrying'; status.dataset.error = 'true';
    }
  } finally {
    if (current === generation) { busy = false; pendingFilters = false; list.removeAttribute('aria-busy'); }
  }
}
function applyFilters() {
  clearTimeout(debounce);
  desiredURL = '/?' + new URLSearchParams(new FormData(filters));
  void refresh(desiredURL, true);
}
filters.addEventListener('submit', event => { event.preventDefault(); applyFilters(); });
filters.querySelector('input[name=q]').addEventListener('input', () => {
  pendingFilters = true; ++generation; controller?.abort(); busy = false;
  clearTimeout(debounce); debounce = setTimeout(applyFilters, 250);
});
filters.querySelectorAll('select').forEach(select => select.addEventListener('change', applyFilters));
window.addEventListener('popstate', () => {
  clearTimeout(debounce); pendingFilters = false;
  const params = new URLSearchParams(location.search);
  filters.elements.q.value = params.get('q') || '';
  filters.elements.status.value = params.get('status') || 'all';
  filters.elements.size.value = params.get('size') || '32';
  desiredURL = location.pathname + location.search;
  void refresh(desiredURL, true);
});
document.addEventListener('click', async event => {
  const button = event.target.closest('button[data-copy]');
  if (!button) return;
  try { await navigator.clipboard.writeText(button.dataset.copy); button.textContent = 'Copied'; }
  catch { button.textContent = 'Select hash to copy'; }
  setTimeout(() => { button.textContent = 'Copy hash'; }, 1800);
});
setInterval(refresh, 3000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) void refresh(); });
`;
