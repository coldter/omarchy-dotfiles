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

`codemode` is on by default (`defaultTools: ["+codemode"]` in the tracked `~/.pi/agent/settings.json`, README §4.6). If a session lacks it, run the phases as **batched bash with aggregated output** (one call per phase, verbose output redirected to files) — do not fake `tools.*` scripts or spawn a nested `pi --print` agent.

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

**`chezmoi diff` direction**: `a/` = **live target** (`$HOME`), `b/` = **source** (desired) — `-` lines are what is on disk now, `+` lines are what source/`apply` would write. Confirm on one known file (`chezmoi cat <target>`) before reading a diff backwards.

| Code | Meaning |
| ---- | ------- |
| ` M` | source changed (e.g. just pulled) — `apply` will update target |
| `MM` | both sides changed — `apply` needs review, may need `--force` |
| `MM` on `hyprland.lua` + `openwhispr-binds.lua` | OpenWhispr rewrote its **app-owned** files; source mirrors the app's output byte-for-byte, so a rewrite is a no-op. Recurring drift after an app upgrade → re-derive per README §4.7 |

Name decoding: source `private_shell.json` → target `shell.json` (`private_` = 0600, not a name change); `chezmoi source-path <target>` resolves a target to its source file. `*.tmpl` files never render 1:1 — check with `chezmoi cat <target>`.

## 3. Decision Matrix (per file)

| Observation | Action |
| ----------- | ------ |
| Upstream changed source, target stale (` M`, diff matches upstream intent) | `apply` (source wins) |
| You edited target and want to keep it | `chezmoi re-add <target>` (target wins → new source commit → push) |
| Omarchy rewrote a managed file, source version is intentional (e.g. deduped comments) | `apply --force` (source wins; drift will likely return — do NOT loop) |
| Drift is in a `*.tmpl` rendered file (e.g. `monitors.lua`) | NEVER `re-add` (chezmoi refuses templates). `chezmoi edit <target>` the template, then `apply` |
| `MM` on mise `config.toml` | mise's own write — adopt live (`re-add`); backend-explicit adds, dropped declarations, and the shortname/backend probes are README §4.5 |
| `MM` on `.pi/agent/settings.json` / `mcp-adapter.json` | pi owns these — adopt live (`re-add`) ONLY when pi wrote real settings (model/theme/packages). If the live delta is just the `lastChangelogVersion` upgrade bump and a fresh pull hasn't been applied, `apply` (source wins) — `re-add` would revert pulled config; README §4.6 |
| `MM` on `.omp/agent/config.yml` / `.omp/plugins/*` | omp owns these — adopt live (`re-add ~/.omp`); `node_modules`/`bun.lock` stay untracked, rebuilt by `bun install`; README §4.8 |
| `MM` on `.config/Code/User/settings.json` | VS Code UI writes it — adopt live (`re-add`), commit `vscode:` |
| `MM` on `hyprland.lua` / `openwhispr-binds.lua` | OpenWhispr owns these — mirrored byte-for-byte, so its rewrite is a no-op; never `re-add` a stale header; re-derive per README §4.7 |
| `MM` on a **directory** (e.g. `.pi/agent`, `.omp/agent`), mode-only diff | dir-mode drift: target mode comes from the source dir **name** (`private_agent`), not `chmod` (ignored) and not `re-add` (skips dirs) |
| Unsure | show the per-file `chezmoi diff`, ask user: adopt (`re-add`) or reject (`apply`) |

**Ordering**: when live-only additions need adopting (`re-add`) **and** other entries need `apply`, re-add FIRST — `apply` clears the live-only delta (e.g. mise `gh = "latest"`), so a later re-add has nothing to adopt.

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
# secrets sanity (README §7) — expect no matches, then guard:ok
git grep -I -n -E 'sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY' -- . | head
git check-ignore -q --no-index dot_pi/private_agent/private_auth.json && echo "secret-guard:ok"
```

## Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `could not open a new TTY` on apply/dry-run | target changed since last write; headless guard | `--dry-run --force` to preview → `apply --force` (whole tree or per-file) |
| `status` still lists entries right after piping `apply --verbose` into `head` | SIGPIPE killed chezmoi mid-apply; later entries never written | redirect apply to a log file (`> /tmp/opencode/apply.log 2>&1; echo exit:$?`), re-run, confirm exit 0 |
| `MM` survives a full `apply --force` | one entry needs per-file pass | `apply --force --verbose <target>` again, then `status` |
| `re-add` ignores a template drift | chezmoi refuses to overwrite templates | `chezmoi edit <target>`, hand-merge, `apply` |
| Both a live-only addition (needs `re-add`) and source changes (need `apply`) are pending | `apply` deletes the live-only addition (e.g. mise `gh = "latest"`); a later `re-add` adopts nothing | `chezmoi re-add <file>` FIRST, then `apply --force` for the rest |
| App-owned `MM` looks like a revert of pulled commits (e.g. pi `settings.json`) | pull landed after the last apply; live was never reverted — the app only bumped its own version (`lastChangelogVersion`) | `apply` (source wins); confirm via `chezmoi git -- reflog --date=iso` + `chezmoi state dump` (entry `contentsSHA256` == `git show <pre-pull-HEAD>:<source>`) |
| `openwhispr-binds.lua` / `hyprland.lua` re-drift after an OpenWhispr upgrade | app's writer changed; source no longer mirrors its canonical output | re-derive the app's output (README §4.7), update template/header, `apply --force`; never `re-add` a stale header |
| A tracked file needs `0600` but its source name is plain | target file mode comes from the source **name** on a fresh clone (plain → `0644`, `private_` → `0600`); pi's and the adapter's writers both preserve the existing mode | `git mv <dir>/<file> <dir>/private_<file>`, then `apply` (`chezmoi add` encodes the mode automatically). Probe an app's new-file mode empirically (`stat -c %a`) rather than reading its bundle |
| `verify` exit 1 | drift remains | `status` + per-file `diff`, return to §3 |
| `git push` → `403` / `Permission to <repo> denied to <user>` | git's helper is `gh auth git-credential`, which prefers env `GITHUB_TOKEN` (fine-grained PAT, no write on this repo) over the keyring `gho_…` token that carries `repo` scope | re-run just the push with the env var unset: `env -u GITHUB_TOKEN chezmoi git -- push` — see the §6 auth note |
| Credential store would be staged (`chezmoi add ~/.pi/agent/auth.json` + `git add -A`) | root `.gitignore` mirrors README §7; if it still stages, the pattern is missing | `git check-ignore -v <source-file>`, add the pattern; if a secret was already pushed, rotate it first, then rewrite history — deleting the file is not enough |
| `pull --ff-only` refuses | diverged (local commits + upstream) | resolve per §4 conflict flow, or push first if ahead-only |
| Template parse error on apply | `else if` placed after `else` | move new machine block above `{{ else }}` fallback |

## Post-Execution Reflection

1. Did every phase succeed to §7 SLO? If not, fix the section above.
2. Did a flag or output change? Update the command block.
3. Was a workaround needed? Fold it into the skill so the next run doesn't improvise.
4. Did you edit this skill (it is tracked and chezmoi-ignored)? Commit it too (`agents:` prefix) — an uncommitted skill edit breaks the §7 clean-tree SLO.
