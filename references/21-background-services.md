# 21 · Background services — find what eats the machine, tame the file indexer

<!-- meta
категория: B-производительность / G-аудит
риск: L1 (аудит — только чтение; фикс — пользовательская настройка gsettings, без sudo, полностью обратимо)
preflight-гейт: DE=GNOME (localsearch/Tracker существует только в GNOME); сам аудит — DE-агностик
откат: в файле: вернуть прежнее значение `ignored-directories`
-->

Verified live: Fedora 44, GNOME 50, 15 GiB RAM, GTX 1660 SUPER (6 GiB).
Audit of the "quiet" background turned up two remote-desktop agents listening
(AnyDesk + RustDesk), duplicate MCP servers, and GNOME's file indexer grinding
the Go module cache (`~/go/pkg/mod`) at ~1.6 GiB of disk I/O. Fix narrowed the
indexer to documents/media — it went idle and stopped rescanning caches.

## Why it matters

- The windows you actually see (game, browser, messenger) are only part of the
  load. The hidden part is **services**: remote-access agents listening on
  ports, indexers grinding the disk, duplicated helper processes, daemons stuck
  on a half-open TCP connection.
- Idle RAM doesn't disappear — it gets pushed to **swap**, and `kswapd0` starts
  thrashing CPU on every allocation. On a 15 GiB box with a game + browser +
  messenger, swap fills fast. Wanting "where did it all go" usually means
  "what got swapped out", not "what burns CPU".
- Two remote-desktop tools installed at once (AnyDesk **and** RustDesk) is both
  wasted RAM and a real attack surface: each one listens/keeps an outbound
  rendezvous channel. For a machine that cares about not being exposed, this
  is the first thing to look at.
- The file indexer is the classic false alarm: it looks like malware (heavy
  disk churn, big memory peak) but is a stock GNOME component. The real fix is
  narrowing its scope, not killing it.

## Part 0 — 5-minute audit (read-only)

Run each; nothing is modified.

```bash
# load / memory / swap pressure
uptime; free -h

# top by CPU and by RAM (commit charge), swap per process
ps -eo pid,user,%cpu,%mem,etime,args --sort=-%cpu | head -20
ps -eo pid,user,%cpu,%mem,rss,etime,args --sort=-rss | head -20
for p in $(ps -eo pid=); do s=$(awk '/VmSwap/{print $2}' /proc/$p/status 2>/dev/null)
  [ -n "$s" ] && [ "$s" -gt 0 ] && echo "$s $p $(tr '\0' ' ' </proc/$p/cmdline | cut -c1-50)"; done | sort -nr | head

# who talks to the network, and what listens on real interfaces
ss -tulpn | grep -vE '127.0.0.1|::1|/run|@'     # non-local listeners
ss -tnp  | grep ESTAB                            # live outbound

# disk churn per process (cumulative bytes since start)
for p in /proc/[0-9]*; do pid=${p#/proc/}; [ -r "$p/io" ] || continue
  w=$(awk '/^write_bytes/{print $2;exit}' "$p/io"); r=$(awk '/^read_bytes/{print $2;exit}' "$p/io")
  echo "$(( (${r:-0}+w)/1048576 )) $pid $(tr '\0' ' ' <$p/cmdline | cut -c1-55)"; done | sort -nr | head

# user services that survive reboots (what restarts by itself)
systemctl --user list-unit-files --state=enabled --no-pager
systemctl --user list-units --type=service --state=running --no-pager
```

Read it like this: **CPU** tells you the active job (usually the game/browser);
**swap-per-process** tells you the memory victims; **listeners** tell you the
attack surface; **disk churn** tells you who grinds storage. A process that is
high in none of them but runs 24/7 is a "quiet" one — fine, just know it exists.

## Part 1 — localsearch-3 (ex-Tracker): the GNOME file indexer

**What it is.** `localsearch-3` (package `localsearch-3`, formerly **Tracker**)
is GNOME's built-in file indexer. It scans your home, extracts metadata (name,
type, size, text content) into `~/.cache/tracker3`, and answers: GNOME Shell
search (Super → type a filename), Nautilus (Files) search, and the Photos /
Videos / Documents / Music apps. It is **not malware** — it is a stock part of
GNOME.

**Why it grinds.** Default scope is the **entire `$HOME`**:

```bash
gsettings get org.freedesktop.Tracker3.Miner.Files index-recursive-directories
# ['$HOME']
gsettings get org.freedesktop.Tracker3.Miner.Files ignored-directories
# ['po', 'CVS', 'core-dumps', 'lost+found']      <- almost nothing ignored
```

On a developer's home that means `~/go/pkg/mod`, `~/.cache`, `node_modules`,
`Projects/…/target` — hundreds of thousands of files. On this host it also
mis-detected Go's `.mod` files as MIME `audio/x-mod` and logged a warning for
each, adding noise on top of the I/O.

**The fix — narrow, don't disable.** Add the heavy/junk paths to
`ignored-directories` (keep the stock entries), then restart the miner:

```bash
gsettings set org.freedesktop.Tracker3.Miner.Files ignored-directories \
"['po','CVS','core-dumps','lost+found',
  '$HOME/go','$HOME/.cache','$HOME/.cargo','$HOME/.rustup','$HOME/.npm','$HOME/.wine',
  '$HOME/.local/share/containers','$HOME/.local/share/Trash',
  '$HOME/Projects','$HOME/.opencode',
  'node_modules','.git','target','build','dist','.venv','venv','__pycache__']"

gsettings get org.freedesktop.Tracker3.Miner.Files ignored-directories   # verify written
systemctl --user restart localsearch-3.service
```

The list mixes **full paths** for the top-level junk (`$HOME/go`, `$HOME/.cache`)
and **bare names** for caches that can appear anywhere (`node_modules`, `target`,
`.git`). Paths are exact; bare names match any directory of that name.

**Alternatives** (pick per taste, all reversible):

| Option | Command | Effect |
|---|---|---|
| Narrow (this doc, recommended) | add to `ignored-directories` | documents/media still searchable, caches skipped |
| Whitelist folders | `index-recursive-directories` = `['$HOME/Documents','$HOME/Pictures','$HOME/Music','$HOME/Videos','$HOME/Загрузки']` | tiny, fast index; project files not searchable |
| Disable entirely | `systemctl --user mask localsearch-3.service` | zero churn; GNOME file search stops working |

## Part 2 — the usual "quiet" suspects

Check these in the audit output; each has a clear call.

- **Remote-desktop agents.** `anydesk` (listens `tcp/7070`, `udp/50001`) and
  `rustdesk` (`rustdesk --service` as root + `--server` + tray; public
  rendezvous `rs-ny.rustdesk.com:21116`). Running **both** is redundant — keep
  one, remove the other. See `references/07-rustdesk-games.md` and
  `references/20-rustdesk-audio.md` for the RustDesk config.
- **Duplicate MCP servers.** One `opencode` instance spawns its own
  `playwright-mcp` / `mcp-searxng`; several opencode processes → several
  copies (~100 MB each). Close unused editor sessions; don't hand-kill blindly
  (they're children of a live parent).
- **`gnome-software`** can sit with a **CLOSE-WAIT** connection to a CDN for
  hours; it's a package UI, safe to restart (`systemctl --user restart
  gnome-software.service`) or ignore.
- **`opencode serve --service`** accumulated ~49 GiB of writes in ~4.5 h on
  this host (`~/.local/share/opencode/opencode.db`, WAL side-files). If you
  don't need a long-lived server, don't keep it running in the background.
- **`localsearch-3`** itself (Part 1). CPU is tiny (tens of seconds over
  hours); the tell-tale is the **disk I/O and the memory peak**.
- **`wsdd`** (Samba/Web-Service-Discovery) keeps many multicast sockets for
  Windows network discovery. Harmless; remove if you never browse SMB shares.

## Verify

The fix is real only if the indexer stops touching the ignored trees:

```bash
# 0 new warnings/rescans for the ignored trees since the restart (want: 0)
journalctl --user -u localsearch-3.service --since "2 min ago" --no-pager \
  | grep -cE 'go/pkg/mod|/\.cache/|node_modules'

# indexer state (want: "Индексатор бездействует" / idle)
localsearch status

# indexed roots (still $HOME, but junk pruned by ignore list)
localsearch index

# a search must NOT return anything from the ignored trees
localsearch search actionlint | grep -c '/go/'      # want: 0
localsearch search <your-project-name> | grep -c '/Projects/'   # want: 0
```

Note: `localsearch status` may still print a small count of **past** recorded
failures ("отказы") that predate the change — they live in the DB, not the new
run. Judge by the timestamped journal, not the counter.

## Rollback

```bash
gsettings set org.freedesktop.Tracker3.Miner.Files ignored-directories \
  "['po','CVS','core-dumps','lost+found']"
systemctl --user restart localsearch-3.service
```

To wipe the index and rebuild it cleanly with the new scope (optional, triggers
a full re-scan of whatever is not ignored):

```bash
localsearch reset
```

## References

- GNOME LocalSearch (ex-Tracker): GNOME project — `localsearch` / Tracker3
  schema `org.freedesktop.Tracker3.Miner.Files` (`gsettings list-recursively
  | grep Tracker3`).
- `localsearch` CLI subcommands: `index`, `info`, `search`, `status`, `reset`,
  `inhibit` (`localsearch --help`).
- Remote access: `references/07-rustdesk-games.md`,
  `references/20-rustdesk-audio.md`.
- General speed-up (services, boot): `references/01-speedup.md`; read-only
  audit script: `scripts/audit.sh`.
