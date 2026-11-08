import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';

// Only normalized usage and fixed error messages leave this process, never auth.
export function normalize(body, now = Date.now()) {
  const limits = body?.rate_limit;
  const windows = [];
  for (const [key, label] of [['primary_window', '5h'], ['secondary_window', 'weekly']]) {
    const window = limits?.[key];
    if (!window) continue;
    if (typeof window.used_percent !== 'number' || !Number.isFinite(window.used_percent)) {
      throw new Error('Invalid usage response');
    }
    const seconds = window.limit_window_seconds;
    const actualLabel = seconds === 604800 ? 'weekly' : seconds === 18000 ? '5h' : label;
    const reset = Number.isFinite(window.reset_at) ? window.reset_at * 1000
      : Number.isFinite(window.reset_after_seconds) ? now + window.reset_after_seconds * 1000 : undefined;
    windows.push({ label: actualLabel, usedPercent: Math.max(0, Math.min(100, window.used_percent)),
      ...(reset !== undefined ? { resetAt: new Date(reset).toISOString() } : {}) });
  }
  if (!windows.length) throw new Error('No usage windows returned');
  return { fetchedAt: now, usage: { provider: 'openai', windows } };
}

export async function collect(root) {
  const load = path => import(pathToFileURL(join(root, path)).href);
  const { AuthStorage } = await load('dist/core/auth-storage.js');
  const { createModels } = await load('node_modules/@earendil-works/pi-ai/dist/index.js');
  const { openaiCodexProvider } = await load('node_modules/@earendil-works/pi-ai/dist/providers/openai-codex.js');
  const credentials = AuthStorage.create(join(process.env.PI_CODING_AGENT_DIR || join(homedir(), '.pi', 'agent'), 'auth.json'));
  if ((await credentials.read('openai-codex'))?.type !== 'oauth') {
    throw new Error('Sign in to OpenAI Codex in Pi');
  }
  // Pi's native credential-store lock serializes token rotation with running Pi sessions.
  const models = createModels({ credentials });
  models.setProvider(openaiCodexProvider());
  const resolved = await models.getAuth('openai-codex', { signal: AbortSignal.timeout(90000) });
  const token = resolved?.auth.apiKey;
  if (!token) throw new Error('Sign in to OpenAI Codex in Pi');
  const credential = await credentials.read('openai-codex');
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/json' };
  if (typeof credential?.accountId === 'string') headers['ChatGPT-Account-Id'] = credential.accountId;
  const response = await fetch('https://chatgpt.com/backend-api/wham/usage', {
    headers, redirect: 'error', signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    throw new Error(response.status === 401 || response.status === 403
      ? 'OpenAI login expired or access denied; sign in again in Pi'
      : `Usage request failed (HTTP ${response.status})`);
  }
  return normalize(await response.json());
}

export async function main(root) {
  const file = join(process.env.XDG_CACHE_HOME || join(homedir(), '.cache'), 'noctalia', 'openai-usage.json');
  let previous = {};
  try { previous = JSON.parse(await readFile(file, 'utf8')); } catch { /* First run or corrupt cache. */ }
  let result;
  try {
    result = { lastGood: await collect(root) };
  } catch (error) {
    // SDK/network exceptions may include sensitive request details. Never serialize them.
    const message = /^(Sign in to OpenAI Codex in Pi|OpenAI login expired or access denied; sign in again in Pi|Usage request failed \(HTTP \d+\)|Invalid usage response|No usage windows returned)$/.test(error.message)
      ? error.message : 'Usage refresh failed; retrying automatically';
    result = { lastGood: previous.lastGood, error: message };
  }
  await mkdir(dirname(file), { recursive: true, mode: 0o700 });
  const temporary = `${file}.${process.pid}.tmp`;
  await writeFile(temporary, JSON.stringify(result), { mode: 0o600 });
  await rename(temporary, file);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main(process.argv[2]).catch(() => {
    console.error('Could not write subscription usage cache');
    process.exitCode = 1;
  });
}
