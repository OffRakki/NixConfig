import { randomBytes } from 'node:crypto';
import { chmodSync, chownSync, constants, closeSync, existsSync, lstatSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { passwordHash, validatePasswordHash } from './approval-server.mjs';

try {
  const [command, directory] = process.argv.slice(2);
  if (process.argv.length !== 4 || process.getuid() !== 0 || !directory?.startsWith('/')) throw new Error('root_required');
  const stat = lstatSync(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== 0 || (stat.mode & 0o777) !== 0o750) throw new Error('private_directory_required');
  const paths = Object.fromEntries(['api-key', 'password-hash', 'bootstrap-password'].map(name => [name, join(directory, name)]));
  const checkedRead = (name, mode) => {
    const info = lstatSync(paths[name]);
    if (!info.isFile() || info.isSymbolicLink() || info.uid !== 0 || (mode === 0o440 && info.gid !== stat.gid) || (info.mode & 0o777) !== mode) throw new Error('invalid_credential_file');
    const fd = openSync(paths[name], constants.O_RDONLY | constants.O_NOFOLLOW);
    try { return readFileSync(fd, 'utf8').trim(); } finally { closeSync(fd); }
  };
  if (command === 'init') {
    const write = (name, value, mode) => { writeFileSync(paths[name], value + '\n', { mode, flag: 'wx' }); chmodSync(paths[name], mode); if (mode === 0o440) chownSync(paths[name], 0, stat.gid); };
    if (!existsSync(paths['bootstrap-password'])) {
      if (existsSync(paths['password-hash'])) throw new Error('incomplete_credentials');
      write('bootstrap-password', randomBytes(32).toString('base64url'), 0o600);
    }
    const password = checkedRead('bootstrap-password', 0o600);
    if (!existsSync(paths['password-hash'])) write('password-hash', await passwordHash(password), 0o440);
    validatePasswordHash(checkedRead('password-hash', 0o440));
    if (!existsSync(paths['api-key'])) write('api-key', randomBytes(48).toString('base64url'), 0o440);
    if (!/^[A-Za-z0-9_-]{64}$/.test(checkedRead('api-key', 0o440))) throw new Error('invalid_api_key');
  } else if (command === 'show-login') {
    if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error('tty_required');
    const tty = openSync('/dev/tty', constants.O_WRONLY | constants.O_NOCTTY);
    try { writeFileSync(tty, `Username: lucky\nURL: http://127.0.0.1:8765\nPassword: ${checkedRead('bootstrap-password', 0o600)}\n`); }
    finally { closeSync(tty); }
  } else throw new Error('invalid_command');
} catch { process.stderr.write('Mail approval credential operation failed\n'); process.exitCode = 1; }
