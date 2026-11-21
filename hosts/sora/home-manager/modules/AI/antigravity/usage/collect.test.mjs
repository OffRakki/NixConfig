import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { main, normalize } from './collect.mjs';

test('normalizes all three Antigravity groups, converts remaining to used, orders 5h before weekly, and drops extra fields', () => {
  const result = normalize({
    conversation_id: 'private-id',
    status: 'SUCCESS',
    command: {
      name: 'usage',
      data: {
        description: 'private tier details',
        groups: [
          {
            name: 'Gemini Models',
            description: 'Models within this group',
            buckets: [
              { id: 'gemini-weekly', name: 'Weekly Limit Remaining', window: 'weekly', remaining_fraction: 0.98998, reset_time: '2026-11-27T23:56:31Z' },
              { id: 'gemini-5h', name: 'Five Hour Limit Remaining', window: '5h', remaining_fraction: 0.96993, reset_time: '2026-11-21T04:56:31Z' },
            ],
          },
          {
            name: 'Claude and GPT models',
            buckets: [
              { id: '3p-weekly', name: 'Weekly Limit Remaining', window: 'weekly', remaining_fraction: 1, reset_time: '2026-11-28T00:00:56Z' },
              { id: '3p-5h', name: 'Five Hour Limit Remaining', window: '5h', remaining_fraction: 0.75, reset_time: '2026-11-21T05:00:56Z' },
            ],
          },
          {
            name: 'Gemini 4 Argon',
            buckets: [
              { id: 'gemini-argon-wtu-weekly', name: 'Gemini 4 Argon Weekly Limit', window: 'weekly', remaining_fraction: 0.5, reset_time: '2026-11-28T00:00:56Z' },
            ],
          },
        ],
      },
    },
  }, 1234);

  assert.deepEqual(result, {
    fetchedAt: 1234,
    usage: {
      provider: 'antigravity',
      groups: [
        {
          id: 'gemini',
          name: 'Gemini Models',
          shortName: 'Gem',
          windows: [
            { label: '5h', usedPercent: 3, resetAt: '2026-11-21T04:56:31.000Z' },
            { label: 'weekly', usedPercent: 1, resetAt: '2026-11-27T23:56:31.000Z' },
          ],
        },
        {
          id: 'claude-gpt',
          name: 'Claude & GPT',
          shortName: 'C/G',
          windows: [
            { label: '5h', usedPercent: 25, resetAt: '2026-11-21T05:00:56.000Z' },
            { label: 'weekly', usedPercent: 0, resetAt: '2026-11-28T00:00:56.000Z' },
          ],
        },
        {
          id: 'argon',
          name: 'Gemini 4 Argon',
          shortName: 'Arg',
          windows: [
            { label: 'weekly', usedPercent: 50, resetAt: '2026-11-28T00:00:56.000Z' },
          ],
        },
      ],
    },
  });
});

test('handles omitted zero remaining_fraction when text response reports 0% remaining', () => {
  const result = normalize({
    status: 'SUCCESS',
    response: 'Gemini Models\tFive Hour Limit Remaining\t0%\t2026-11-21T04:56:31Z\n',
    command: {
      name: 'usage',
      data: {
        groups: [{
          name: 'Gemini Models',
          buckets: [{ id: 'gemini-5h', name: 'Five Hour Limit Remaining', window: '5h', reset_time: '2026-11-21T04:56:31Z' }],
        }],
      },
    },
  }, 0);
  assert.equal(result.usage.groups[0].windows[0].usedPercent, 100);
});

test('rejects missing or malformed groups/buckets and clamps out-of-range fractions', () => {
  for (const body of [
    null,
    {},
    { status: 'ERROR', command: { data: { groups: [] } } },
    { status: 'SUCCESS', command: { data: { groups: [] } } },
    { status: 'SUCCESS', command: { data: { groups: [{ name: 'Gemini Models', buckets: [] }] } } },
    { status: 'SUCCESS', command: { data: { groups: [{ name: 'Gemini Models', buckets: [{ window: '5h', remaining_fraction: null }] }] } } },
    { status: 'SUCCESS', command: { data: { groups: [{ name: 'Gemini Models', buckets: [{ window: '5h', remaining_fraction: NaN }] }] } } },
  ]) {
    assert.throws(() => normalize(body));
  }
  const clamped = normalize({
    status: 'SUCCESS',
    command: {
      data: {
        groups: [{
          name: 'Gemini Models',
          buckets: [
            { window: '5h', remaining_fraction: -0.5 },
            { window: 'weekly', remaining_fraction: 1.5 },
          ],
        }],
      },
    },
  }, 0);
  assert.equal(clamped.usage.groups[0].windows[0].usedPercent, 100);
  assert.equal(clamped.usage.groups[0].windows[1].usedPercent, 0);
});

test('failed refresh preserves last good usage and writes only sanitized errors privately', async () => {
  const cache = await mkdtemp(join(tmpdir(), 'agy-usage-test-'));
  const old = process.env.XDG_CACHE_HOME;
  process.env.XDG_CACHE_HOME = cache;
  try {
    await main('/nonexistent/secret-in-error');
    const file = join(cache, 'noctalia', 'antigravity-usage.json');
    assert.deepEqual(JSON.parse(await readFile(file, 'utf8')), { error: 'Antigravity usage command failed' });
    const lastGood = normalize({
      status: 'SUCCESS',
      command: { data: { groups: [{ name: 'Gemini Models', buckets: [{ window: '5h', remaining_fraction: 0.66 }] }] } },
    }, 500);
    await writeFile(file, JSON.stringify({ lastGood }));
    await main('/nonexistent/secret-in-error');
    assert.deepEqual(JSON.parse(await readFile(file, 'utf8')), { lastGood, error: 'Antigravity usage command failed' });
    assert.equal((await stat(file)).mode & 0o777, 0o600);
  } finally {
    if (old === undefined) delete process.env.XDG_CACHE_HOME;
    else process.env.XDG_CACHE_HOME = old;
    await rm(cache, { recursive: true });
  }
});
