# 17 · OpenCode 2 (beta) — AI coding agent, install & run

Verified live: Fedora 44, node v22.23.1 / npm 10.9.8, `~/.local` npm
prefix (no sudo). Result: `opencode2` v0.0.0-beta-18155 installed and
running as a native binary, side by side with OpenCode 1 — this doc is
itself written by it. Source: opencode.ai/v2/docs (official beta docs).

## What it is

- **OpenCode 2 (beta)** — the next-gen open source AI coding agent
  (terminal TUI). Will become OpenCode 2.0; the beta is still changing
  (APIs/config/plugins may break).
- Installs and runs as **`opencode2`** — it does NOT replace OpenCode 1's
  `opencode` binary; both can live on one machine and be run side by side.
- Built-in support for many LLM providers (connect in the TUI via
  `/connect`), plugins, MCP servers, themes/keybinds.

## Install (per-user npm, no sudo — verified path)

This host has npm prefix pointed at `~/.local`, so no root needed:

```bash
npm config get prefix            # must be a user dir: /home/<user>/.local
npm install -g @opencode-ai/cli@beta
which opencode2                  # ~/.local/bin/opencode2
opencode2 --version              # v0.0.0-beta-XXXX
```

- The package runs a **trusted postinstall script** that selects the
  native `opencode2` binary for your platform. If npm skip-scripts is
  on, use the explicit flags instead:
  `bun install -g --trust @opencode-ai/cli@beta` or
  `pnpm add -g --allow-build=@opencode-ai/cli @opencode-ai/cli@beta`.
- One-liner alternative: `curl -fsSL https://opencode.ai/v2/install | bash`
  (custom dirs: `$OPENCODE_INSTALL_DIR`, `$XDG_BIN_DIR`, `$HOME/bin`,
  `$HOME/.opencode/bin`).
- During beta NOT supported: Homebrew, Arch Linux, Windows package
  managers, Docker, standalone binaries.

## First run

```bash
cd <your-project>
opencode2              # start the TUI
```

- `/connect` — pick a provider, paste the API key (or opencode.ai/auth,
  then copy the key back).
- **Tab** toggles agents: `build` (full access, default) ↔ `plan`
  (read-only: suggests, asks before shell commands, edits denied).
- `init` — create `AGENTS.md` in the project root (project rules/memory).
- `/undo` — revert the last change batch; `/redo` — redo it.
- `/share` — grab a shareable link to the current conversation.
- `@general` — internal subagent for complex searches / multi-step tasks.

## Pitfalls

1. **`opencode2` vs `opencode` are different programs** — v2 is beta and
   does not replace v1; if you later install v1 it will not overwrite v2.
2. **Beta instability** — config/plugin APIs may change without notice;
   pin versions and keep the v1 install if you depend on it.
3. **Trusted postinstall is required** — plain `npm` runs it, but bun /
   pnpm need an explicit `--trust` / `--allow-build` flag or the native
   binary will not be fetched.
4. **No API key = nothing to run** — the agent needs a provider
   (OpenCode Zen / any provider) configured before first use.
5. **Docker/scoop/choco/brew are NOT available for v2 in beta** — only
   npm/bun/pnpm/yarn/curl script.

## Verified

2026-08-25: `opencode2` symlink
`~/.local/bin/opencode2 → ../lib/node_modules/@opencode-ai/cli/bin/opencode2.exe`,
`opencode2 --version` → `v0.0.0-beta-18155`, `npm ls -g` →
`@opencode-ai/cli@0.0.0-beta-18155`, npm prefix `/home/<user>/.local`
(sudo-free install). ✅
