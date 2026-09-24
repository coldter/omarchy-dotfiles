-- OpenWhispr keybinds (managed automatically)
-- If you delete this file, also remove the matching load line from your Hyprland config.
-- Loaded from hyprland.lua via pcall(require, …) — the pcall also hides load
-- errors, so after editing this file validate with `hyprctl configerrors`.
hl.bind("SUPER + F1", hl.dsp.exec_cmd("dbus-send --session --type=method_call --dest=com.openwhispr.App /com/openwhispr/App com.openwhispr.App.Toggle"))
