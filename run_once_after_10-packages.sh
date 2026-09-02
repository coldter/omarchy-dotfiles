#!/bin/bash
# run_once_after_10-packages.sh
# Installs YOUR packages (on top of Omarchy's defaults) from the tracked lists.
#   packages/manual-packages.txt  → repo packages   (omarchy pkg add)
#   packages/aur-packages.txt     → AUR packages    (omarchy pkg aur add)
#
# Runs once per content-hash on `chezmoi apply` (i.e. on new-machine setup).
# Safe to re-run manually anytime: both omarchy commands skip what's installed.
set -u

SRC="$(chezmoi source-path)"

if [ -s "$SRC/packages/manual-packages.txt" ]; then
  # intentional word splitting: one arg per package line
  pkgs=$(grep -vE '^[[:space:]]*(#|$)' "$SRC/packages/manual-packages.txt")
  if [ -n "$pkgs" ]; then
    echo ">> Installing repo packages (skipping present ones)…"
    # shellcheck disable=SC2086
    omarchy pkg add $pkgs || echo "!! some repo packages failed — rerun later: omarchy pkg add"
  fi
fi

if [ -s "$SRC/packages/aur-packages.txt" ]; then
  aur=$(grep -vE '^[[:space:]]*(#|$)' "$SRC/packages/aur-packages.txt")
  if [ -n "$aur" ]; then
    echo ">> Installing AUR packages (skipping present ones)…"
    # shellcheck disable=SC2086
    omarchy pkg aur add $aur || echo "!! some AUR packages failed — rerun later: omarchy pkg aur add"
  fi
fi
