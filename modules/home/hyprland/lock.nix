# programs.hyprlock — the shared lock-screen appearance. Split out of the host
# files (both hosts carried a byte-identical settings attrset); shared helpers
# live in ./lib.nix, which this concern happens not to need.
#
# Only the LOOK is shared. Everything about *when* and *how* the screen locks
# stays per-host: services.hypridle's listeners and lock_cmd diverge too much to
# share usefully (one host suspends on battery and dims a keyboard backlight,
# the other wraps every lock command in nixGL and re-arms the locker after
# resume), so hypridle is deliberately left in the host files.
#
# The colors are Catppuccin palette variables ($base, $surface1, $surface2,
# $text) sourced by catppuccin/nix's hyprlock module, which contributes
# settings.source alongside this. A consumer that enables the lock screen
# without that module gets unset variables — set `lock.enable = false` and
# configure programs.hyprlock yourself in that case.
#
# Every value is mkDefault at the leaf, so a host can override one field (or
# add `package`, `position`, extra background layers, …) with a plain
# assignment — no mkForce needed.
{
  config,
  lib,
  ...
}: let
  cfg = config.hyprland-desktop;
in {
  config = lib.mkIf cfg.enable {
    programs.hyprlock = lib.mkIf cfg.lock.enable {
      enable = true;
      settings = {
        general = {
          hide_cursor = lib.mkDefault true;
          grace = lib.mkDefault 2;
        };
        background = lib.mkDefault [{color = "$base";}];
        input-field = lib.mkDefault [
          {
            size = "240, 50";
            outline_thickness = 2;
            dots_size = 0.25;
            dots_spacing = 0.3;
            outer_color = "$surface2";
            inner_color = "$surface1";
            font_color = "$text";
            placeholder_text = "<i>Password...</i>";
          }
        ];
      };
    };
  };
}
