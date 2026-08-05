# Session plumbing — kitty, the walker/elephant launcher stack, mako, the
# swayosd/swaybg/darkman session units, and the networkmanager_dmenu config.
# Split out of hyprland.nix; shared helpers come from ./lib.nix. (The shared
# home.packages list lives in the entry module — see the comment there.)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hyprland-desktop;
  h = import ./lib.nix {inherit config lib pkgs;};
  inherit (h) nmDmenuLauncher sessionTarget walkerLayout walkerMochaStyle;
in {
  config = lib.mkIf cfg.enable {
    # networkmanager_dmenu (waybar network left-click): pick/join networks
    # through walker, and hand passphrase entry to a real masked pinentry rather
    # than typing the key into the visible picker. It uses one dmenu_command for
    # both the SSID list and the passphrase, so it can't obscure the latter for a
    # launcher it doesn't recognise — pinentry-qt gives a proper hidden-input
    # dialog (Qt is already in the closure via Plasma and needs no secret-service
    # prompter under Hyprland). Talks to NetworkManager, so it respects the iwd
    # backend just like nmtui.
    xdg.configFile."networkmanager-dmenu/config.ini".text = ''
      [dmenu]
      dmenu_command = ${nmDmenuLauncher}
      pinentry = ${pkgs.pinentry-qt}/bin/pinentry-qt
      wifi_chars = ▂▄▆█
    '';

    programs = {
      # Kitty declaratively, so catppuccin/nix's kitty module auto-enables and
      # themes it (Mocha). Translucent so the wallpaper bleeds through.
      kitty = {
        enable = lib.mkDefault true;
        settings = {
          background_opacity = "0.90";
          dynamic_background_opacity = "yes";
          background_blur = 5;
          allow_remote_control = "yes";
        };
      };
    };

    services = {
      # walker (the app launcher bound to $mod+Space), via the home-manager
      # module; the systemd service makes $mod+Space instant (resident
      # GApplication). walker 2.x's data providers (apps, runner, calc, …) live in
      # the separate `elephant` daemon (services.elephant) — without it the
      # launcher opens but lists nothing.
      walker = {
        enable = lib.mkDefault true;
        systemd.enable = lib.mkDefault true;
        theme = {
          name = "mocha";
          layout = walkerLayout;
          style = walkerMochaStyle;
        };
      };

      elephant.enable = lib.mkDefault true;

      # mako notification daemon. services.mako writes the config + lets
      # catppuccin theme it; it emits no systemd unit on this HM rev, so add one
      # scoped to hyprland-session.target. Type=simple: mako claims
      # org.freedesktop.Notifications within ms of start, preempting a blocking
      # backend (e.g. KDE's, which hangs waiting for a Plasma session).
      mako = lib.mkIf cfg.mako.enable {
        enable = true;
        settings = cfg.mako.settings;
      };
    };

    systemd.user.services = {
      # Scope walker + elephant to the Hyprland session (the module defaults to
      # graphical-session.target, which the GNOME/Plasma sessions also reach).
      walker = {
        Install.WantedBy = lib.mkForce [sessionTarget];
        # Order walker AFTER the session target. Under uwsm, WAYLAND_DISPLAY only
        # lands in the user env once graphical-session.target is reached (uwsm
        # finalizes the env there). Without this After, walker.service starts too
        # early, dies with "Failed to open display", and crash-loops into
        # StartLimitBurst — after which it's dead and can launch nothing. waybar
        # already orders itself after the target, which is why it was unaffected.
        # PartOf so walker also stops cleanly on logout.
        Unit = {
          After = [sessionTarget];
          PartOf = [sessionTarget];
        };
      };
      elephant = {
        Install.WantedBy = lib.mkForce [sessionTarget];
        # elephant is what actually spawns the apps walker selects, so it must
        # also start AFTER the session target — otherwise it (and every app it
        # launches) inherits an env without WAYLAND_DISPLAY and the launch
        # silently fails to open the display. (Same fix as walker above.)
        Unit = {
          After = [sessionTarget];
          PartOf = [sessionTarget];
        };
      };

      # darkman (if enabled) BindsTo graphical-session.target, and it is
      # D-Bus/XDG-portal activated — so after logout something pokes its portal,
      # darkman restarts, and BindsTo (which implies Requires) drags
      # graphical-session.target back up. Under uwsm that makes the NEXT login
      # abort with "a compositor or graphical-session* target is already active"
      # (black screen). As long as ANY user session lingers (an open SSH session,
      # a detached process, or loginctl linger) the user manager stays up and this
      # keeps recurring. Drop the BindsTo — keep PartOf so darkman still stops with
      # the session — so its activation can no longer resurrect the target, and
      # uwsm re-login stays clean regardless of lingering sessions.
      darkman.Unit.BindsTo =
        lib.mkIf (cfg.uwsm.enable && config.services.darkman.enable) (lib.mkForce []);

      # swaybg paints the desktop background: one random image from the pool on
      # every output (swaybg's implicit `*` match also covers monitors that appear
      # later, e.g. on docking). This was wpaperd, then swww/awww — both drive a
      # per-output GL buffer pool this Hyprland/Intel stack mishandles (wpaperd
      # segfaulted on undock; awww mapped its surface but never committed a buffer,
      # so the wallpaper stayed blank). swaybg attaches a single shm/layer-shell
      # buffer with no GL draw loop and no per-output state, so it rides output
      # changes. It has no in-place image swap, so rotation launches a fresh swaybg
      # with the next random pick, lets it map, then kills the old one (overlap, so
      # no black flash) — a hard cut every 30 minutes rather than a fade.
      swaybg = lib.mkIf (cfg.wallpaperPath != null) {
        Unit = {
          Description = "swaybg desktop wallpaper (random from the pool, rotated every 30m)";
          PartOf = [sessionTarget];
          After = [sessionTarget];
        };
        Service = {
          ExecStart = pkgs.writeShellScript "swaybg-rotate" ''
            pid=
            # Kill the current swaybg when we exit; and on TERM/INT actually
            # *exit*. Without the explicit exit the trap fired but the `while`
            # loop just relaunched swaybg and kept running, so the service sat in
            # stop-sigterm for the full 90s TimeoutStopSec. That stalled every
            # Hyprland login: the env-import exec-once does a synchronous
            # `systemctl --user stop hyprland-session.target && ... start ...`,
            # and the stop blocked 90s on swaybg before waybar (everything
            # PartOf the target) came back — a ~90s blank login.
            trap '[ -n "$pid" ] && kill "$pid" 2>/dev/null' EXIT
            trap 'exit 0' TERM INT
            while :; do
              img=$(${pkgs.findutils}/bin/find ${cfg.wallpaperPath}/ -type f \
                \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
                | ${pkgs.coreutils}/bin/shuf -n1)
              if [ -n "$img" ]; then
                ${pkgs.swaybg}/bin/swaybg -i "$img" -m fill &
                new=$!
                ${pkgs.coreutils}/bin/sleep 1
                [ -n "$pid" ] && kill "$pid" 2>/dev/null
                pid=$new
              fi
              ${pkgs.coreutils}/bin/sleep 1800
            done
          '';
          Restart = "on-failure";
          # Backstop: if the wrapper ever can't exit in time, never block a
          # session-target stop for systemd's default 90s (the wallpaper has no
          # state worth a graceful shutdown).
          TimeoutStopSec = "5s";
        };
        Install.WantedBy = [sessionTarget];
      };

      # swayosd OSD server — paints the workspace-switch popups (workspaceOsd) and,
      # where mediaKeyOsd is on, the volume/brightness popups. cairo/layer-shell,
      # no GL. Hand-rolled unit (no home-manager services.swayosd), target-scoped
      # like the others.
      swayosd = {
        Unit = {
          Description = "swayosd OSD server";
          PartOf = [sessionTarget];
          After = [sessionTarget];
        };
        Service = {
          ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
          Restart = "on-failure";
        };
        Install.WantedBy = [sessionTarget];
      };

      mako = lib.mkIf cfg.mako.enable {
        Unit = {
          Description = "mako notification daemon";
          PartOf = [sessionTarget];
          After = [sessionTarget];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.mako}/bin/mako";
          ExecReload = "${pkgs.mako}/bin/makoctl reload";
          Restart = "on-failure";
        };
        Install.WantedBy = [sessionTarget];
      };
    };
  };
}
