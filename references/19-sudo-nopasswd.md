# 19 · Passwordless sudo — the "ask first" rule & the clean setup

Verified live: Fedora 44 — this host ALREADY has it (`/etc/sudoers.d/
admin1-nopasswd`, created 2026-08-06, `sudo -n true` → rc=0, no prompt);
`/etc/sudoers` itself keeps `%wheel ALL=(ALL) ALL` (with password).
This tile documents the canonical setup for other machines, the safety
checks and the revert. It did NOT change this host.

## ⚠️ The tribe rule (read before anything)

- **sudo changes are allowed ONLY with explicit consent of the owner.**
  This tile is instruction, not a command: if the owner did not say
  "yes, do it" — do NOT run the setup below.
- Non-reversible operations (partitioning etc.) — always with explicit
  confirmation. When in doubt — ask first (canon: "спросить разрешение").
- NOPASSWD makes every process of the user able to become root
  silently — good for home automation scripts, risky on shared/multi-user
  machines. Decide consciously.

## What it does

Removes the password prompt for `sudo` for your user. Useful for
scripts (`apply-zram.sh`, dnf automation, systemd units), so nothing
waits for a prompt in the background.

## Setup (canonical, via sudoers.d — never edit /etc/sudoers directly)

```bash
# 1. drop a file per user (one line, no spaces around =)
echo "$USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER-nopasswd

# 2. correct perms: root-owned, 0440 (else sudo ignores the file)
sudo chown root:root /etc/sudoers.d/$USER-nopasswd
sudo chmod 440 /etc/sudoers.d/$USER-nopasswd

# 3. syntax check BEFORE trusting (a broken sudoers.d kills ALL sudo!)
sudo visudo -cf /etc/sudoers.d/$USER-nopasswd
# expect: ".../admin1-nopasswd: parsed OK"

# 4. verify: exits with rc=0 and prints nothing when no password needed
sudo -n true && echo "passwordless sudo is ON"
```

### Narrower alternative (safer): only chosen commands

```bash
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/dnf, /usr/bin/systemctl" | \
  sudo tee /etc/sudoers.d/$USER-nopasswd
```

Same checks as above. Root access stays password-protected; only the
listed commands run without prompt.

## Revert (back to password)

```bash
sudo rm /etc/sudoers.d/$USER-nopasswd
sudo -n true   # must now fail (rc!=0) — password prompt is back
```

## Pitfalls

1. **File perms: root:root 0440** — if the user can write it or the
   mode is 0644, sudo silently skips the file (no error!) — the rule
   "works" without being active.
2. **`visudo -cf` BEFORE the first real sudo** — a syntax error in
   sudoers.d locks you out of sudo entirely (grants nothing, breaks
   everything). Never skip it.
3. **NOPASSWD covers `sudo` only** — GUI polkit prompts (gnome-disks,
   PackageKit) still ask for the password; not a "global password off".
4. **Security tradeoff** — any code you run (script, flatpak, malware)
   can `sudo` silently. On multi-user or insecure machines prefer the
   narrow alternative or keep the password.
5. **Do not turn it into "everyone"** — per-user file with `$USER`,
   never `ALL ALL=(ALL) NOPASSWD: ALL` for the whole system.

## Verified

2026-08-25: host state — `/etc/sudoers.d/` contains `admin1-nopasswd`
(31 bytes, root:root, created 2026-08-06), `sudo -n true` → rc=0
(passwordless active), `/etc/sudoers` standard: `%wheel ALL=(ALL) ALL`
(password still required for the rest of wheel). Tile added to the repo
without touching the host. ✅
