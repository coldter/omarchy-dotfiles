#!/bin/bash
# run_once_after_10-packages.sh
# Installs YOUR packages (on top of Omarchy's defaults) from the tracked lists:
#   packages/manual-packages.txt  → official Arch repos  (omarchy pkg add)
#   packages/aur-packages.txt     → AUR                  (omarchy pkg aur add)
#
# Runs once per content-hash — i.e. on new-machine setup AND any time you edit
# this script (the next `chezmoi apply` re-runs it; harmless: both omarchy
# commands skip packages that are already installed).
#
# NOTE: `omarchy pkg add` shells out to sudo pacman — run `chezmoi apply` in a
# real terminal so the sudo password prompt can be answered.
set -u

# chezmoi sets CHEZMOI_SOURCE_DIR when it runs this script during `apply`.
# Calling `chezmoi source-path` from inside apply would deadlock on the state
# lock, so it is only used as a fallback when running this script by hand.
SRC="${CHEZMOI_SOURCE_DIR:-$(chezmoi source-path 2>/dev/null)}"
if [ -z "$SRC" ]; then
  echo "!! cannot locate the chezmoi source dir — cd into ~/.local/share/chezmoi and run this script manually"
  exit 0  # bootstrap scripts must never break `chezmoi apply`
fi

install_list() {  # $1 = path to package list, $2 = omarchy subcommand
  local list="$1" cmd="$2" pkgs p
  [ -s "$list" ] || return 0
  pkgs=$(grep -vE '^[[:space:]]*(#|$)' "$list")
  [ -n "$pkgs" ] || return 0

  echo ">> Installing via 'omarchy $cmd' (present packages are skipped)…"
  # intentional word splitting: one arg per non-comment line
  # shellcheck disable=SC2086
  if omarchy $cmd $pkgs; then
    return 0
  fi

  # A batch aborts entirely if ANY single name is unresolvable (renamed
  # package, repo outage) — retry one-by-one so one bad name can't starve
  # the rest of the list.
  echo "!! batch failed — retrying one-by-one"
  for p in $pkgs; do
    omarchy $cmd "$p" || echo "!! failed: $p — rerun later: omarchy $cmd $p"
  done
}

install_list "$SRC/packages/manual-packages.txt" "pkg add"
install_list "$SRC/packages/aur-packages.txt" "pkg aur add"
