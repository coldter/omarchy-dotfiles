-- Learn how to configure Hyprland: https://wiki.hypr.land/Configuring/Start/

-- Omarchy's bootstrap keeps path setup out of this user config.
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")

-- Disable all Omarchy default bindings. Add your own in hypr/bindings.lua.
-- omarchy_default_bindings = false
--
-- Or disable only bindings for Omarchy's preinstalled apps/web apps while
-- keeping core window-manager bindings:
-- omarchy_preinstalled_bindings = false

-- Load Omarchy defaults.
require("default.hypr.omarchy")

-- Put your personal overrides in these files. They're loaded after Omarchy's
-- defaults so package updates can improve the defaults without rewriting your
-- ~/.config/hypr files.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle config flags dynamically.
require("default.hypr.toggles")

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- Always float YouTube Music (Brave PWA) - pinned to current size 1156x786
o.window("^(brave-cinhimbnkkaeohfgghhklpknlkffjgod-Default)$", { float = true, size = "1156 786" })

-- Fix JetBrains Toolbox off-screen on Hyprland/XWayland multi-monitor (same as localsend)
o.window("^(jetbrains-toolbox)$", { float = true, center = true })

-- XWayland apps restore X position after window rules, so force center after open (Hyprland 0.56 needs timer)
hl.on("window.open", function(w)
  if w.class == "jetbrains-toolbox" then
    hl.timer(function()
      hl.dispatch(hl.dsp.window.center({ window = w }))
    end, { timeout = 150, type = "oneshot" })
  end
end)
pcall(require, "hypr.openwhispr-binds")

