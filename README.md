# dotfiles — Omarchy × chezmoi

Omarchy v4 (quattro) / Hyprland config, tracked with [chezmoi](https://www.chezmoi.io/).
**Live files are the source of truth** — chezmoi copies them into place.
Source: `$(chezmoi source-path)` → `coldter/omarchy-dotfiles` (public). This machine: profile `desktop`, theme `matte-black`.

## 1. Ownership model

| Zone | Owner | Examples | Tracked |
|---|---|---|---|
| 1 · package | `omarchy` pacman pkg | `/usr/share/omarchy/**` | ❌ |
| 2 · generated | `omarchy theme set`, refresh backups | `~/.local/state/omarchy/**`, `~/.cache/omarchy/**`, `*.bak.*` | ❌ |
| 3 · seeded, then yours | you | `~/.config/hypr/*.lua`, `~/.config/omarchy/shell.json`, terminal configs, `~/.bashrc` | ✅ |
| 4 · yours | you | custom themes/hooks/extensions/branding, git/starship/tmux/btop, mise, pi + omp configs | ✅ |

Zone 3 is stable: Omarchy loads packaged defaults first, your files after as overrides; terminal colors import at runtime from zone 2 — tracked terminal configs contain no colors.
Besides you, only `omarchy update` (migrations, leaves `*.bak.*`) and `omarchy refresh <app>` write zone 3. The drift hook notifies after `update` only (§4.3).

## 2. Repo layout

```
~/.local/share/chezmoi/        ← source state = this repo      .chezmoi.toml.tmpl  # init prompts
├── .chezmoiignore             # source-only files              skills-lock.json
├── .agents/skills/{chezmoi-workflows,chezmoi-sync}/   # vendored skills, source-only (§8)
├── packages/{manual,aur}-packages.txt                 # package lists (run_once_after_10)
├── run_once_after_{10-packages.sh,20-theme.sh.tmpl,30-mise.sh}
├── dot_bashrc · dot_agents/skills/i-have-adhd/        # i-have-adhd = pi's symlink target
├── dot_pi/private_agent/                              # → ~/.pi/agent/ 0700 — pi (§4.6)
├── dot_omp/private_agent/private_config.yml           # → ~/.omp/agent/config.yml 0600 (§4.8)
├── dot_omp/plugins/                                   # → ~/.omp/plugins/ manifests (§4.8)
└── dot_config/
    ├── hypr/    # hyprland.lua.tmpl + monitors.lua.tmpl (per-machine), bindings/input/
    │            # looknfeel/autostart, openwhispr-binds.lua §4.7
    ├── omarchy/ # private_shell.json (0600), themes/, hooks/post-update.d/,
    │            # extensions/ (menu.sh, omarchy-menu.jsonc), branding/
    ├── alacritty/ foot/ kitty/ ghostty/ · git/ tmux/ btop/ · starship.toml
    └── mise/config.toml       # tool list — pins bun 1.4.2, rest `latest`
```

Source-name decoder: `dot_x` → `~/.x`; `private_` → 0600 (dirs 0700, e.g. `private_agent/`); `executable_` → +x; `*.tmpl` → Go template, rendered on apply; `run_once_after_*` → once per content hash; `symlink_x` → symlink to the path stored in the file.

**Deliberately untracked** (secret/regenerable — §7):
- pi: `auth.json` (API key — `/login` again), `sessions/`, `npm/`, `models-store.json`, `commandcode-models.json`, `trust.json`.
- omp: `agent/agent.db` (**holds provider credentials** — log in again), `agent/{history,models,skill-descriptions}.db`, `agent/{cache,sessions,terminal-sessions}/`, `agent/last-changelog-version`, `plugins/{node_modules,bun.lock}`, `logs/`, `natives/`, `run/`, `cache/`. omp's lazy `agent/{rules,agents,managed-skills}/`: `chezmoi add` once you put files there.
- per-machine `~/.config/chezmoi/chezmoi.toml` (§5).

## 3. New machine bootstrap

```bash
# 1. Stock Omarchy ISO install.
# 2. Toolchain — mise ships with Omarchy (only if missing):
command -v mise >/dev/null || omarchy pkg add mise-bin
mise install chezmoi
# 3. Deploy — run inside the Omarchy session (the package step needs sudo):
chezmoi init --apply coldter/omarchy-dotfiles
#    prompts: machine profile (Enter = desktop) + theme (Enter = matte-black)
#    → renders templates, copies configs, then run-once: packages → theme → mise
# 4. If run outside a session: omarchy theme set matte-black   # then log out/in
```

The mise config pins `bun` = 1.4.2, everything else `latest` (incl. `chezmoi`) — to pin the chezmoi you just installed: `mise use -g chezmoi@<version>` then `chezmoi add ~/.config/mise/config.toml` + commit.

Not covered: `chezmoi.toml` (generated from the prompts), SSH keys, browser profiles, secrets (§7). Agents: pi — run `/login` (its npm packages rebuild from the tracked `settings.json`); omp — log in (credentials live only in the untracked `agent.db`), then `bun install` in `~/.omp/plugins` to restore the tracked plugin manifest.

### 3.1 Machine #1 — create an empty `coldter/omarchy-dotfiles` repo (no README/license), then

```bash
chezmoi git -- remote add origin git@github.com:coldter/omarchy-dotfiles.git
chezmoi git -- push -u origin master
```

`chezmoi git -- <cmd>` runs inside the source repo — no `cd` needed.

## 4. Daily workflows

### 4.0 Inspect

```bash
chezmoi managed            # tracked files        chezmoi unmanaged   # untracked files in $HOME
chezmoi status             # current drift        chezmoi cat <target>  # preview a render, no apply
```

### 4.1 Edit configs (the only habit)

```bash
# edit the live file, then:
chezmoi re-add [<path>]    # live → source
chezmoi git -- add -A && chezmoi git -- commit -m "<prefix>: …" && chezmoi git -- push
```

⚠ `re-add` never touches templates (`monitors.lua`, `hyprland.lua`) — edit those with `chezmoi edit <target>` (§5).

### 4.2 Other machines

```bash
chezmoi update             # pull source + apply; then chezmoi diff and reconcile per §4.3
```

### 4.3 After `omarchy update` (hook fires: notification + `~/.local/state/chezmoi-drift/<ts>.diff`)

```bash
chezmoi diff               # drift vs your source of truth
chezmoi re-add             # adopt it (then commit + push)
chezmoi apply              # or reject it (restore yours)
```

`omarchy refresh <app>` → usually reject; update migrations → usually adopt unless they clobber your tweaks. No hook after `refresh` (run `chezmoi diff` yourself). Test: `omarchy hook post-update`.

### 4.4 Add a package

```bash
omarchy pkg add <pkg>          # only if Omarchy doesn't ship it (/usr/share/omarchy/install/*.packages)
echo <pkg> >> "$(chezmoi source-path)/packages/manual-packages.txt"   # AUR → aur-packages.txt
chezmoi git -- add -A && chezmoi git -- commit -m "pkg: <pkg>" && chezmoi git -- push
```

### 4.5 Add a dev tool (mise)

```bash
mise use -g <tool>@<version>   # writes tracked ~/.config/mise/config.toml
chezmoi re-add && chezmoi git -- add -A && chezmoi git -- commit -m "mise: <tool>" && chezmoi git -- push
```

mise rewrites/normalizes this file (`upgrade`, `prune`, shortname forms) — adopt (`re-add`), never `apply` a stale spec back.

### 4.6 pi config

`~/.pi/agent/` is tracked (`settings.json`, `extensions/`, `themes/`, `skills/`); pi writes it via `/settings`, `/model`, `/theme`, `/login`:

```bash
chezmoi re-add ~/.pi/agent/settings.json     # or just: chezmoi re-add
# then commit "pi: …" + push — /login only writes the untracked auth.json
```

`lastChangelogVersion` bumps on every pi upgrade — expected drift, adopt it (or defer until the next real change).

### 4.7 OpenWhispr-owned Hyprland files — mirror, never patch

OpenWhispr rewrites them on every hotkey registration: `openwhispr-binds.lua` (canonical 2-line header, plain comments preserved) and appends `pcall(require, "<abs>/openwhispr-binds.lua")` to `hyprland.lua`. Our source mirrors the output **byte-for-byte** (`hyprland.lua.tmpl` renders the absolute path), so the app's write is a no-op — never restore the portable module name `hypr.openwhispr-binds` (commit `4aa5015`) or trim the header; the app recognizes neither (duplicate require + header rewrite). If drift returns after an upgrade, re-derive and re-adopt:

```bash
grep -a -o -b 'openwhispr-binds' /opt/openwhispr/resources/app.asar
dd if=/opt/openwhispr/resources/app.asar bs=1 skip=<offset> count=30000
# update template/header → chezmoi apply → hyprctl configerrors (must be empty)
```

### 4.8 omp config

omp (oh-my-pi) writes its own files: `~/.omp/agent/config.yml` (`modelRoles`, `symbolPreset`, `setupVersion`) and `~/.omp/plugins/{package.json,omp-plugins.lock.json}` (declared plugin set + enabled state; omp pins ranges to the installed version, e.g. `^0.10.1` → `0.9.0`):

```bash
chezmoi re-add ~/.omp       # config.yml + manifests; DBs/node_modules/bun.lock stay untracked
# then commit "omp: …" + push
```

`agent/last-changelog-version` is untracked, so upgrade bumps never drift; credentials live only in the untracked `agent.db`.

## 5. Machine profiles

`monitors.lua.tmpl` holds one block per `[data] machine` profile, else a generic fallback; `hyprland.lua.tmpl` supplies the §4.7 absolute path. **Key on `machine`, never hostname** (hostnames change; two machines share a label only if their hardware matches). `~/.config/chezmoi/chezmoi.toml` is generated by `chezmoi init` from `.chezmoi.toml.tmpl`; change it with `chezmoi edit-config` + `chezmoi apply`.

```toml
[data]
    machine = "desktop"      # this machine
    themeName = "matte-black"
```

Add a machine: `hyprctl monitors all` there → `chezmoi edit-config` (`[data] machine = "<label>"`) → `chezmoi edit ~/.config/hypr/monitors.lua`, inserting **above** the `{{ else }}` fallback (an `else if` after `else` is a parse error): `{{ else if eq (index . "machine" | default "") "<label>" }}` + `hl.monitor()` lines → `chezmoi apply ~/.config/hypr/monitors.lua` → `hyprctl configerrors` empty → commit `monitors: <label>`.

Registry (labels live only in each machine's untracked chezmoi.toml — keep current):

| Profile | Machine | Displays | Notes |
|---|---|---|---|
| `desktop` | primary desktop | HDMI-A-1 TV above; DP-2 144 Hz below | ws 1 pinned to HDMI-A-1 |
| `laptop1` | Lenovo IdeaPad 3 15IIL05 | eDP-1 1080p@60, scale 1.25 | single panel |

## 6. Themes

Custom themes: `~/.config/omarchy/themes/<name>/` (tracked; currently `a-crane-with-a-light-on-top`). Built-ins like `matte-black` ship with Omarchy — never tracked. Colors are zone-2 state (`~/.local/state/omarchy/current/theme/`), regenerated by `omarchy theme set` — tracked terminal configs contain none.
To survive reinstall: `omarchy theme set <name>` + `chezmoi edit-config` → `[data] themeName` → `chezmoi apply` (re-renders `run_once_after_20-theme.sh`, so chezmoi re-runs it).

## 7. Safety (public repo)

Tracking is opt-in (`chezmoi add`) — a stray `git add -A` in `~/.config` can't leak — still:
- **Never track:** `~/.config/gh/` (OAuth token), `~/.ssh/`, `~/.local/share/opencode/` (auth), `~/.pi/agent/auth.json`, `~/.omp/agent/agent.db` (credentials), `~/.config/environment.d` secrets, `*.local`, anything token-shaped.
- **Not worth tracking:** the generated state listed in §2 (agent DBs, sessions/caches, `node_modules`, `last-changelog-version`, npm rebuilds, model catalogs).
- Audit: `grep -rEi 'token|secret|api[_-]?key|password' "$(chezmoi source-path)" --exclude-dir=.git --exclude-dir=.agents`
- Secrets-adjacent files: edit in place, never `chezmoi add`.

## 8. For AI agents

Vendored skill: `.agents/skills/chezmoi-workflows/SKILL.md` (+ `chezmoi-sync`; both source-only via `.chezmoiignore`, hashes in `skills-lock.json`) — follow its status → diff → re-add/apply → verify flow; never blind-apply. Every vendored skill must be listed in `.chezmoiignore` (only `i-have-adhd` is tracked, as pi's symlink target).

1. Read the vendored skill first; adopt live files with `chezmoi re-add` (or `chezmoi edit <target>`); never edit `*.tmpl` renders.
2. Per-machine conditionals: `[data] machine` only, never hostname.
3. After Omarchy update/refresh: `chezmoi diff`, report, adopt/reject per user's call; new tracked files only with user confirmation (zones 3/4).
4. Hyprland changes: `hyprctl reload && hyprctl configerrors` empty.
5. Commit prefixes: `pkg: mise: monitors: hypr: omarchy: docs: agents: pi: omp:`; the drift hook must exit 0 and never apply.
6. pi (`~/.pi/agent/`) and omp (`~/.omp/agent/`, `~/.omp/plugins/`) configs are tracked; credential stores, sessions, caches, catalogs stay untracked (§2, §7).

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Terminal lost colors after restore | `omarchy theme set <name>` |
| `omarchy refresh` clobbered tweaks | `chezmoi apply <path>` |
| Drift after every update | Omarchy rewrote a managed file — reconcile (§4.3) |
| No drift notification after an update | `omarchy hook post-update`; check `~/.local/state/chezmoi-drift/` |
| Missing package / tool on a new machine | `packages/*.txt` + `run_once_after_10-packages.sh`; `mise install` |
| Preview a template | `chezmoi cat <target>` |
| `git push` fails | No remote → §3.1; 403 → `env -u GITHUB_TOKEN chezmoi git -- push` |
| Untrack a file | `chezmoi forget <path>` (live file stays) |
| pi settings drift = only `lastChangelogVersion` | Expected after an upgrade — `re-add` (§4.6) |
| `openwhispr-binds.lua` / `hyprland.lua` drift after OpenWhispr starts | Its writer changed — re-derive + re-adopt (§4.7) |
| `MM` on `.pi/agent` / `.omp/agent`, mode diff only | `chmod` on source dirs is ignored and `re-add` skips dirs — carry `private_agent` in the name (0700) |
| `~/.omp/agent/config.yml` or `~/.omp/plugins/*` drift | omp writes its own config — `chezmoi re-add ~/.omp` (§4.8) |
| omp plugins missing after restore | `bun install` in `~/.omp/plugins` (§3) |
| pi `i-have-adhd` skill dangles | Its target `~/.agents/skills/i-have-adhd` is tracked — `chezmoi status`/`apply` |
| Fallback monitor config on a new machine | Add its profile block (§5) |
