# dotfiles — Omarchy × chezmoi

Reproducible Omarchy desktop config. The **live config files are the source of
truth** — chezmoi just copies them into place. The repo contains no framework
and nothing that runs on every apply: three tiny run-once setup scripts, one
notify-only drift hook, and this documentation.

- Omarchy v4 (quattro) · Hyprland · managed with [chezmoi](https://www.chezmoi.io/) (installed via mise)
- chezmoi source: `$(chezmoi source-path)` (this repo) → GitHub: `coldter/omarchy-dotfiles` (public)
- Profiles: `desktop` + `laptop1` (see §5 registry). This machine runs `laptop1` (theme `ristretto`).

**Contents:** §1 [Ownership model](#1-the-ownership-model-read-this-first) · §2 [Repo layout](#2-repo-layout) · §3 [New machine bootstrap](#3-new-machine-bootstrap-the-whole-point) · §4 [Daily workflows](#4-daily-workflows) · §5 [Machine profiles](#5-machine-profiles--per-machine-config) · §6 [Themes](#6-themes) · §7 [Safety](#7-safety-rules-this-is-a-public-repo) · §8 [For AI agents](#8-for-ai-agents) · §9 [Troubleshooting](#9-troubleshooting)

---

## 1. The ownership model (read this first)

Everything on an Omarchy system falls into one of four zones. This repo tracks only zones 3+4.

| Zone | Who owns it | Examples | Tracked? |
|---|---|---|---|
| 1. Package-owned | the `omarchy` pacman package | `/usr/share/omarchy/**` | ❌ never |
| 2. Generated state | `omarchy theme set`, shell runtime, `omarchy refresh` backups | `~/.local/state/omarchy/**` (terminal colors, background), `~/.cache/omarchy/**`, `*.bak.*` files | ❌ regenerated; backups are disposable |
| 3. Seeded, then yours | you (Omarchy seeds once, rarely rewrites) | `~/.config/hypr/*.lua`, `~/.config/omarchy/shell.json`, terminal configs, `~/.bashrc` | ✅ |
| 4. Purely yours | you | custom themes, hooks, extensions, branding, git/starship/tmux/btop, mise config | ✅ |

**Why zone 3 is stable:** Omarchy v4 loads its packaged defaults *first*
(`require("default.hypr.omarchy")` from `/usr/share/omarchy/default/hypr/`) and your
files *after* as overrides — in Omarchy's own words, "so package updates can improve
the defaults without rewriting your ~/.config/hypr files". Terminal colors are imported
at runtime from `~/.local/state/omarchy/current/theme/`, so tracked terminal configs
only contain fonts, padding and bindings — never colors.

**The two-writer problem.** Only two events besides you ever write to zone 3:

- `omarchy update` — rare migration scripts (they leave `*.bak.*` files behind)
- `omarchy refresh <app>` — manual, explicit

The reconciliation loop that handles both is documented in §4. A drift hook
(`post-update.d/50-chezmoi-drift-check.hook`) notifies you after every `omarchy update`;
note it does **not** fire after `omarchy refresh` — check `chezmoi diff` manually then.

## 2. Repo layout

```
~/.local/share/chezmoi/               ← chezmoi source state = the git repo
├── .chezmoi.toml.tmpl                # prompts machine profile + theme on `chezmoi init`
├── .chezmoiignore                    # source-only files never applied into $HOME
├── README.md                         # this file
├── .agents/skills/chezmoi-workflows/ # vendored agent skill (see §8)
├── skills-lock.json                  # source + content hash of the vendored skill
├── packages/
│   ├── manual-packages.txt           # YOUR packages from official Arch repos
│   └── aur-packages.txt              # YOUR AUR packages
├── run_once_after_10-packages.sh     # installs the lists above (idempotent)
├── run_once_after_20-theme.sh.tmpl   # omarchy theme set <themeName> (regenerates zone 2)
├── run_once_after_30-mise.sh         # mise install from the tracked config
├── dot_bashrc                        # → ~/.bashrc
├── dot_config/
│   ├── hypr/                         # hyprland.lua, bindings/input/looknfeel/autostart,
│   │                                 # openwhispr-binds.lua + monitors.lua.tmpl (per-machine!)
│   ├── omarchy/
│   │   ├── private_shell.json        # → shell.json (private_ = 0600 perms, Omarchy's choice)
│   │   ├── themes/                   # your custom theme: a-crane-with-a-light-on-top
│   │   │                             # (built-ins like matte-black ship with Omarchy — never tracked)
│   │   ├── hooks/post-update.d/      # setup-agent.hook, executable_50-chezmoi-drift-check.hook
│   │   ├── extensions/               # menu.sh, omarchy-menu.jsonc
│   │   └── branding/
│   ├── alacritty/  foot/  kitty/  ghostty/   # fonts/padding/bindings — colors import from zone 2
│   ├── git/  tmux/  btop/
│   ├── starship.toml
│   └── mise/config.toml              # mise tool list — bun & opencode pinned, rest = latest (§3 note)
└── …
```

**Source-name decoder** (chezmoi encodes file attributes in the name):

| Source name | Becomes |
|---|---|
| `dot_bashrc` | `~/.bashrc` |
| `private_shell.json` | `~/.config/omarchy/shell.json` with mode 0600 |
| `executable_50-chezmoi-drift-check.hook` | target file with the executable bit set |
| `*.tmpl` suffix | a Go template — rendered on apply, never copied verbatim |
| `run_once_after_*` | a script that runs once per content-hash during `chezmoi apply` |

**Not in this repo — per-machine data lives in `~/.config/chezmoi/chezmoi.toml`
(untracked):** the machine profile label + theme, auto-generated by `chezmoi init`
from `.chezmoi.toml.tmpl`. See §5 for its lifecycle.

## 3. New machine bootstrap (the whole point)

```bash
# 1. Install Omarchy from the ISO (stock install, nothing custom).

# 2. Toolchain bootstrap — mise ships with Omarchy (package: mise-bin).
#    Only if it's somehow missing:
command -v mise >/dev/null 2>&1 || omarchy pkg add mise-bin
mise install chezmoi              # NOTE below on pinning

# 3. Deploy everything — run inside a terminal in the Omarchy session
#    (the package script needs a sudo password prompt):
chezmoi init --apply coldter/omarchy-dotfiles
#    → prompts: machine profile label (Enter = desktop) + theme (Enter = matte-black)
#    → renders per-machine templates, copies all configs, then the run-once
#      scripts fire: packages install → theme applies → mise tools install

# 4. If step 3 ran outside a session, finish by hand:
omarchy theme set matte-black
#    then log out / back in.
```

> **Pinning note:** the tracked mise config pins `bun` and `opencode`; `chezmoi`,
> `node` and `pnpm` track `latest`. Until step 3 applies that config, `mise install
> chezmoi` resolves to the latest release of the day — behavior-identical, but for
> bit-for-bit reproducibility pin it: `mise use -g chezmoi@<version>`, then
> `chezmoi add ~/.config/mise/config.toml && chezmoi git -- add -A && chezmoi git -- commit -m "mise: pin chezmoi"`.

**What the bootstrap does NOT cover** (provision these yourself):
`~/.config/chezmoi/chezmoi.toml` is generated fresh (its values are prompted), SSH
keys, `gh auth login`, browser profiles, and secrets — see §7.

### 3.1 Machine #1 — create the remote and first push (once)

Every other machine starts at §3. This one-time step is what makes §3 possible:

1. Create an **empty** repo at `github.com/coldter/omarchy-dotfiles`
   (no README/license — chezmoi owns this history).
2. From this machine:
   ```bash
   chezmoi git -- remote add origin git@github.com:coldter/omarchy-dotfiles.git
   chezmoi git -- push -u origin master
   ```

`chezmoi git -- <cmd>` runs `<cmd>` inside the source repo
(`~/.local/share/chezmoi`) — you never need to `cd` there.

## 4. Daily workflows

### 4.0 Inspect (the read-side commands)

```bash
chezmoi managed     # every file chezmoi tracks (paths under $HOME)
chezmoi unmanaged   # files in $HOME that are NOT tracked
chezmoi status      # tracked targets currently differing from source
chezmoi cat ~/.config/hypr/monitors.lua   # preview a (templated) render — never applies
```

### 4.1 Editing configs (the only habit you need)

```bash
edit files as usual (Omarchy menu, editor, whatever)
chezmoi re-add                 # sync live files → source (or: chezmoi add <path>)
chezmoi git -- add -A && chezmoi git -- commit -m "…" && chezmoi git -- push
```

⚠ `chezmoi re-add` never touches **templated** files (today only `monitors.lua`)
— chezmoi refuses to overwrite templates. Reconcile those by hand: see §5.

### 4.2 Pulling on your other machines

```bash
chezmoi update     # git pull in the source repo, then apply
chezmoi diff       # if anything disagrees with local state, reconcile per §4.3
```

### 4.3 After `omarchy update` (reconciliation — review, then choose)

The drift hook fires automatically: a notification plus a full diff saved to
`~/.local/state/chezmoi-drift/<timestamp>.diff`. Then:

```bash
chezmoi diff                   # what changed vs. your source of truth
chezmoi re-add                 # Omarchy's change is good → adopt it (then commit+push)
                               # ⚠ never touches templated files — handle monitors.lua via §5
chezmoi apply                  # Omarchy's change is bad  → restore yours
```

Rule of thumb: **`omarchy refresh <app>` → almost always reject** (`chezmoi apply`);
**update migrations → usually adopt** (`chezmoi re-add`), unless they clobber your
tweaks. Remember: `omarchy refresh` runs no hook — after a manual refresh, run
`chezmoi diff` yourself. Test the hook anytime with `omarchy hook post-update`.

### 4.4 Adding a package

```bash
omarchy pkg add <pkg>          # try it first, confirm you like it
# then record it in the right list (official repo → manual-packages.txt,
# AUR-only → aur-packages.txt):
echo "<pkg>" >> "$(chezmoi source-path)/packages/manual-packages.txt"
chezmoi git -- add -A && chezmoi git -- commit -m "pkg: <pkg>" && chezmoi git -- push
```

Only add what Omarchy doesn't already ship (check
`/usr/share/omarchy/install/omarchy-*.packages`). `omarchy pkg add` is idempotent,
so accidental duplicates are harmless — but keep the lists meaningful.

### 4.5 Adding a dev tool (mise)

```bash
mise use -g <tool>@<version>   # writes ~/.config/mise/config.toml (tracked)
chezmoi re-add && chezmoi git -- add -A && chezmoi git -- commit -m "mise: <tool>" && chezmoi git -- push
```

## 5. Machine profiles & per-machine config

`dot_config/hypr/monitors.lua.tmpl` is the only templated config. It contains one
Lua block per **machine profile**; chezmoi renders only the matching block into
`~/.config/hypr/monitors.lua`. Unknown profiles (and unset keys) render a generic
fallback block, so a fresh machine always boots with a working display config.

**Conditionals key on the `machine` profile variable — never the hostname.**
Hostnames change (reinstalls, DHCP, cloned VMs); the profile label is a stable,
human-chosen key. Two machines may share a label only if their hardware config
is identical.

**Lifecycle of `~/.config/chezmoi/chezmoi.toml`:** it is not hand-written from
scratch — `chezmoi init` generates it from `.chezmoi.toml.tmpl` (those are the
§3 prompts). To change a machine's label later: `chezmoi edit-config`, change
`[data] machine`, then `chezmoi apply` to re-render templates keyed on it.

```toml
[data]
    machine = "desktop"     # ← this machine's profile label
    themeName = "matte-black"
```

To add a machine with profile `laptop`:

1. On that machine: `hyprctl monitors all` (outputs, modes, positions)
2. Set its profile: `~/.config/chezmoi/chezmoi.toml` → `[data] machine = "laptop"`
3. Edit the template: `chezmoi edit ~/.config/hypr/monitors.lua`
4. Insert a block **above** the generic `{{ else }}` fallback at the bottom of
   the file — an `else if` placed *after* `else` is a template parse error and
   `chezmoi apply` will refuse to render:
   `{{ else if eq (index . "machine" | default "") "laptop" }}` followed by your `hl.monitor()` lines
   (the `index … | default ""` guard means a machine with no `[data] machine` set
   still renders the generic fallback instead of hard-failing `chezmoi apply`)
5. Render + reload: `chezmoi apply ~/.config/hypr/monitors.lua`
6. Validate: `hyprctl configerrors` (must print nothing)
7. Commit: `chezmoi git -- add -A && chezmoi git -- commit -m "monitors: laptop"`

### Machine registry

Profile labels exist only in each machine's untracked `chezmoi.toml` — record
them here so a dead machine's identity is never lost:

| Profile label | Machine | Displays (from `hyprctl monitors all`) | Notes |
|---|---|---|---|
| `desktop` | primary desktop | HDMI-A-1 TV (1080p) above; DP-2 Samsung 144Hz below | workspace 1 pinned to HDMI-A-1 |
| `laptop1` | arch / Lenovo IdeaPad 3 15IIL05 (this machine) | eDP-1 1920x1080@60 internal, scale 1.25 | single panel, no workspace rules |

Other per-machine deltas (input.lua, autostart) can become templates keyed on
`.machine` the same way — only do it when machines actually diverge.

## 6. Themes

Your custom themes live in `~/.config/omarchy/themes/<name>/` (tracked, zone 4) —
currently `a-crane-with-a-light-on-top`. Built-in themes like `matte-black` ship
with Omarchy and are never tracked.

Theme *colors* applied to terminals/btop/etc. are **generated** into
`~/.local/state/omarchy/current/theme/` by `omarchy theme set` — never tracked,
always regenerated (that's why tracked terminal configs contain no color blocks).

**Switching theme on a machine:** `omarchy theme set <name>` applies instantly and
regenerates zone-2 state. To make the choice survive a reinstall, also update
`[data] themeName` (`chezmoi edit-config`) and run `chezmoi apply`: the new name
changes the rendered content of `run_once_after_20-theme.sh`, so chezmoi re-runs
it — that is the whole reason the script is templated.

## 7. Safety rules (this is a public repo)

chezmoi is opt-in — only explicitly added files are tracked (a stray
`git add -A` in `~/.config` can't leak anything). Still:

- **Never track:** `~/.config/gh/` (hosts.yml = OAuth token), `~/.ssh/`,
  `~/.local/share/opencode/` (auth.json), `~/.config/environment.d` secrets,
  `*.local` files, anything token-shaped
- Periodic audit (cwd-independent — `chezmoi managed` prints `$HOME`-relative
  paths, so grep the source directly):
  ```bash
  grep -rEi 'token|secret|api[_-]?key|password' "$(chezmoi source-path)" \
    --exclude-dir=.git --exclude-dir=.agents
  ```
- Edit secrets-adjacent configs in place without `chezmoi add` — they simply
  stay unmanaged.

## 8. For AI agents

**Vendored skill (read first):** this repo ships `chezmoi-workflows` at
`.agents/skills/chezmoi-workflows/SKILL.md` (installed via
`npx skills add terrylica/cc-skills --skill chezmoi-workflows`, source + content
hash pinned by `skills-lock.json`). Follow its workflows — in particular
**Status Check (§1)**, **Safe Update / diff-before-apply (§13)** and
**Validation (§10)**: `chezmoi status` → `chezmoi diff` → explicit
`chezmoi re-add` / `chezmoi apply` → `chezmoi verify`. Never blind-apply.

Operating rules:

1. **Read and follow the vendored skill** (above) before touching anything.
2. Source-of-truth edits happen via the live files + `chezmoi re-add`
   (or `chezmoi edit <target>`, which edits source and applies on save).
3. **Never** edit rendered output of `*.tmpl` files directly
   (`~/.config/hypr/monitors.lua`) — edit the template in source.
4. Per-machine conditionals key on the `[data] machine` profile variable —
   **never on hostname**. Set it in `~/.config/chezmoi/chezmoi.toml` (untracked).
5. `chezmoi re-add` skips templated files. To adopt upstream changes into a
   template: `chezmoi edit` the template, then `chezmoi apply` (see §4.3/§5).
6. After any Omarchy update/refresh: run `chezmoi diff`, report the drift to the
   user, then `chezmoi re-add` (adopt) or `chezmoi apply` (reject) per their call.
   Never apply/revert without asking.
7. New files belong in the tracked set only after the user confirms they're
   wanted on every machine (zone 3/4 only — see §1).
8. Validate Hyprland changes: `hyprctl reload && hyprctl configerrors` (must be empty).
9. Commit messages: short, lowercase prefix (`pkg:`, `mise:`, `monitors:`, `hypr:`, `omarchy:`, `docs:`, `agents:`).
10. The drift hook must always exit 0 and never apply changes — keep it that way.

## 9. Troubleshooting

| Symptom | Fix |
|---|---|
| Terminal lost colors after a restore | `omarchy theme set <name>` — regenerates zone-2 state (§6) |
| `omarchy refresh` clobbered your tweaks | `chezmoi apply <path>` restores yours |
| `chezmoi diff` shows drift after every update | Omarchy rewrote a managed file — reconcile (§4.3) |
| Drift notification never appeared after an update | Test the hook: `omarchy hook post-update`; check `~/.local/state/chezmoi-drift/` |
| New machine is missing a package | Add it to `packages/*.txt`, then run `~/.local/share/chezmoi/run_once_after_10-packages.sh` manually |
| `mise install` says a tool is missing | `mise install` from any directory; check `~/.config/mise/config.toml` |
| Want to preview a template without applying | `chezmoi cat ~/.config/hypr/monitors.lua` |
| `chezmoi git -- push` fails | No remote on this machine — do §3.1 (machine #1 first push) |
| A tracked file you no longer want (`chezmoi managed` lists the tracked set) | `chezmoi forget <path>` — removes from source, keeps the live file |
| Machine boots with fallback monitor config | Its profile has no block in `monitors.lua.tmpl` — add one (§5) |
