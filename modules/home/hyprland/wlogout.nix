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
  inherit (h) plainLogout uwsmLogout;

  # wlogout is launched by waybar's power button, so its actions run inside
  # waybar.service's cgroup. Both logout scripts begin by stopping
  # graphical-session.target, which stops waybar — and systemd kills every
  # process in waybar's cgroup, the running logout script included, before it
  # reaches the compositor-stop line. Result: bar and wallpaper gone, session
  # still up (seen on oceaneering-laptop 2026-10-05; the $mod+Shift+E bind is
  # unaffected because Hyprland, not waybar, is its parent). So the menu hands
  # the script to its own transient user unit and returns at once. Bare
  # `systemd-run` (PATH) for the same reason the scripts use bare `systemctl`:
  # it must match the user manager that owns the session. PATH and the
  # Hyprland instance are passed through because a transient unit starts from
  # the manager's environment, not the caller's.
  detached = script:
    pkgs.writeShellScript "logout-detached" ''
      exec systemd-run --user --collect --quiet \
        --unit="session-logout-$$" \
        --setenv=PATH="$PATH" \
        --setenv=HYPRLAND_INSTANCE_SIGNATURE="''${HYPRLAND_INSTANCE_SIGNATURE:-}" \
        ${script}
    '';
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
            # Both paths stop graphical-session.target first, so the session
            # services get an ordered SIGTERM while the display is still up;
            # only the way the compositor itself is stopped differs (uwsm stop
            # vs. dispatch exit). See uwsmLogout / plainLogout.
            # Run detached from waybar's cgroup — see `detached` above.
            action =
              if cfg.uwsm.enable
              then "${detached uwsmLogout}"
              else "${detached plainLogout}";
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
