-- OpenWhispr keybinds (managed automatically)
-- Loaded from hyprland.lua via pcall(require, …) — the pcall also hides load
-- errors, so after editing this file validate with `hyprctl configerrors`.
-- If you delete this file, also remove the matching require line from hyprland.lua.
hl.bind("SUPER + F1", hl.dsp.exec_cmd("dbus-send --session --type=method_call --dest=com.openwhispr.App /com/openwhispr/App com.openwhispr.App.Toggle"))
