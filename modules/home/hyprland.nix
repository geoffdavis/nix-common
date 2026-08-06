# Shared Hyprland desktop (home-manager). The ~identical core of the per-host
# Hyprland configs — helper scripts, kitty/waybar/walker/wlogout, the
# swayosd/swaybg/elephant services, the dynamic-workspace model + switch OSD,
# and the binds/gestures/input/overview — lifted out of the host files so the
# two hosts can't silently drift (they had: birdrock missing swayosd, divergent
# workspace models, a stale waybar). Host-specific glue (monitor layouts, nixGL,
# Apple-T2 backlight/clamshell, portals, PAM, etc.) stays in the host
# file; differences that ARE shared-but-parameterised become options below.
#
# Consumed via nix-common.homeModules.hyprland; enable + configure with
#   hyprland-desktop = { enable = true; volumeBackend = "pactl"; ... };
# The host still sets wayland.windowManager.hyprland.settings.monitor (and any
# other host-only settings) directly — those merge with what this module sets.
#
# The implementation is split by concern into ./hyprland/ (imported below);
# this entry file keeps the whole hyprland-desktop.* option namespace so the
# module's API stays in one obvious place:
#   hyprland/lib.nix     shared helper scripts + derivations (NOT a module)
#   hyprland/waybar.nix  programs.waybar (modules + CSS)
#   hyprland/wlogout.nix programs.wlogout (power menu)
#   hyprland/session.nix kitty, walker/elephant/mako, session units
#   hyprland/binds.nix   wayland.windowManager.hyprland (settings + binds)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hyprland-desktop;
  h = import ./hyprland/lib.nix {inherit config lib pkgs;};
  inherit (h) sessionTarget waybarRelayoutScript;
in {
  imports = [
    ./hyprland/binds.nix
    ./hyprland/session.nix
    ./hyprland/waybar.nix
    ./hyprland/wlogout.nix
  ];

  options.hyprland-desktop = {
    enable = lib.mkEnableOption "shared Hyprland desktop (waybar, walker, binds, dynamic workspaces, switch OSD)";

    volumeBackend = lib.mkOption {
      type = lib.types.enum ["pactl" "wpctl"];
      default = "wpctl";
      description = "Audio control backend for the volume keys + waybar: pactl (PulseAudio) or wpctl (WirePlumber/PipeWire).";
    };

    glWrap = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/nix/store/…/bin/nixGLIntel";
      description = ''
        Command prefix wrapping GL apps launched from systemd-user services
        (waybar on-click TUIs), which start without the compositor's
        leaked nixGL discovery vars. Empty on NixOS; a nixGL path on non-NixOS.
      '';
    };

    mediaKeyOsd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Show a swayosd popup on the volume/brightness media keys (in addition to the always-on workspace-switch OSD).";
    };

    wallpaperPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Directory of wallpapers for swaybg (one random image on every output, rotated every 30m). Null disables the managed swaybg service.";
    };

    onePasswordQuickAccessCmd = lib.mkOption {
      type = lib.types.str;
      default = "1password --quick-access";
      description = "Command for the $mod+Shift+Space 1Password Quick Access bind (prefix with `env -u LD_LIBRARY_PATH` on nixGL hosts).";
    };

    cliphist.enable =
      lib.mkEnableOption "cliphist clipboard history ($mod+V picker + sensitive-copy-guarded watchers)";

    udiskie.enable =
      lib.mkEnableOption "udiskie USB automount + tray (exec-once)";

    playerctlMediaKeys =
      lib.mkEnableOption "MPRIS media-transport keys (play/pause/next/prev) via playerctl";

    wlogout.enable =
      lib.mkEnableOption "the wlogout power menu (layout + Catppuccin Mocha style)" // {default = true;};

    uwsm.enable =
      lib.mkEnableOption "uwsm-managed Hyprland session integration (Universal Wayland Session Manager). uwsm owns the session, so this turns OFF home-manager's own session integration (wayland.windowManager.hyprland.systemd.enable) and binds the desktop's systemd user services to the stock graphical-session.target that uwsm brings up (see hyprland-desktop.sessionTarget), and makes logout run the built-in `uwsm stop -r`. Because that target is shared with every other desktop session on the host, the session services also gain an XDG-autostart ExecCondition so they stay out of a GNOME/Plasma login. uwsm and HM's session integration cannot coexist — both manage graphical-session.target and uwsm refuses to start if it is already active. Pair with programs.hyprland.withUWSM at the system level; the Hyprland package's own \"Hyprland (uwsm-managed)\" session entry is used (no custom waylandCompositors needed)";

    sessionTarget = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = sessionTarget;
      description = "Read-only: the systemd user target host-specific session services should bind to (PartOf/After/WantedBy). graphical-session.target under uwsm (uwsm owns it), else home-manager's hyprland-session.target. Use this from host session services so they attach to whichever target is actually started.";
    };

    polkitAgent.enable =
      lib.mkEnableOption "the hyprpolkitagent GUI polkit auth agent (package + exec-once)" // {default = true;};

    bluetooth.enable =
      lib.mkEnableOption "the waybar bluetooth module + blueman (manager on-click + the applet agent in exec-once)" // {default = true;};

    effects.enable =
      lib.mkEnableOption "window effects — animations, rounded corners, blur behind translucent windows, drop shadows. Default on; opt out per host (e.g. a weak iGPU that chugs) with `effects.enable = false`, which also turns blur off for performance" // {default = true;};

    # Hardware gates. Both default to on — the pre-split behavior — so hosts
    # without the hardware opt out explicitly.
    g502.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Logitech G502 pieces: the live profile/DPI waybar module (custom/mouse) and its CSS, the piper onboard-profile GUI, and the thumb-button workspace binds.";
    };

    laptop.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Laptop-only waybar modules: battery and backlight (their modules-right entries and config blocks).";
    };

    onePasswordTray = {
      enable =
        lib.mkEnableOption "the 1Password tray launcher (waits for waybar's StatusNotifier watcher before `1password --silent`, so the tray icon registers)";
      stripGlEnv = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Strip the leaked nixGL GL-discovery env before launching 1Password (needed when the compositor is nixGL-wrapped and 1Password is a system Electron app).";
      };
    };

    mako = {
      enable =
        lib.mkEnableOption "the mako notification daemon (Hyprland ships none; mako claims org.freedesktop.Notifications so apps don't hang on D-Bus activation). services.mako writes the config + catppuccin themes it; the module adds a hyprland-session.target unit since services.mako emits none on this HM rev";
      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        example = {
          anchor = "top-right";
          default-timeout = 6000;
        };
        description = "Passed to services.mako.settings (writes ~/.config/mako/config). Empty = mako defaults.";
      };
    };

    waybarRelayout = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = ''
        Read-only: path to a script that recreates waybar's layer-shell surfaces
        on the current outputs via SIGUSR1 hide+show (NOT `systemctl restart`,
        which tears down the StatusNotifier watcher and orphans tray icons).
        Reference it from host-specific monitor-change handlers (lid binds,
        clamshell services).
      '';
    };

    extraExecOnce = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Host-specific exec-once entries appended to the shared set.";
    };
    extraBind = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Host-specific `bind` entries appended to the shared set.";
    };
    extraBindel = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Host-specific `bindel` (repeating, locked) entries appended to the shared set.";
    };
    extraBindl = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Host-specific `bindl` (locked) entries appended to the shared set.";
    };
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Host-specific raw hyprland.conf appended after the shared extraConfig (windowrules etc.).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Read-only handle to the waybar relayout helper, for host monitor-change
    # handlers (laptop lid binds, birdrock clamshell settle).
    hyprland-desktop.waybarRelayout = "${waybarRelayoutScript}";

    # home.packages stays in THIS entry module, not session.nix: the module
    # system collects definitions in module order, and a list definition moved
    # into an imported sub-module lands at a different position among the
    # other modules' home.packages contributions — which reorders the
    # home-manager-path buildEnv inputs and changes every downstream drv.
    # Keeping it here preserves the pre-split order exactly (verified by
    # consumer drvPath equality).
    home.packages = with pkgs;
      [
        grim # screenshots
        slurp # region select
        satty # crop/annotate editor for screenshots
        wl-clipboard # clipboard
        brightnessctl # backlight keys
        pavucontrol # audio control (waybar pulseaudio on-click)
      ]
      # GUI for ratbagd (G502 onboard-profile programming), behind the G502
      # gate. Spliced mid-list so the default-on package order is unchanged.
      ++ lib.optional cfg.g502.enable piper
      ++ [
        nwg-displays # GTK GUI: drag monitor layout, mode/scale dropdowns
        hyprmon # TUI: visual monitor layout, drag-and-drop, saved profiles
        networkmanagerapplet # nm-connection-editor (waybar network middle-click)
        networkmanager_dmenu # walker-driven wifi scan/join picker (network left-click)
        pinentry-qt # masked passphrase dialog for networkmanager_dmenu joins
        inter # UI font waybar + wlogout reference (else they fall back to DejaVu)
        swayosd # OSD server + client (workspace switch, optionally media keys)
      ]
      ++ lib.optional cfg.wlogout.enable wlogout
      ++ lib.optional cfg.cliphist.enable cliphist
      ++ lib.optional cfg.playerctlMediaKeys playerctl
      ++ lib.optional cfg.udiskie.enable udiskie
      ++ lib.optional cfg.bluetooth.enable blueman # waybar bluetooth on-click + applet
      ++ lib.optional cfg.polkitAgent.enable hyprpolkitagent;
  };
}
