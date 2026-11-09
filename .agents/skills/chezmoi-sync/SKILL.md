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

## Codemode

`codemode` is on by default (`defaultTools: ["+codemode"]` in the tracked `~/.pi/agent/settings.json`, source `dot_pi/private_agent/private_settings.json`). If a session lacks it, run the phases as **batched bash with aggregated output** (one call per phase, verbose output redirected to files) — do not fake `tools.*` scripts or spawn a nested `pi --print` agent.

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
- Fresh pull + no `apply` yet is the #1 cause of apparent drift (`chezmoi git -- reflog --date=iso`: a pull newer than the last apply means live is pre-apply, not reverted).

## 2. Drift Check (source vs home)

```bash
chezmoi status                         # one line per drifted file
chezmoi diff 2>&1 | head -n 100        # what `apply` WOULD do to $HOME
chezmoi diff ~/.config/path/file 2>&1  # per-file review
chezmoi verify; echo "verify:$?"       # 0 = clean, 1 = drift remains
```

Status columns (`chezmoi status --help`): col-1 = last-written vs actual (your edits/Omarchy rewrites), col-2 = actual vs target (`apply` effect).

**`chezmoi diff` direction**: `a/` = **destination** (current `$HOME`), `b/` = **target state** (rendered source) — `-` lines are on disk now, `+` lines are what `apply` would write. Confirm on one known file (`chezmoi cat <target>`) before reading a diff backwards.

| Code | Meaning |
| ---- | ------- |
| ` M` | source changed (e.g. just pulled) — `apply` will update target |
| `MM` | both sides changed — `apply` needs review, may need `--force` |

Name decoding: source `private_shell.json` → target `shell.json` (`private_` = 0600, not a name change); `chezmoi source-path <target>` resolves a target to its source file. `*.tmpl` files never render 1:1 — check with `chezmoi cat <target>`.

## 3. Decision Matrix (per file)

| Observation | Action |
| ----------- | ------ |
| Upstream changed source, target stale (` M`, diff matches upstream intent) | `apply` (source wins) |
| You edited target and want to keep it | `chezmoi re-add <target>` (target wins → new source commit → push) |
| Omarchy rewrote a managed file, source version is intentional (e.g. deduped comments) | `apply --force` (source wins; drift will likely return — do NOT loop) |
| Drift is in a `*.tmpl` rendered file (e.g. `monitors.lua`) | NEVER `re-add` (chezmoi refuses templates). `chezmoi edit <target>` the template, then `apply` |
| `MM` on mise `config.toml` | mise's own write — adopt live (`re-add`); backend-explicit adds, dropped declarations, and the shortname/backend probes are README §4.5 |
| `MM` on `.pi/agent/settings.json` / `mcp-adapter.json` | pi owns these — adopt live (`re-add`) when pi wrote real settings; a lone `lastChangelogVersion` bump after a fresh pull → `apply` (source wins); README §4.6 |
| `MM` on `.omp/agent/config.yml` / `.omp/plugins/*` | omp owns these — adopt live (`re-add ~/.omp`); `node_modules`/`bun.lock` stay untracked, rebuilt by `bun install`; README §4.8 |
| `MM` on `.config/Code/User/settings.json` | VS Code UI writes it — adopt live (`re-add`), commit `vscode:` |
| `MM` on `.config/herdr-app/settings.json` | herdr writes it — adopt live (`re-add`), commit `herdr:` |
| `MM` on `hyprland.lua` / `openwhispr-binds.lua` | OpenWhispr's binds writer adds one blank line per rewrite — adopt live (`re-add`), commit `hypr:`. Header/load-line change → re-derive from the app (README §4.7); never `re-add` a stale header |
| `MM` on a **directory** (e.g. `.pi/agent`, `.omp/agent`), mode-only diff | dir mode comes from the source dir **name** (`private_agent`); `chmod` is ignored and `re-add` ignores non-file entries — rename the source dir |
| Unsure | show the per-file `chezmoi diff`, ask user: adopt (`re-add`) or reject (`apply`) |

**Ordering**: when live-only additions need adopting (`re-add`) **and** other entries need `apply`, re-add FIRST — `apply` clears the live-only delta (e.g. mise `gh = "latest"`), so a later re-add has nothing to adopt.

## 4. Pull

```bash
chezmoi git -- pull --ff-only 2>&1     # fast-forward only; aborts on divergence
chezmoi status                         # re-check drift — upstream may add ` M` entries
chezmoi diff 2>&1 | head -n 100
LOG=$(mktemp); chezmoi apply --dry-run --force --verbose > "$LOG" 2>&1; echo "exit:$?"; head -n 40 "$LOG"
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

Commit prefix convention: lowercase (`pkg:`, `mise:`, `pi:`, `omp:`, `vscode:`, `herdr:`, `monitors:`, `hypr:`, `omarchy:`, `docs:`, `agents:`).

## 5. Apply

```bash
# NEVER pipe apply --verbose through head — SIGPIPE kills chezmoi mid-run (see Notes).
LOG=$(mktemp)
chezmoi apply --dry-run --force --verbose > "$LOG" 2>&1; echo "exit:$?"
head -n 40 "$LOG"                                      # must review first
LOG=$(mktemp)
chezmoi apply --force --verbose > "$LOG" 2>&1; echo "exit:$?"  # --force ONLY after diff review
tail -n 60 "$LOG"
chezmoi apply --force --verbose ~/.config/path/file    # per-file retry if one entry sticks
```

Notes:

- Plain `apply`/`--dry-run` aborts with `could not open a new TTY` when a target changed since the last write. Add `--force` to the dry-run, review, then `apply --force`.
- Never pipe `apply --verbose` into `head` — SIGPIPE kills chezmoi mid-run. Redirect to a `mktemp` log, check `exit:$?`, then read it. Same for `--dry-run`.
- A leftover `MM` may need a per-file `apply --force` pass.
- Templates: `chezmoi cat <target>` to verify; `monitors.lua.tmpl` blocks go above `{{ else }}`.
- Hyprland: `hyprctl configerrors` must print nothing.

## 6. Push Path (only when source changed via `re-add`/`edit`)

```bash
chezmoi status                         # confirm which files were adopted
chezmoi re-add                         # bulk adopt (skips *.tmpl — see §3)
chezmoi git -- status -sb              # re-add only dirties the worktree (no autoCommit)
chezmoi git -- add -A && chezmoi git -- commit -m "<prefix>: <what changed>"
chezmoi git -- log -1 --oneline
chezmoi git -- push
git rev-list --left-right --count HEAD...@{u}          # expect 0 0
```

`autoCommit` is NOT set in `chezmoi.toml`, so `re-add`/`edit` never commit — always commit explicitly.
If the worktree is still clean after `re-add`, nothing was adopted: do NOT create empty commits. `git status -sb` staying `## master...origin/master` with no push needed is the normal `apply`-only outcome.

**Push 403 (`Permission to <repo> denied to <you>`)** → git uses `gh auth git-credential`, and gh
prefers env `GH_TOKEN`/`GITHUB_TOKEN` over the keyring. A fine-grained PAT without write scope 403s.
Unset it first:

```bash
env -u GITHUB_TOKEN chezmoi git -- push
```

If the active keyring account is not the repo owner (check `gh auth status`), mint the owner's token
for this push only:

```bash
TOKEN=$(env -u GITHUB_TOKEN gh auth token --user coldter)   # never echo $TOKEN
env -u GITHUB_TOKEN GH_TOKEN="$TOKEN" chezmoi git -- push
unset TOKEN
```

## 7. Validation (SLO — every run ends here)

```bash
chezmoi verify; echo "verify:$?"       # 0 required
chezmoi status                         # empty required
chezmoi diff 2>&1 | head -n 5          # empty required
git status -sb                         # ## master...origin/master, no markers
git rev-list --left-right --count HEAD...@{u}          # 0 0 required
chezmoi git -- log --oneline -3
# secrets sanity (README §7) — filenames only, so a hit does not print the secret
git grep -l -I -E 'sk-[A-Za-z0-9_-]{20,}|gh[oprsu]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY' -- . | head
git check-ignore -q --no-index dot_pi/private_agent/private_auth.json &&
  git check-ignore -q --no-index dot_omp/private_agent/private_agent.db && echo "secret-guard:ok"
```

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| App-owned `MM` looks like a revert of pulled commits (e.g. pi `settings.json`) | pull landed after the last apply; the app only bumped `lastChangelogVersion` | `apply` (source wins); confirm via `chezmoi git -- reflog --date=iso` + `chezmoi state dump` (`contentsSHA256`) |
| `openwhispr-binds.lua` / `hyprland.lua` re-drift | binds writer adds one blank line per rewrite; header/load-line change means the app writer changed | blank-line-only → `re-add` + commit `hypr:`; otherwise re-derive (README §4.7), `apply --force` |
| A tracked file needs `0600` but its source name is plain | mode comes from the source name (`private_` → 0600); app writers preserve the existing mode | `git mv <dir>/<file> <dir>/private_<file>`, then `apply` |
| Credential store would be staged | `.gitignore` pattern missing | `git check-ignore -v <source-file>`, add the pattern; rotate first if already pushed |

## Post-Execution Reflection

1. Fix any phase that failed §7.
2. Update commands/flags that drifted.
3. Fold in real workarounds; commit skill edits (`agents:`) — it is tracked and chezmoi-ignored.
