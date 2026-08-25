# 18 · Camoufox Research MCP — install in OpenCode 2, fix the "Unknown tool" curse

Verified live: Fedora 44, OpenCode 2 (`opencode2` v0.0.0-beta-18155),
camoufox-research v0.2.0. Result: `opencode2 mcp list` → `✓ camoufox
connected`; the agent calls all 48 tools DIRECTLY (this doc's research,
fetch and shell calls above are live proof). The old curse —
"Unknown tool" on direct calls — no longer reproduces in current
OpenCode: it was a stale-tool-cache problem of old sessions, not a
broken server.

## What it is

- **camoufox-research** — your own MCP server (48 tools) giving the
  agent a real anti-detect browser: search, deep research (10+ sources),
  read JS/SPA pages, live sessions (clicks/forms/uploads), screenshots
  with Set-of-Mark, crawl/map/sitemap, extract/tables→CSV, export
  json/csv/md, page-diff monitoring, proxies, login profiles.
- Runs as a **stdio MCP server** (`camoufox-research` binary from a venv)
  wired into OpenCode via `~/.config/opencode/opencode.json`.

## Install (4 steps, no sudo)

```bash
# 1. clone (to any work dir, e.g. ~/projects)
git clone https://github.com/aidvizhhub/camoufox-research.git

# 2. isolated venv + package
python3 -m venv ~/.venvs/camoufox-research
~/.venvs/camoufox-research/bin/pip install .

# 3. download the browser ONCE
~/.venvs/camoufox-research/bin/python -m camoufox fetch

# 4. smoke check (waits on stdin — stdio server)
~/.venvs/camoufox-research/bin/camoufox-research
```

## Wire into OpenCode 2 (`~/.config/opencode/opencode.json`)

```json
{
  "mcp": {
    "camoufox": {
      "type": "local",
      "codemode": false,
      "command": ["/home/<user>/.venvs/camoufox-research/bin/camoufox-research"],
      "enabled": true
    }
  }
}
```

- `codemode: false` — required by this server (it needs the full runtime
  tool catalog, not the code-mode sandbox). The old lesson from the
  tribe's ledger (BROlegacy): with `codemode: true` the tools show up in
  the catalog but a direct call dies with "Unknown tool".
- `enabled: true` — same as omitting it; explicit is better for toggling.

## Check & first use

```bash
opencode2 mcp list        # → ✓ camoufox  connected
```

Then just ask the agent, e.g.:
"Find the latest articles about Camoufox, compare them and save the result
to Markdown." — it will chain `research` → `fetch_page` → `export`
by itself. No browser automation code needed.

## Pitfalls — the historical curses and their real fixes

1. **"Unknown tool" when calling camoufox.* directly** — that was a
   stale tool-cache: the server was connected, but the old session's
   catalog was dead forever. Fixes that WORK: start a NEW session
   (tools re-register); `opencode2 service restart` + new session.
   `opencode2 mcp list` showing "connected" is NOT proof the current
   session can call the tools.
2. **`camoufox Connection closed`** — server process died (VNC/browser
   crash). Fix: kill the leftover process, disconnect from MCP, connect
   again, then fresh session. One server, no parallel instances
   (single-instance canon of the tribe).
3. **Fallback canon** — if the server is really down: web search +
   plain fetch still give 10+ sources; say "кауфми лёг" and continue
   with the fallback instead of hammering the same tool 4 times.
4. **Python from python.org (not MS Store) + VC++ Redistributable** —
   required on Windows; on Fedora just `python3` (3.10-3.12).
5. **`stats` masks secrets** — use it to audit the server work; API keys
   from profiles never leak into the report.

## Verified

2026-08-25: `opencode2 --version` → v0.0.0-beta-18155; `opencode2 mcp
list` → `✓ camoufox connected`; live session CALLED `camoufox_batch_fetch`
directly (no execute shim) and got the repo README back — first run
after install, no "Unknown tool". Config file
`~/.config/opencode/opencode.json` has `mcp.camoufox` local + codemode
false + venv path. ✅
