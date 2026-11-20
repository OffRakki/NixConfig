import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { main, normalize } from './collect.mjs';

test('normalizes both windows, reset times and zero usage without private fields', () => {
  const result = normalize({ email: 'private', rate_limit: {
    primary_window: { used_percent: 0, reset_at: 18000, limit_window_seconds: 18000 },
    secondary_window: { used_percent: 72, reset_after_seconds: 604800, limit_window_seconds: 604800 },
  } }, 0);
  assert.deepEqual(result, { fetchedAt: 0, usage: { provider: 'openai', windows: [
    { label: '5h', usedPercent: 0, resetAt: '1970-01-01T05:00:00.000Z' },
    { label: 'weekly', usedPercent: 72, resetAt: '1970-01-08T00:00:00.000Z' },
  ] } });
});

test('rejects missing/malformed windows instead of inventing zero usage', () => {
  for (const body of [null, {}, { rate_limit: { primary_window: { used_percent: null } } },
    { rate_limit: { primary_window: { used_percent: NaN } } }]) {
    assert.throws(() => normalize(body));
  }
  assert.equal(normalize({ rate_limit: { secondary_window: { used_percent: 200 } } }).usage.windows[0].usedPercent, 100);
});

test('failed refresh preserves last good usage and writes only sanitized errors privately', async () => {
  const cache = await mkdtemp(join(tmpdir(), 'usage-test-'));
  const old = process.env.XDG_CACHE_HOME;
  process.env.XDG_CACHE_HOME = cache;
  try {
    await main('/nonexistent/secret-in-error');
    const file = join(cache, 'noctalia', 'openai-usage.json');
    assert.deepEqual(JSON.parse(await readFile(file)), { error: 'Usage refresh failed; retrying automatically' });
    const lastGood = normalize({ rate_limit: { primary_window: { used_percent: 34 } } });
    await writeFile(file, JSON.stringify({ lastGood }));
    await main('/nonexistent/secret-in-error');
    assert.deepEqual(JSON.parse(await readFile(file)), { lastGood, error: 'Usage refresh failed; retrying automatically' });
    assert.equal((await stat(file)).mode & 0o777, 0o600);
  } finally {
    if (old === undefined) delete process.env.XDG_CACHE_HOME;
    else process.env.XDG_CACHE_HOME = old;
    await rm(cache, { recursive: true });
  }
});
