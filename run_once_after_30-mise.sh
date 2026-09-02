#!/bin/bash
# run_once_after_30-mise.sh
# Installs every tool pinned in the tracked ~/.config/mise/config.toml
# (chezmoi itself is one of those tools — see mise config).
# Assumes mise is installed. On a fresh Omarchy machine:
#   omarchy pkg add mise      (or: curl https://mise.run | sh)
set -u

if ! command -v mise >/dev/null 2>&1; then
  echo "!! mise not found — install it first: omarchy pkg add mise"
  exit 0  # bootstrap scripts must never break `chezmoi apply`
fi

echo ">> Installing mise tools from ~/.config/mise/config.toml"
mise install || echo "!! mise install failed — rerun later: mise install"
