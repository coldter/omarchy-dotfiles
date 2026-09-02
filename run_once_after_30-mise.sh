#!/bin/bash
# run_once_after_30-mise.sh
# Installs the tools declared in the tracked ~/.config/mise/config.toml
# (chezmoi itself is one of those tools — it is installed through mise).
#
# mise ships with Omarchy (package: mise-bin), so this normally finds mise
# already present. Runs once per content-hash; `mise install` is a no-op when
# everything is current.
set -u

if ! command -v mise >/dev/null 2>&1; then
  echo "!! mise not found — install it first: omarchy pkg add mise-bin (or: curl https://mise.run | sh)"
  exit 0  # bootstrap scripts must never break `chezmoi apply`
fi

echo ">> Installing mise tools from ~/.config/mise/config.toml"
mise install || echo "!! mise install failed — rerun later: mise install"
