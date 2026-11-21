import { execFile as execFileCb } from 'node:child_process';
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { promisify } from 'node:util';

const execFile = promisify(execFileCb);

const ALLOWED_ERRORS = /^(Sign in to Google Antigravity CLI|Antigravity usage command failed|Invalid usage response|No usage windows returned)$/;

function groupMeta(group) {
  const name = typeof group?.name === 'string' ? group.name.trim() : '';
  const bucketIds = Array.isArray(group?.buckets)
    ? group.buckets.map(b => String(b?.id || '').toLowerCase())
    : [];

  if (/\bargon\b/i.test(name) || bucketIds.some(id => id.includes('argon'))) {
    return { id: 'argon', name: 'Gemini 4 Argon', shortName: 'Arg' };
  }
  if (/\b(claude|gpt)\b/i.test(name) || bucketIds.some(id => id.startsWith('3p-'))) {
    return { id: 'claude-gpt', name: 'Claude & GPT', shortName: 'C/G' };
  }
  if (/\bgemini\b/i.test(name) || bucketIds.some(id => id.startsWith('gemini-'))) {
    return { id: 'gemini', name: 'Gemini Models', shortName: 'Gem' };
  }

  const fallbackName = name || 'Other';
  const id = fallbackName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'other';
  const shortName = fallbackName.split(/\s+/)[0].slice(0, 3) || '?';
  return { id, name: fallbackName, shortName };
}

function windowOrder(label) {
  if (label === '5h') return 0;
  if (label === 'weekly') return 1;
  return 2;
}

function zeroRemainingInResponse(response, groupName, bucketName) {
  if (typeof response !== 'string' || !groupName || !bucketName) return false;
  const prefix = `${groupName}\t${bucketName}\t`;
  return response.split(/\r?\n/).some(line => line.startsWith(prefix) && line.slice(prefix.length).startsWith('0%'));
}

// Only normalized usage and fixed error messages leave this process, never auth.
export function normalize(body, now = Date.now()) {
  if (body?.status !== 'SUCCESS' || !Array.isArray(body?.command?.data?.groups)) {
    throw new Error('Invalid usage response');
  }

  const groups = [];
  for (const rawGroup of body.command.data.groups) {
    if (!rawGroup || !Array.isArray(rawGroup.buckets) || !rawGroup.buckets.length) {
      throw new Error('Invalid usage response');
    }
    const meta = groupMeta(rawGroup);
    const windows = [];
    for (const bucket of rawGroup.buckets) {
      if (!bucket || typeof bucket !== 'object') {
        throw new Error('Invalid usage response');
      }
      const rawWindow = typeof bucket.window === 'string' ? bucket.window.trim().toLowerCase() : '';
      if (!rawWindow) throw new Error('Invalid usage response');
      const label = rawWindow === 'weekly' ? 'weekly' : rawWindow === '5h' ? '5h' : rawWindow;

      let remaining;
      if (typeof bucket.remaining_fraction === 'number' && Number.isFinite(bucket.remaining_fraction)) {
        remaining = bucket.remaining_fraction;
      } else if (
        bucket.remaining_fraction === undefined
        && typeof bucket.reset_time === 'string'
        && zeroRemainingInResponse(body.response, rawGroup.name, bucket.name)
      ) {
        remaining = 0;
      } else {
        throw new Error('Invalid usage response');
      }

      const usedPercent = Math.max(0, Math.min(100, Math.round((1 - remaining) * 1000) / 10));
      const resetMs = typeof bucket.reset_time === 'string' ? Date.parse(bucket.reset_time) : Number.NaN;
      windows.push({
        label,
        usedPercent,
        ...(Number.isFinite(resetMs) ? { resetAt: new Date(resetMs).toISOString() } : {}),
      });
    }

    windows.sort((a, b) => windowOrder(a.label) - windowOrder(b.label));
    if (windows.length) {
      groups.push({ ...meta, windows });
    }
  }

  if (!groups.length) throw new Error('No usage windows returned');
  return { fetchedAt: now, usage: { provider: 'antigravity', groups } };
}

export async function collect(agyBin = 'agy') {
  let stdout;
  try {
    ({ stdout } = await execFile(agyBin, ['-p', '/usage', '--output-format', 'json'], {
      timeout: 60000,
      maxBuffer: 1024 * 1024,
    }));
  } catch (error) {
    if (error?.code === 3) {
      throw new Error('Sign in to Google Antigravity CLI');
    }
    const detail = `${error?.stderr || ''}\n${error?.stdout || ''}`;
    if (/(unauthenticated|sign in|login required|not signed in)/i.test(detail)) {
      throw new Error('Sign in to Google Antigravity CLI');
    }
    throw new Error('Antigravity usage command failed');
  }

  let body;
  try {
    body = JSON.parse(stdout);
  } catch {
    throw new Error('Invalid usage response');
  }
  return normalize(body);
}

export async function main(agyBin = 'agy') {
  const file = join(process.env.XDG_CACHE_HOME || join(homedir(), '.cache'), 'noctalia', 'antigravity-usage.json');
  let previous = {};
  try { previous = JSON.parse(await readFile(file, 'utf8')); } catch { /* First run or corrupt cache. */ }
  let result;
  try {
    result = { lastGood: await collect(agyBin) };
  } catch (error) {
    // CLI/process exceptions may include sensitive output. Never serialize them.
    const message = ALLOWED_ERRORS.test(error?.message || '')
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
    console.error('Could not write Antigravity usage cache');
    process.exitCode = 1;
  });
}
