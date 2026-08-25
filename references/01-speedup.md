# 01 · Speed up Fedora/GNOME (audit → services → boot → GNOME → kernel)

Verified live: boot from ~45s to ~13s, minus ~300–500MB RAM, noticeably snappier
response — without losing functionality. All steps are reversible (each has a
rollback command).

## Why it matters

- Boot time is mostly *waiting*: dead UUIDs in fstab, `NetworkManager-wait-online`,
  plymouth splash — not the hardware. Fixing waits is free performance.
- Idle RAM is spent on crash reporters, modems, iSCSI/LVM monitors nobody uses.
  Masking them frees hundreds of MB after reboot.
- GNOME animations and blur extensions burn GPU/CPU on every interaction.
- A custom kernel is the LAST step — it is not "+50%", it is single-digit
  percentages in narrow workloads.

## When to use / when NOT

- **Use:** "make it faster", slow boot, heavy UI, "which services can I disable",
  "is a custom kernel worth it".
- **NOT:** zram/swap tuning → `references/05-zram.md`; disk layout/formatting →
  `references/06-disks.md`; servers (there — do NOT touch
  NetworkManager-wait-online and friends).

## Main rule

**Audit first (read-only), then changes, then reboot — owned by the user.**
Change nothing until facts are collected. Show every change to the owner with
its cost and rollback command.

## Workflow

### Step 0 — Audit (read-only, change nothing)

```bash
bash scripts/audit.sh          # one run — the whole picture
```

Or manually:

```bash
cat /etc/os-release                                   # distro/version
systemd-analyze; systemd-analyze blame | head -15     # where boot time goes
systemd-analyze critical-chain | head -12             # who blocks whom
systemctl list-unit-files --state=enabled | grep -vE "dbus|getty|systemd-|user@"  # candidates
systemctl --failed                                     # failed services
cat /etc/fstab; lsblk -f                               # dead UUIDs vs real disks
free -h; swapon --show                                 # memory/swap
systemd-detect-virt                                    # VM or bare metal
journalctl -b -p err | tail -20                        # boot errors
```

### Step 1 — Boot: remove the waits

| Culprit | How to find | How to fix | Rollback |
|---|---|---|---|
| Dead UUID in fstab (disk reformatted/unplugged) | `lsblk -f` vs `cat /etc/fstab`; journal "timed out waiting for device" | backup `cp -a /etc/fstab /etc/fstab.bak-$(date +%Y%m%d)`, remove/fix the line; `x-systemd.device-timeout=N` and `nofail` contain it, don't cure it | restore the backup |
| `NetworkManager-wait-online.service` (servers/network FS only) | `systemd-analyze blame` (usually 2–10s) | `sudo systemctl mask NetworkManager-wait-online.service` | `unmask` |
| plymouth splash (`rhgb` in cmdline) | `blame` → `plymouth-quit-wait.service` | remove `rhgb quiet` from GRUB cmdline (grubby `--update-kernel`/`--args`) | restore args |

### Step 2 — Services: mask the parasites (reversible)

Rule: `sudo systemctl mask --now <unit>` (mask = symlink to /dev/null —
more reliable than disable; rollback `unmask`). RAM is freed **after reboot**.

**Safe to mask on a desktop (verified):**

| Services | What you lose | When NOT to touch |
|---|---|---|
| `abrtd`, `abrt-journal-core`, `abrt-oops`, `abrt-vmcore`, `abrt-xorg` | auto crash detection and notifications | user files bug reports |
| `ModemManager` | USB 3G/4G modems | a modem is used |
| `iscsi-onboot`, `iscsi-starter` | iSCSI storage | iSCSI in use |
| `mdmonitor` | software RAID monitoring | mdadm RAID exists (`lsblk`) |
| `lvm2-monitor` | LVM events | LVM in use (`lsblk`) |
| `qemu-guest-agent` | agent for VMs | system IS a VM (`systemd-detect-virt`) |
| `intel_lpmd` | laptop SoC power efficiency | laptop |
| `thermald` | Intel thermal daemon | laptop with stock cooling; often already failed on desktops |

**Ask first:** `cups` (printer), `bluetooth`, `avahi-daemon` (mDNS/device discovery).

**NEVER mask:** `akmods` (driver builds), `nvidia-powerd`, `chronyd`, `crond`,
`irqbalance`, `mcelog`, `firewalld`, `auditd`, `fips-crypto-policy-overlay`,
`gdm`, anything `systemd-*` and `user@`.

### Step 3 — GNOME: interface responsiveness

```bash
gsettings set org.gnome.desktop.interface enable-animations false   # rollback: true
gsettings get org.gnome.shell enabled-extensions                    # each ext = shell load
```

- Dynamic-blur extensions (blur-my-shell and co) are the biggest GPU/CPU
  eaters: switch to static blur or Hack Level 0 (in the extension settings).
- `tracker` (file index): disable in Settings → Search if file search is unused.

### Step 4 (optional) — CachyOS x86_64_v3 custom kernel

> **Can you install it?** YES, if all checks in "Checks BEFORE installing"
> pass: CPU supports x86-64_v3, Secure Boot is off, NVIDIA (if any) via
> akmods. If ANY check fails — do NOT install; steps 1–3 give most of the gain.

> **Status at home: installed & booting** (checked 2026-08-25, `uname -r` →
> `7.1.8-cachyos1.fc44`). Why we run it: **~+10% in games** (SIMD-bound
> workloads benefit from x86_64_v3 builds + BORE scheduler); it is NOT a
> "+50%" rocket — everyday desktop ~0.

Honest assessment: **not "+50%"** — single digits to ~10–20% in narrow
workloads (SIMD: compression, media, scientific — up to 10–20%; everyday ~0;
BORE scheduler — subjectively snappier). For a "rocket" — do steps 1–3 first;
the kernel is the last touch.

Checks BEFORE installing:

```bash
/lib64/ld-linux-x86-64.so.2 --help | grep "x86-64-v3"   # CPU support (no — DON'T install)
mokutil --sb-state                                        # Secure Boot (no mokutil = usually off)
rpm -qa | grep akmod-nvidia                               # NVIDIA via akmods? (custom kernel needs akmods)
```

Install (official CachyOS team port):

```bash
sudo dnf copr enable bieszczaders/kernel-cachyos -y
sudo dnf install -y kernel-cachyos kernel-cachyos-devel-matched
sudo setsebool -P domain_kernel_load_modules on          # SELinux: module loading
```

NVIDIA (akmods builds the kmod at kernel install; check/rebuild — with the
FULL kernel version, the short one is not found):

```bash
ls /boot | grep cachyos                                    # exact version: 7.x.y-cachyosZ.fcN.x86_64
sudo akmods --force --kernels <full-version>
rpm -qa | grep kmod-nvidia                                 # kmod for the new kernel = present
```

Default in GRUB + rollback:

```bash
sudo grubby --set-default /boot/vmlinuz-<cachyos-version>  # old kernels stay in the menu
sudo grubby --default-kernel                                # verify
# rollback: pick the old kernel in the GRUB menu at boot, then:
sudo grubby --set-default /boot/vmlinuz-<old> && sudo dnf remove kernel-cachyos*
```

### Step 5 — Verify after reboot (owner reboots themselves)

```bash
systemd-analyze            # compare with the Step-0 measurement
uname -r                   # kernel (if installed)
nvidia-smi                 # GPU alive (if NVIDIA)
systemctl --failed         # empty (masks do not fail)
```

## Owner's power & energy rules (verified 2026-08-25)

The owner wants maximum responsiveness, not battery savings — everything
below is ALREADY set on this desktop; check and keep, do not "fix" back:

| What | Value | Check command |
|---|---|---|
| Night Light | OFF (do NOT force-enable) | `gsettings get org.gnome.settings-daemon.plugins.color night-light-enabled` → `false` |
| Power profile | `performance` (max) | `gdbus call --system --dest org.freedesktop.UPower.PowerProfiles --object-path /org/freedesktop/UPower/PowerProfiles --method org.freedesktop.DBus.Properties.Get org.freedesktop.UPower.PowerProfiles ActiveProfile` → `('performance',)` |
| Auto screen blank | OFF (screen never blanks on idle) | `gsettings get org.gnome.desktop.session idle-delay` → `uint32 0` |
| Auto suspend (idle) | OFF | `gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type` → `'nothing'` |
| Screen dim on idle | OFF (no dimming!) | `gsettings get org.gnome.settings-daemon.plugins.power idle-dim` → `false` |

- PowerProfiles comes from modern `upower` itself (no
  `power-profiles-daemon` package needed; it is absent here and the
  profile still answers `performance` on the system bus).
- To change the profile in GUI: Settings → Power → Power Mode →
  Performance. To force it: `gdbus call --system ... HoldProfile s
  performance manual` (then release with `ReleaseProfile`).
- On a desktop (no battery, no `/sys/firmware/acpi/platform_profile`)
  the profiles are cosmetic for the OS, but the control center still
  shows them — keep Performance as the owner's choice.

## Success criteria

- Faster boot: `systemd-analyze` before/after (typically 45s → 13s including
  timeouts; LUKS password entry is not counted — see Gotchas).
- `systemctl --failed` empty; masked services show `masked`.
- RAM: `free -h` — hundreds of MB freer after reboot.
- Every change documented to the owner with its rollback.

## Failure modes

| What goes wrong | Cause | What to do |
|---|---|---|
| Something needed disappeared after a mask (print, BT, modem) | masked "ask-first" without asking | `unmask` — instant |
| Doesn't boot after an fstab edit | typo in UUID/options | GRUB → rescue/old kernel, `mount -o remount,rw /`, restore `/etc/fstab.bak-*` |
| New kernel installed, no graphics/drivers | kmod not built for the new kernel | boot the old kernel from GRUB, `sudo akmods --force --kernels <full-version>` |
| Custom kernel doesn't boot at all | Secure Boot on / no v3 support | pick old kernel in GRUB; SB — disable or sign the kernel (mokutil) |

## Gotchas (from real cases)

- **"initrd loads 30–60s" is often the LUKS password prompt, not a bug.**
  `journalctl -b | grep systemd-cryptsetup` — seconds between "Starting" and
  "Finished" with cipher set near the end = waited for the password.
- **`systemd-analyze blame` shows DEVICE activation times** (dev-sda1 "34s" =
  the disk appeared at second 34, not that it waited 34s). Read it with
  `critical-chain` and journal, not by a single number.
- **UUID in fstab ≠ UUID on disk** after reformatting (NTFS→ext4 etc.):
  cross-check `blkid`/`lsblk -f`, don't copy old config entries. Symptom:
  "timed out waiting for device" in journal.
- **thermald on desktops is often failed on its own** (conflicts with laptop
  daemons/custom kernels) — don't fix, mask; on laptops — leave it.
- **Secure Boot check without mokutil:** if a proprietary NVIDIA module works
  unsigned — SB is off, a custom kernel will install without fuss.
- **akmods needs the FULL kernel version** (`7.x.y-cachyosZ.fcN.x86_64`); the
  short one gives "Could not find files needed to compile modules".
- **Masks free no RAM until reboot** — don't expect an immediate effect.
- **`mask --now` on a failed service** keeps it in `--failed` until reboot —
  residual state, not an error.
- **Kernel effect is bimodal** (Phoronix: "handful of workloads jump, most
  barely move"); don't promise "+30–50%" from a kernel.
- **The CachyOS-for-Fedora repo dropped prebuilt NVIDIA drivers** — akmods/
  RPMFusion required; COPR kernels = "bugs not in Fedora Bugzilla".

## References

- General Fedora optimization guide: github.com/winterofhell/fedora-optimizations
- Official kernel port: copr.fedorainfracloud.org/coprs/bieszczaders/kernel-cachyos
- Fedora community experience: discussion.fedoraproject.org (clean-up services,
  slow boot after LUKS unlock / dracut-initqueue)
- v3 benchmarks: phoronix.com/review/cachyos-x86-64-v3-v4, "Mixed Bag" analysis:
  sunnyflunk.github.io (x86-64-v3 Mixed Bag of Performance)
- systemd-analyze methodology: linuxblog.io/systemd-analyze-debug-optimize-linux-boot
- blur-my-shell performance: deepwiki.com/aunetx/blur-my-shell (Performance Considerations)
