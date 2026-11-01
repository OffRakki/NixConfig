import assert from 'node:assert/strict';
import { scryptSync } from 'node:crypto';
import { test } from 'node:test';
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { passwordHashFor } from '../mail/provision.mjs';
import { validatePasswordHash } from '../mail/approval-server.mjs';

test('SOPS password derives a valid scrypt hash and unchanged input preserves it', async () => {
  const password = 'offline-fixture-password';
  const hash = await passwordHashFor(password, null);
  assert.equal(validatePasswordHash(hash), hash);
  const [, salt, expected] = hash.split(':');
  assert.equal(scryptSync(password, salt, 64).toString('hex'), expected);
  assert.equal(await passwordHashFor(password, hash), hash);
  assert.ok(!hash.includes(password));
});

test('password rotation changes the hash without trimming meaningful spaces', async () => {
  const old = await passwordHashFor('offline-fixture-password', null);
  const changed = await passwordHashFor(' offline-fixture-password ', old);
  assert.notEqual(changed, old);
  assert.equal(await passwordHashFor(' offline-fixture-password ', changed), changed);
  assert.notEqual(await passwordHashFor('offline-fixture-password', changed), changed);
});

test('root provisioning preserves the API key, rotates atomically and removes the bootstrap password', { skip: process.getuid() !== 0 }, async () => {
  const root = mkdtempSync(join(tmpdir(), 'mail-provision-fixture-'));
  const directory = join(root, 'credentials');
  const passwordFile = join(root, 'password');
  mkdirSync(directory, { mode: 0o750 }); chmodSync(directory, 0o750);
  const script = fileURLToPath(new URL('../mail/provision.mjs', import.meta.url));
  const run = () => spawnSync('/bin/sh', ['-c', 'umask 077; exec "$@"', 'sh', process.execPath, script, 'init', directory, passwordFile], { encoding: 'utf8', timeout: 10000 });
  try {
    writeFileSync(passwordFile, 'offline-provision-fixture\n', { mode: 0o400 });
    const first = run(); assert.equal(first.status, 0, first.stderr);
    const read = name => readFileSync(join(directory, name), 'utf8');
    const apiKey = read('api-key'); const initialHash = read('password-hash');
    for (const name of ['api-key', 'password-hash']) assert.equal(statSync(join(directory, name)).mode & 0o777, 0o440);
    assert.equal(run().status, 0); assert.equal(read('password-hash'), initialHash);
    writeFileSync(join(directory, 'bootstrap-password'), 'obsolete-offline-fixture', { mode: 0o600 });
    writeFileSync(passwordFile, 'rotated-offline-fixture\n');
    assert.equal(run().status, 0);
    const rotated = read('password-hash'); assert.notEqual(rotated, initialHash);
    assert.equal(read('api-key'), apiKey); assert.equal(existsSync(join(directory, 'bootstrap-password')), false);
    assert.equal(await passwordHashFor('rotated-offline-fixture', rotated.trim()), rotated.trim());
    writeFileSync(passwordFile, '\n');
    const invalid = run(); assert.equal(invalid.status, 1);
    assert.equal(read('password-hash'), rotated); assert.equal(read('api-key'), apiKey);
    assert.ok(!invalid.stderr.includes('rotated-offline-fixture'));
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('invalid SOPS passwords and malformed current hashes fail closed', async () => {
  for (const value of ['', 'x'.repeat(257), 'é'.repeat(129), 'line\nbreak', 'line\rbreak', 'nul\0byte', null]) {
    await assert.rejects(passwordHashFor(value, null));
  }
  await assert.rejects(passwordHashFor('offline-fixture-password', 'corrupt-hash'));
});
