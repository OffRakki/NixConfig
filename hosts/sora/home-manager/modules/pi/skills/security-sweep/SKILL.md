---
name: security-sweep
description: Post-secret-work verification checklist. Run after any task touching SOPS secrets, API keys, tokens, private URLs, or credentials.
---

# Security sweep

After ANY task that touches, reads, edits, searches, adds, removes, decrypts, or otherwise interacts with:

- SOPS secrets (`private.yaml` or any `.sops.*` file)
- API tokens or keys (OpenAI, DeepSeek, Firebase, Mercado Pago, etc.)
- Private URLs (internal services, localhost services with auth)
- Private files (Firefly credentials, CalDAV secrets, mail passwords)
- Any encrypted or restricted config paths

Run the five-point checklist below immediately and exhaustively.

## Checklist

### 1. Working tree

`jj status` (or `git status`). Check for files staged or modified that contain secrets in plaintext. Did you accidentally leave a decrypted value, a raw API key, a private URL, or sensitive data in a `.nix`, `.json`, `.md`, or config file?

### 2. Commit history

`jj log` with a diff check on recent commits. Did any commit capture secrets in plaintext? If so, `jj abandon` or rebase it out. **Never let a secret touch the commit log.**

### 3. Stray decrypted files

Check temp dirs, `/dev/shm`, or any paths where `sops-decrypt` or similar tools may have left artifacts. Did any tool/script dump decrypted content somewhere it shouldn't be?

### 4. Full NixConfig grep

Run a scan of changed areas:

```
rg -n '(sk-[a-zA-Z0-9]{20,}|AIza[0-9A-Za-z_-]{35}|ghp_[0-9a-zA-Z]{36}|-----BEGIN (RSA |EC |OPENSSH )PRIVATE KEY-----|secret|api[_-]?key|password|token)' --glob '!*.sops.*' ~/Projects/NixConfig/
```

This catches the most common leak patterns. Add more patterns as needed.

### 5. Re-verify INDEX.md

If you added a new secret, sops file, or private reference, make sure INDEX.md was updated (or doesn't need updating).

## Remediation

**If any secret was found unencrypted or in the commit log:**

1. Fix the source file (encrypt via sops, remove the plaintext value)
2. Rotate the secret if it hit the remote (assume compromised)
3. Mark it as a `failure` memory so Ciel knows not to repeat the mistake
4. `notify-send` Lucky ("Ciel — security sweep") with a summary

**This is a hard rule. No exceptions. Skip it and you risk leaking Lucky's entire infrastructure.**
