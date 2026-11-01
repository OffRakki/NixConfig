import { randomBytes, scryptSync } from 'node:crypto';
import { chmodSync, chownSync, constants, closeSync, existsSync, lstatSync, openSync, readFileSync, renameSync, unlinkSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { equal, passwordHash, validatePasswordHash } from './approval-server.mjs';
import { text } from './core.mjs';

export async function passwordHashFor(password, currentHash) {
  text(password, 256, 1);
  if (/[\r\n]/.test(password)) throw new Error('single_line_password_required');
  if (currentHash !== null) {
    validatePasswordHash(currentHash);
    const [, salt, expected] = currentHash.split(':');
    if (equal(scryptSync(password, salt, 64).toString('hex'), expected)) return currentHash;
  }
  return passwordHash(password);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const [command, directory, passwordFile] = process.argv.slice(2);
    if (process.argv.length !== 5 || command !== 'init' || process.getuid() !== 0 || !directory?.startsWith('/') || !passwordFile?.startsWith('/')) throw new Error('root_init_required');
    const stat = lstatSync(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== 0 || (stat.mode & 0o777) !== 0o750) throw new Error('private_directory_required');
    const paths = Object.fromEntries(['api-key', 'password-hash', 'bootstrap-password'].map(name => [name, join(directory, name)]));
    const checkedRead = name => {
      const info = lstatSync(paths[name]);
      if (!info.isFile() || info.isSymbolicLink() || info.uid !== 0 || info.gid !== stat.gid || (info.mode & 0o777) !== 0o440) throw new Error('invalid_credential_file');
      const fd = openSync(paths[name], constants.O_RDONLY | constants.O_NOFOLLOW);
      try { return readFileSync(fd, 'utf8').trim(); } finally { closeSync(fd); }
    };
    const password = readFileSync(passwordFile, 'utf8').replace(/\r?\n$/, '');
    const currentHash = existsSync(paths['password-hash']) ? checkedRead('password-hash') : null;
    const desiredHash = await passwordHashFor(password, currentHash);
    if (!existsSync(paths['api-key'])) {
      writeFileSync(paths['api-key'], randomBytes(48).toString('base64url') + '\n', { mode: 0o440, flag: 'wx' });
      chmodSync(paths['api-key'], 0o440); chownSync(paths['api-key'], 0, stat.gid);
    }
    if (!/^[A-Za-z0-9_-]{64}$/.test(checkedRead('api-key'))) throw new Error('invalid_api_key');
    if (desiredHash !== currentHash) {
      const temporary = join(directory, `.password-hash-${randomBytes(16).toString('hex')}`);
      try {
        writeFileSync(temporary, desiredHash + '\n', { mode: 0o440, flag: 'wx' });
        chmodSync(temporary, 0o440); chownSync(temporary, 0, stat.gid);
        renameSync(temporary, paths['password-hash']);
      } finally { if (existsSync(temporary)) unlinkSync(temporary); }
    }
    if (existsSync(paths['bootstrap-password'])) unlinkSync(paths['bootstrap-password']);
  } catch { process.stderr.write('Mail approval credential operation failed\n'); process.exitCode = 1; }
}
