# wlogout — the power menu behind waybar's power button. Split out of
# hyprland.nix; shared helpers come from ./lib.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hyprland-desktop;
  h = import ./lib.nix {inherit config lib pkgs;};
  inherit (h) hyprctl uwsmLogout;
in {
  config = lib.mkIf cfg.enable {
    programs = {
      # Power menu (waybar power button). The nixpkgs wlogout package ships icons
      # but NO default layout, so a bare `wlogout` opens with zero buttons —
      # provide an explicit layout + a Catppuccin-Mocha style pointing at the
      # package's bundled icons.
      wlogout = lib.mkIf cfg.wlogout.enable {
        enable = true;
        layout = [
          {
            label = "lock";
            action = "loginctl lock-session";
            text = "Lock";
            keybind = "l";
          }
          {
            label = "logout";
            # uwsm: stop graphical-session.target (graceful) then the compositor —
            # see uwsmLogout. Non-uwsm: plain dispatch-exit.
            action =
              if cfg.uwsm.enable
              then "${uwsmLogout}"
              else "${hyprctl} dispatch exit";
            text = "Logout";
            keybind = "e";
          }
          {
            label = "suspend";
            action = "systemctl suspend";
            text = "Suspend";
            keybind = "s";
          }
          {
            label = "reboot";
            action = "systemctl reboot";
            text = "Reboot";
            keybind = "r";
          }
          {
            label = "shutdown";
            action = "systemctl poweroff";
            text = "Shutdown";
            keybind = "p";
          }
        ];
        style = ''
          * {
            background-image: none;
            box-shadow: none;
            font-family: "Inter", sans-serif;
            font-size: 16px;
          }
          window {
            background-color: rgba(30, 30, 46, 0.9); /* Mocha base */
          }
          button {
            color: #cdd6f4; /* text */
            background-color: #1e1e2e; /* base */
            border: 2px solid #313244; /* surface0 */
            border-radius: 12px;
            margin: 10px;
            background-repeat: no-repeat;
            background-position: center;
            background-size: 25%;
          }
          button:focus,
          button:hover {
            background-color: #313244; /* surface0 */
            border-color: #cba6f7; /* mauve */
            color: #cba6f7;
          }
          #lock { background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/lock.png")); }
          #logout { background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/logout.png")); }
          #suspend { background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/suspend.png")); }
          #reboot { background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/reboot.png")); }
          #shutdown { background-image: image(url("${pkgs.wlogout}/share/wlogout/icons/shutdown.png")); }
        '';
      };
    };
  };
}
