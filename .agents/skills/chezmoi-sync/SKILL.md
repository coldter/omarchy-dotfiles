---
name: chezmoi-sync
description: Full chezmoi sync flow — fetch upstream, check git + drift diff, pull, apply or re-add, resolve conflicts, validate, push. TRIGGERS - sync dotfiles, check diff, fetch upstream, pull apply push, drift, conflict, behind ahead.
allowed-tools: Read, Edit, Bash
---

# Chezmoi Sync (fetch → diff → pull → apply → push)

> **Self-Evolving Skill**: If a command fails, a flag drifted, or a workaround was needed — fix this file immediately. Only for real, reproducible issues.

## When to Use

- "check the diff", "sync dotfiles", "fetch upstream", "apply as needed", "push the changes"
- `chezmoi status` shows drift, or git is behind/ahead of origin
- After an Omarchy update/refresh (it rewrites managed files)
- Any merge/apply conflict in the chezmoi source repo

## 0. Preflight

```bash
chezmoi source-path                    # source dir (this repo); cd here first
chezmoi git -- remote -v               # expect origin → coldter/omarchy-dotfiles
chezmoi git -- status -sb              # branch tracking line
cat ~/.config/chezmoi/chezmoi.toml     # note [data] machine profile (never hostname)
```

Always run git via `chezmoi git --` (portable across custom `sourceDir`), or plain `git` with cwd = source dir.

## 1. Fetch + Git State

```bash
chezmoi git -- fetch --all -p
chezmoi git -- status -sb                              # [behind N] / [ahead N]
git rev-list --left-right --count HEAD...@{u}          # "<ahead> <behind>"
chezmoi git -- log HEAD..origin/master --oneline       # what upstream added
chezmoi git -- diff HEAD..origin/master --stat         # upstream file list
chezmoi git -- diff HEAD..origin/master                # review upstream content
git status --porcelain                                  # local dirt: must be empty before pull
git diff --stat; git diff --cached --stat               # uncommitted / staged changes
```

- Behind + clean → safe to fast-forward (Phase 4).
- Ahead → needs push (Phase 6), never reset without asking.
- Dirty (uncommitted) → stash or commit first; never pull over dirt.

## 2. Drift Check (source vs home)

```bash
chezmoi status                         # one line per drifted file
chezmoi diff 2>&1 | head -n 100        # what `apply` WOULD do to $HOME
chezmoi diff ~/.config/path/file 2>&1  # per-file review
chezmoi verify; echo "verify:$?"       # 0 = clean, 1 = drift remains
```

Status columns (`chezmoi status --help`): col-1 = last-written vs actual (your edits/Omarchy rewrites), col-2 = actual vs target (`apply` effect).

**`chezmoi diff` direction**: `a/` = **live target** (`$HOME`), `b/` = **source** (desired) — `-` lines are what is on disk now, `+` lines are what source/`apply` would write. Confirm on one known file (`chezmoi cat <target>`) before reading a diff backwards.

| Code | Meaning |
| ---- | ------- |
| ` M` | source changed (e.g. just pulled) — `apply` will update target |
| `MM` | both sides changed — `apply` needs review, may need `--force` |
| `MM` on `hyprland.lua` + `openwhispr-binds.lua` | OpenWhispr rewrote its **app-owned** files. Source mirrors the app's canonical output byte-for-byte, so a rewrite is a no-op (§3.1). Drift that recurs after an app upgrade = the app changed its writer → re-derive and re-adopt (§3.1) |

Name decoding: source `private_shell.json` → target `shell.json` (`private_` = 0600, not a name change). `*.tmpl` files never render 1:1 — check with `chezmoi cat <target>`.

## 3. Decision Matrix (per file)

| Observation | Action |
| ----------- | ------ |
| Upstream changed source, target stale (` M`, diff matches upstream intent) | `apply` (source wins) |
| You edited target and want to keep it | `chezmoi re-add <target>` (target wins → new source commit → push) |
| Omarchy rewrote a managed file, source version is intentional (e.g. deduped comments) | `apply --force` (source wins; drift will likely return — do NOT loop) |
| Drift is in a `*.tmpl` rendered file (e.g. `monitors.lua`) | NEVER `re-add` (chezmoi refuses templates). `chezmoi edit <target>` the template, then `apply` |
| `lifeExpectancy`-style value drift where source is already committed | `apply` (target stale) |
| `MM` on `.config/mise/config.toml` (source `npm:<pkg>` vs live shortname) | mise rewrote it: adopt per README §4.5 — `chezmoi re-add <target>`, commit `mise: …`, push |
| `MM` on `.pi/agent/settings.json`, only `lastChangelogVersion` older in source | pi's own write on every upgrade; README §4.6 calls it expected drift — `re-add` (never `apply` the stale value back) |
| `MM` on `.omp/agent/config.yml` (`modelRoles`/`symbolPreset`/`setupVersion` differ live) | omp (oh-my-pi) writes its own config (onboarding, model selection); README §4.8 — adopt live (`re-add ~/.omp`), never `apply` a stale value back |
| `MM` on `.omp/plugins/package.json` / `omp-plugins.lock.json` | `omp plugin install\|enable\|disable` wrote them — adopt live (`re-add`); `node_modules/` + `bun.lock` are untracked and rebuilt by `bun install` |
| `MM` on `.config/Code/User/settings.json` (live newer than last commit; formatter / `github.copilot.enable` keys differ) | VS Code UI writes this file — adopt live (`re-add`), per repo precedent `vscode: adopt live …` |
| `MM` on `.config/mise/config.toml` where live **added** a backend-explicit key (e.g. `"github:can1357/oh-my-pi" = "latest"`) | a `mise use` write — live config mtime ≈ the new `installs/<backend>-<owner>-<repo>/` mtime proves the author (e.g. `installs/github-can1357-oh-my-pi` + `omp` bin). NOT a mere rename: `apply` drops the declaration and `auto_prune = true` eventually prunes the install. Adopt per README §4.5 (`re-add`), never `apply` |
| `MM` on `.config/mise/config.toml` where live **dropped** a declared `"npm:<pkg>"` line | not a normalizing rewrite — `mise registry <t>` errors, so `npm:` is the only valid form. Probe `mise ls <t>` / `mise which <t>`; installed-but-*inactive* means the declaration is gone: ask whether to adopt the removal (`re-add`, tool becomes orphan/prunable) or restore (`apply`) |
| `MM` on a **directory** (e.g. `.pi/agent`, `.omp/agent`) | dir mode drift only — target dir mode is NOT taken from the source dir's mode (`chmod` the source dir is ignored), and `re-add` skips non-files. Rename the source dir with the `private_` attribute (e.g. `dot_pi/private_agent`, `dot_omp/private_agent` → 0700); never plain-`chmod` it |
| Unsure | show the per-file `chezmoi diff`, ask user: adopt (`re-add`) or reject (`apply`) |

Before treating a mise `npm:<pkg>` ↔ shortname pair as cosmetic, resolve the backend — a
shortname may pick a *different* backend than the explicit spec:

```bash
mise registry <name>   # shortname → backend priority list (first match wins)
cat ~/.local/share/mise/installs/<name>/.mise.backend.toml  # e.g. full = "aqua:earendil-works/pi", explicit_backend = false
ls ~/.local/share/mise/installs/   # npm-<pkg> dirs exist only for npm-backend tools
```

Adopting the shortname matches what `mise use`/`mise install` write and what is physically
installed; `apply`-ing the explicit form back can install a second copy under a different
`installs/` dir. Repo policy (README §4.5) is to adopt mise's write, so no need to ask — but only for a mere `npm:<pkg>` ↔ shortname rename. A declaration *disappearing* leaves the CLI inactive (`mise which` fails), so ask per §3.

### 3.1 OpenWhispr-owned Hypr files (mirrored, not patched)

OpenWhispr (AUR `openwhispr-bin`) rewrites both files on every hotkey registration:

- `~/.config/hypr/openwhispr-binds.lua` — rebuilt with its 2-line `MANAGED_HEADER_TEXT`
  (`OpenWhispr keybinds (managed automatically)` + `If you delete this file, also remove
  the matching load line from your Hyprland config.`); plain comment lines are preserved.
- `~/.config/hypr/hyprland.lua` — appends `pcall(require, "<abs>/openwhispr-binds.lua")`.
  Its filter removes only existing lines that contain the filename *and* start with
  `pcall(require,` (i.e. not a portable module name).

Repo policy: source mirrors the app's output **byte-for-byte** so the app's write is a
no-op — `dot_config/hypr/hyprland.lua.tmpl` renders the absolute path via
`{{ .chezmoi.homeDir }}`, and `openwhispr-binds.lua` carries the exact app header.
Never restore the portable `pcall(require, "hypr.openwhispr-binds")` (commit `4aa5015`)
or a trimmed header: the app recognizes neither, so it appends a duplicate absolute-path
require (double load) or rewrites the header. Diagnose the diff first with
`git log -S openwhispr -- dot_config/hypr/`.

If drift reappears (an app upgrade changed its writer), re-derive the canonical output
from the installed app and re-adopt:

```bash
grep -a -o -b 'openwhispr-binds' /opt/openwhispr/resources/app.asar     # find offsets
dd if=/opt/openwhispr/resources/app.asar bs=1 skip=<offset> count=30000  # MANAGED_HEADER_TEXT / sourceLine
```

Update the template/header, `chezmoi apply --force`, then verify: `hyprctl configerrors`
empty, the bind present (`hyprctl binds -j | grep -A5 F1`), `chezmoi status` clean.

## 4. Pull

```bash
chezmoi git -- pull --ff-only 2>&1     # fast-forward only; aborts on divergence
chezmoi status                         # re-check drift — upstream may add ` M` entries
chezmoi diff 2>&1 | head -n 100
chezmoi apply --dry-run --verbose 2>&1 | head -n 40
```

### Resolve git conflicts (only if `--ff-only` refuses)

```bash
chezmoi git -- status                  # conflicted files
chezmoi git -- diff                    # review markers
# edit resolved files in source dir, then:
chezmoi git -- add <resolved-files>
chezmoi git -- commit -m "<prefix>: resolve merge conflict"
chezmoi apply                          # redeploy
chezmoi git -- push
# or abandon: chezmoi git -- merge --abort
```

Commit prefix convention: lowercase (`pkg:`, `mise:`, `monitors:`, `hypr:`, `omarchy:`, `docs:`, `agents:`).

## 5. Apply

```bash
# NEVER pipe apply --verbose through head — SIGPIPE kills chezmoi mid-run (see Notes).
chezmoi apply --dry-run --force --verbose > /tmp/opencode/apply-dry.log 2>&1; echo "exit:$?"
head -n 40 /tmp/opencode/apply-dry.log                 # must review first
chezmoi apply --force --verbose > /tmp/opencode/apply.log 2>&1; echo "exit:$?"  # --force ONLY after diff review
tail -n 60 /tmp/opencode/apply.log
chezmoi apply --force --verbose ~/.config/path/file    # per-file retry if one entry sticks
```

Notes:

- Plain `apply` — and even `--dry-run` — aborts with `could not open a new TTY` when a file `has changed since chezmoi last wrote it`: the guard fires before preview too. Add `--force` to the dry-run, review the diff, then `apply --force`.
- Never run `chezmoi apply --verbose | head -n N`: when `head` exits, chezmoi dies from SIGPIPE partway through and later entries are silently skipped (they linger as ` M`/`MM`/` A` in `status`). Redirect to a log file, check the real `exit:$?`, and read the log with `head`/`tail`. Same applies to the `--dry-run` (truncated review).
- `apply` may need two passes: re-run `status` after the first pass; a leftover `MM` (seen with `shell.json`) clears on per-file `--force` retry.
- Templates: verify rendering with `chezmoi cat <target>`; new `monitors.lua.tmpl` blocks go ABOVE the `{{ else }}` fallback or the template fails to parse.
- After Hyprland files: `hyprctl configerrors` must print nothing.

## 6. Push Path (only when source changed via `re-add`/`edit`)

```bash
chezmoi status                         # confirm which files were adopted
chezmoi re-add                         # bulk adopt (skips *.tmpl — see §3)
chezmoi git -- status -sb              # new commit(s) should exist
chezmoi git -- log -1 --oneline
chezmoi git -- push
git rev-list --left-right --count HEAD...@{u}          # expect 0 0
```

If nothing was re-added, there is nothing to commit — do NOT create empty commits. `git status -sb` staying `## master...origin/master` with no push needed is the normal `apply`-only outcome.

**Push 403 (`Permission to <repo> denied to <you>`)** → git's helper is `gh auth git-credential`
(`~/.config/git/config`), and gh resolves the token as env `GH_TOKEN`/`GITHUB_TOKEN` **first**, ahead of
its keyring OAuth token. When the env var holds a fine-grained PAT (`github_pat_…`) scoped to other
repos, the identity matches but the write is denied. Re-run the push with the env var unset (falls back
to the keyring `gho_…` token, scopes incl. `repo`) — no config change needed:

```bash
env -u GITHUB_TOKEN chezmoi git -- push
```

Diagnose with: `git config --list --show-origin | grep -i credential` (expect
`credential.https://github.com.helper=!/usr/bin/gh auth git-credential`) and
`printf 'protocol=https\nhost=github.com\n\n' | env -u GITHUB_TOKEN git credential fill`
(expect `username=coldter`, `password=gho_…`; with the env token it returns the PAT instead).

## 7. Validation (SLO — every run ends here)

```bash
chezmoi verify; echo "verify:$?"       # 0 required
chezmoi status                         # empty required
chezmoi diff 2>&1 | head -n 5          # empty required
git status -sb                         # ## master...origin/master, no markers
git rev-list --left-right --count HEAD...@{u}          # 0 0 required
chezmoi git -- log --oneline -3
```

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `could not open a new TTY` on apply/dry-run | target changed since last write; headless guard | `--dry-run --force` to preview → `apply --force` (whole tree or per-file) |
| `status` still lists entries right after piping `apply --verbose` into `head` | SIGPIPE killed chezmoi mid-apply; later entries never written | redirect apply to a log file (`> /tmp/opencode/apply.log 2>&1; echo exit:$?`), re-run, confirm exit 0 |
| `MM` survives a full `apply --force` | one entry needs per-file pass | `apply --force --verbose <target>` again, then `status` |
| `re-add` ignores a template drift | chezmoi refuses to overwrite templates | `chezmoi edit <target>`, hand-merge, `apply` |
| `openwhispr-binds.lua` / `hyprland.lua` re-drift after an OpenWhispr upgrade | app's writer changed; source no longer mirrors its canonical output (§3.1) | re-derive the app's output from `app.asar` (§3.1), update template/header, `apply --force`; never `re-add` a stale header or restore the portable module require |
| `shell.json` vs `private_shell.json` confusion | `private_` prefix = 0600 target `shell.json` | edit source `private_shell.json`, never assume a missing `shell.json` in source |
| `MM` on a directory (e.g. `.pi/agent`), diff shows only `old mode 40700 / new mode 40755` | directory mode drift. `apply` reports the *state-recorded* mode; `chmod` on the source dir is ignored (probe: source `711` still wanted `755`), and `re-add` ignores all non-file entries | git-tracked fix: `git mv dot_pi/agent dot_pi/private_agent` (target = source mode & ^077 = 0700), `chezmoi apply`, then `status` clears. Portable to fresh clones — plain `chmod` is not |
| `verify` exit 1 | drift remains | `status` + per-file `diff`, return to §3 |
| mise config re-drifts (`  M`/`MM` on `config.toml`) | `mise use`/`mise upgrade`/`mise prune` rewrites the whole tools table, normalizing `npm:<pkg>` specs to registry shortnames | adopt with `re-add` (README §4.5) instead of re-`apply`-ing the long form — see §3 backend note |
| `mise which <tool>` → "is a mise bin however it is not currently active" | tool still installed under `installs/`, but live `config.toml` no longer declares it (mise never drops a resolvable `npm:` key on its own — `mise registry <tool>` errors, so no shortname exists) | `chezmoi diff ~/.config/mise/config.toml`; decide per §3 (adopt removal vs restore declaration) — with `auto_prune = true` an undeclared install is eventually deleted |
| `git push` → `403` / `Permission to <repo> denied to <user>` | git's helper is `gh auth git-credential`, which prefers env `GITHUB_TOKEN` (fine-grained PAT, no write on this repo) over the keyring `gho_…` token that carries `repo` scope | re-run just the push with the env var unset: `env -u GITHUB_TOKEN chezmoi git -- push` — see the §6 auth note |
| `pull --ff-only` refuses | diverged (local commits + upstream) | resolve per §4 conflict flow, or push first if ahead-only |
| Template parse error on apply | `else if` placed after `else` | move new machine block above `{{ else }}` fallback |

## Post-Execution Reflection

1. Did every phase succeed to §7 SLO? If not, fix the section above.
2. Did a flag or output change? Update the command block.
3. Was a workaround needed? Fold it into the skill so the next run doesn't improvise.
4. Did you edit this skill (it is tracked and chezmoi-ignored)? Commit it too (`agents:` prefix) — an uncommitted skill edit breaks the §7 clean-tree SLO.
