# Shared Hyprland desktop (home-manager). The ~identical core of the per-host
# Hyprland configs — helper scripts, kitty/waybar/walker/wlogout, the
# swayosd/wpaperd/elephant services, the dynamic-workspace model + switch OSD,
# and the binds/gestures/input/overview — lifted out of the host files so the
# two hosts can't silently drift (they had: birdrock missing swayosd, divergent
# workspace models, a stale waybar). Host-specific glue (monitor layouts, nixGL,
# Apple-T2 backlight/clamshell, portals, PAM, mako, etc.) stays in the host
# file; differences that ARE shared-but-parameterised become options below.
#
# Consumed via nix-common.homeModules.hyprland; enable + configure with
#   hyprland-desktop = { enable = true; volumeBackend = "pactl"; ... };
# The host still sets wayland.windowManager.hyprland.settings.monitor (and any
# other host-only settings) directly — those merge with what this module sets.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hyprland-desktop;

  hyprctl = "${pkgs.hyprland}/bin/hyprctl";

  # GL wrapper prefix for apps launched from a systemd-user service (waybar
  # on-click, wpaperd), which start in a clean env without the compositor's
  # leaked nixGL discovery vars. Empty on NixOS (real hardware.graphics); a
  # nixGL command path on non-NixOS. `wrap` prepends it iff set.
  wrap = c:
    if cfg.glWrap == ""
    then c
    else "${cfg.glWrap} ${c}";
  glKitty = wrap "kitty";

  # Volume control commands per audio stack. pactl = PulseAudio,
  # wpctl = WirePlumber/PipeWire.
  vol =
    {
      pactl = {
        up = "pactl set-sink-volume @DEFAULT_SINK@ +5%";
        down = "pactl set-sink-volume @DEFAULT_SINK@ -5%";
        mute = "pactl set-sink-mute @DEFAULT_SINK@ toggle";
        micMute = "pactl set-source-mute @DEFAULT_SOURCE@ toggle";
      };
      wpctl = {
        up = "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
        down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        mute = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        micMute = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
      };
    }
    .${
      cfg.volumeBackend
    };

  # Optional swayosd popup suffix for the media keys (best-effort display only;
  # the pactl/wpctl/brightnessctl call always does the real change). Off where
  # swayosd only paints the workspace OSD and not media keys.
  osd = sub: lib.optionalString cfg.mediaKeyOsd " ; ${pkgs.swayosd}/bin/swayosd-client ${sub}";

  # --- helper scripts (were duplicated verbatim across both hosts) ------------

  # waybar light/dark indicator: moon glyph when dark, sun when light, read
  # from darkman. printf emits the nerd-font codepoints (avoids glyph-drop).
  themeIcon = pkgs.writeShellScriptBin "waybar-theme-icon" ''
    if [ "$(${pkgs.darkman}/bin/darkman get)" = "dark" ]; then
      printf '\U000f0594'
    else
      printf '\U000f0599'
    fi
  '';

  # Live G502 profile + DPI for waybar. ratbagd/piper only read the mouse's
  # onboard state once at probe time, so onboard DPI-button presses are
  # invisible to `ratbagctl ... active get`. Query the mouse directly over
  # HID++ 2.0 instead: ADJUSTABLE_DPI (0x2201) getSensorDpi for the live DPI,
  # ONBOARD_PROFILES (0x8100) getCurrentProfile/getCurrentDpiIndex for the
  # active profile/slot. Needs the hidraw uaccess udev rule (per-host system
  # layer) so the seat user can open the device node. Emits waybar JSON;
  # empty text + "hidden" class when the mouse is unplugged.
  g502Status = pkgs.writeScriptBin "waybar-g502" ''
    #!${pkgs.python3}/bin/python3
    import glob
    import json
    import os
    import select

    SWID = 0x0D  # arbitrary software id, distinct from ratbagd's
    DEV = 0xFF  # device index for a wired HID++ device


    def nodes():
        # The G502 exposes two hidraw nodes; the keyboard/consumer endpoint
        # rejects 20-byte HID++ long reports with EPIPE and gets skipped.
        for p in sorted(glob.glob("/sys/class/hidraw/hidraw*/device/uevent")):
            try:
                with open(p) as f:
                    txt = f.read()
            except OSError:
                continue
            if "046D" in txt and "C08B" in txt:
                yield "/dev/" + p.split("/")[4]


    def call(fd, feat, func, params=b""):
        req = bytes([0x11, DEV, feat, (func << 4) | SWID]) + params
        req += bytes(20 - len(req))
        try:
            os.write(fd, req)
        except OSError:
            return None
        for _ in range(6):
            r, _, _ = select.select([fd], [], [], 0.3)
            if not r:
                return None
            resp = os.read(fd, 32)
            if len(resp) < 4 or resp[0] != 0x11:
                continue
            if resp[1] == DEV and resp[2] == feat and resp[3] == (func << 4 | SWID):
                return resp[4:]
            if resp[2] == 0xFF and resp[3] == feat:  # HID++ 2.0 error reply
                return None
        return None


    def read_state():
        for node in nodes():
            try:
                fd = os.open(node, os.O_RDWR)
            except OSError:
                continue
            try:
                # ROOT.getFeature() resolves feature id -> index at runtime
                feat_dpi = call(fd, 0, 0, bytes([0x22, 0x01]))
                if not feat_dpi or feat_dpi[0] == 0:
                    continue
                feat_obp = call(fd, 0, 0, bytes([0x81, 0x00]))
                dpi = call(fd, feat_dpi[0], 0x2, bytes([0]))
                prof = slot = None
                if feat_obp and feat_obp[0]:
                    prof = call(fd, feat_obp[0], 0x4)
                    slot = call(fd, feat_obp[0], 0xB)
                if not dpi:
                    continue
                return {
                    "dpi": (dpi[1] << 8) | dpi[2],
                    "profile": prof[1] if prof else None,  # 1-based, as in piper
                    "slot": slot[0] + 1 if slot else None,  # 0-based on the wire
                }
            finally:
                os.close(fd)
        return None


    s = read_state()
    if not s:
        print(json.dumps({"text": "", "class": "hidden"}))
    else:
        text = f"P{s['profile']} {s['dpi']}" if s["profile"] else str(s["dpi"])
        tip = f"G502 · profile {s['profile']} · DPI slot {s['slot']} · {s['dpi']} dpi"
        print(json.dumps({"text": text, "tooltip": tip, "class": "g502"}))
  '';

  # Single-instance app launcher for waybar on-click handlers. Repeated clicks
  # otherwise spawn a window per click; this focuses the existing window
  # instead (focuswindow also switches to its workspace). $1 is a
  # case-insensitive regex matched against window class.
  focusOrLaunch = pkgs.writeShellScriptBin "focus-or-launch" ''
    class="$1"
    shift
    addr=$(${hyprctl} -j clients \
      | ${pkgs.jq}/bin/jq -r --arg re "$class" \
          'first(.[] | select(.class | test($re; "i")) | .address) // empty')
    if [ -n "$addr" ]; then
      exec ${hyprctl} dispatch focuswindow "address:$addr"
    fi
    # Launch through the compositor, not a plain exec: this script runs inside
    # waybar.service's cgroup, so a bare `exec "$@"` makes the launched app a
    # waybar child. waybar has Restart=on-failure and crash-restarts on monitor
    # changes (dock/undock/lid) — which kills its whole cgroup, taking the app
    # with it. `hyprctl dispatch exec` reparents it into the compositor's tree
    # so it survives any waybar reload/restart/crash.
    #
    # "$*" (single joined string), NOT "$@": hyprctl getopt-parses its argv, so a
    # launch command with a -- flag (e.g. `kitty --class btop`) passed as separate
    # args makes hyprctl treat `--class` as its OWN flag and bail with a usage
    # error — nothing launches. Joining into one arg hands hyprctl the whole
    # command as the exec string, which it sh -c's.
    exec ${hyprctl} dispatch exec "$*"
  '';
  fol = "${focusOrLaunch}/bin/focus-or-launch";

  # Screenshot helper: grim/slurp -> timestamped PNG in ~/Pictures/Screenshots,
  # also copied to the clipboard. `region` exits cleanly if slurp is cancelled;
  # anything else captures the focused monitor (the one with the active
  # workspace), falling back to all outputs if it can't be resolved.
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    set -eu
    dir="$HOME/Pictures/Screenshots"
    ${pkgs.coreutils}/bin/mkdir -p "$dir"
    file="$dir/Screenshot-$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S).png"
    case "''${1:-full}" in
      region)
        geom="$(${pkgs.slurp}/bin/slurp)" || exit 0
        ${pkgs.grim}/bin/grim -g "$geom" "$file"
        ;;
      *)
        mon="$(${hyprctl} -j activeworkspace 2>/dev/null | ${pkgs.jq}/bin/jq -r '.monitor // empty')"
        if [ -n "$mon" ]; then
          ${pkgs.grim}/bin/grim -o "$mon" "$file"
        else
          ${pkgs.grim}/bin/grim "$file"
        fi
        ;;
    esac
    ${pkgs.wl-clipboard}/bin/wl-copy --type image/png <"$file"
  '';

  # OSD on workspace switch. Hyprland's IPC socket2 emits an event line for
  # every workspace change and monitor-focus change no matter how it was
  # triggered (keybind, mouse, gesture, overview), so one listener covers them
  # all — far less glue than wrapping each dispatcher. On a relevant event we
  # read the authoritative active workspace + its monitor from hyprctl (rather
  # than parsing the event) and pop a swayosd custom message like
  # "Workspace 3 · DP-4". The outer loop reconnects if socat ever drops the
  # socket (e.g. a compositor IPC blip) so the OSD doesn't silently die.
  workspaceOsd = pkgs.writeShellScript "workspace-osd" ''
    sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    while true; do
      ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$sock" | while read -r line; do
        case "$line" in
          "workspace>>"* | "focusedmon>>"*)
            ws="$(${hyprctl} -j activeworkspace \
              | ${pkgs.jq}/bin/jq -r '"\(.name) · \(.monitor)"')"
            [ -n "$ws" ] && ${pkgs.swayosd}/bin/swayosd-client \
              --custom-message "Workspace $ws" --custom-icon video-display
            ;;
        esac
      done
      ${pkgs.coreutils}/bin/sleep 1
    done
  '';

  # cliphist store guarded against sensitive copies. cliphist itself stores
  # whatever is piped to it — it does NOT honor wl-clipboard's
  # CLIPBOARD_STATE=sensitive, so a bare `wl-paste --watch cliphist store`
  # captures every password. 1Password marks password copies with the
  # x-kde-passwordManagerHint mime, and wl-paste (>=2.3.0) turns that into
  # CLIPBOARD_STATE=sensitive for its --watch child — so drop sensitive copies
  # here, before they reach the history.
  cliphistStore = pkgs.writeShellScript "cliphist-store" ''
    [ "$CLIPBOARD_STATE" = sensitive ] && exit 0
    exec ${pkgs.cliphist}/bin/cliphist store
  '';

  # Workspaces are dynamic: created on demand on the focused monitor and
  # destroyed when empty. Nothing is pinned to a monitor or pre-created, so a
  # changing monitor topology can't strand a workspace on an absent or disabled
  # output (which is how windows used to vanish under the old monitor-pinned
  # grid). The overview (hyprspace) renders whatever workspaces exist, so it
  # needs no pre-populated grid. $mod+N / $mod+SHIFT+N piggy-back on the number
  # row, so only 1-9 get bindings; higher numbers still spawn on demand.
  keyboundWorkspaces = builtins.genList (i: i + 1) 9;

  # walker 2.x theme. walker 2.x replaced the 0.13 TOML `layout` with GTK XML
  # layout files + a CSS stylesheet. Rather than hand-maintain the XML tree,
  # reuse walker's own default theme for the installed version (layout verbatim)
  # and only recolour the stylesheet to Catppuccin Mocha.
  walkerSrc = pkgs.fetchFromGitHub {
    owner = "abenz1267";
    repo = "walker";
    rev = "v2.16.2"; # keep in sync with pkgs.walker.version
    hash = "sha256-fX3ErzTmHRO9z1SzHC2VZUgKOgRfO13X/joC5a3QN7Q=";
  };
  walkerThemeDir = "${walkerSrc}/resources/themes/default";
  # Each XML becomes themes/mocha/<name>.xml. The HM module treats store
  # *sub*paths as literal text (only top-level store paths as files), so pass
  # the file *contents* as strings rather than the paths.
  walkerLayout =
    lib.mapAttrs'
    (n: _: lib.nameValuePair (lib.removeSuffix ".xml" n) (builtins.readFile "${walkerThemeDir}/${n}"))
    (lib.filterAttrs (n: _: lib.hasSuffix ".xml" n) (builtins.readDir walkerThemeDir));
  walkerMochaStyle =
    builtins.replaceStrings
    ["#1f1f28" "#54546d" "#f2ecbc" "#C34043" "#DCD7BA"]
    ["#1e1e2e" "#585b70" "#cdd6f4" "#f38ba8" "#1e1e2e"]
    (builtins.readFile "${walkerThemeDir}/style.css");

  # hyprspace overview (the hyprexpo replacement, behind $mod+grave / 4-finger-
  # up). nixpkgs' hyprlandPlugins.hyprspace pins a pre-0.55 rev that won't
  # compile against Hyprland 0.55 (the LayoutManager headers moved), so override
  # the source to an upstream commit carrying the 0.55 fixes. Built against
  # pkgs.hyprland so the plugin ABI matches the compositor.
  hyprspace = pkgs.hyprlandPlugins.hyprspace.overrideAttrs (_: {
    version = "0-unstable-2026-05-28";
    src = pkgs.fetchFromGitHub {
      owner = "KZDKM";
      repo = "Hyprspace";
      rev = "c109256f5a79a8694acd6176971c4a273d32264c";
      hash = "sha256-q+5ETwj+oiZBT9j6/huwB8nwV4nbZdZmCrchL2E7tDQ=";
    };
  });
in {
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
        (waybar on-click TUIs, wpaperd), which start without the compositor's
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
      description = "Directory of wallpapers for wpaperd (rotated every 30m). Null disables the managed wpaperd service.";
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
    home.packages = with pkgs;
      [
        grim # screenshots
        slurp # region select
        wl-clipboard # clipboard
        brightnessctl # backlight keys
        pavucontrol # audio control (waybar pulseaudio on-click)
        piper # GUI for ratbagd: G502 onboard-profile programming
        nwg-displays # GTK GUI: drag monitor layout, mode/scale dropdowns
        hyprmon # TUI: visual monitor layout, drag-and-drop, saved profiles
        networkmanagerapplet # nm-connection-editor for the waybar network on-click
        blueman # bluetooth manager (waybar bluetooth module on-click)
        inter # UI font waybar + wlogout reference (else they fall back to DejaVu)
        swayosd # OSD server + client (workspace switch, optionally media keys)
      ]
      ++ lib.optional cfg.wlogout.enable wlogout
      ++ lib.optional cfg.cliphist.enable cliphist
      ++ lib.optional cfg.playerctlMediaKeys playerctl
      ++ lib.optional cfg.udiskie.enable udiskie;

    # Kitty declaratively, so catppuccin/nix's kitty module auto-enables and
    # themes it (Mocha). Translucent so the wallpaper bleeds through.
    programs.kitty = {
      enable = true;
      settings = {
        background_opacity = "0.90";
        dynamic_background_opacity = "yes";
        background_blur = 5;
        allow_remote_control = "yes";
      };
    };

    # Declarative waybar. Icon glyphs are nerd-font (Symbols Nerd Font)
    # Material Design Icons.
    programs.waybar = {
      enable = true;
      # Scope to hyprland-session.target so the bar doesn't also start under the
      # GNOME/Plasma sessions that still exist in GDM's session list. 26.05
      # renamed the singular `target` to a `targets` list.
      systemd = {
        enable = true;
        targets = ["hyprland-session.target"];
      };
      settings.mainBar = {
        layer = "top";
        position = "top";
        height = 34;

        modules-left = ["hyprland/workspaces" "hyprland/window"];
        modules-center = ["clock"];
        modules-right = [
          "idle_inhibitor"
          "pulseaudio"
          "backlight"
          "network"
          "bluetooth"
          "power-profiles-daemon"
          "cpu"
          "memory"
          "temperature"
          "battery"
          "custom/mouse"
          "tray"
          "custom/theme"
          "custom/power"
        ];

        "hyprland/workspaces" = {
          # macOS Spaces-style dots: filled = active, hollow = occupied. The
          # middot `empty` icon is a harmless fallback that no longer triggers —
          # workspaces are dynamic, so empty ones are destroyed.
          format = "{icon}";
          format-icons = {
            active = "●";
            default = "○";
            empty = "·";
          };
          on-click = "activate";
        };

        "hyprland/window" = {
          format = "{title}";
          max-length = 50;
          separate-outputs = true;
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰅶";
            deactivated = "󰅷";
          };
        };

        clock = {
          format = "{:%a %d %b  %H:%M}";
          format-alt = "{:%Y-%m-%d %H:%M:%S}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          calendar = {
            mode = "month";
            mode-mon-col = 3;
            weeks-pos = "right";
            on-scroll = 1;
            format = {
              months = "<span color='#ffead3'><b>{}</b></span>";
              days = "<span color='#ecc6d9'><b>{}</b></span>";
              weeks = "<span color='#99ffdd'><b>W{}</b></span>";
              weekdays = "<span color='#ffcc66'><b>{}</b></span>";
              today = "<span color='#ff6699'><b><u>{}</u></b></span>";
            };
          };
          actions = {
            on-click-right = "mode";
            on-scroll-up = "shift_up";
            on-scroll-down = "shift_down";
          };
        };

        backlight = {
          format = "{percent}% {icon}";
          format-icons = ["󰃞" "󰃟" "󰃠"];
          on-scroll-up = "brightnessctl set 5%+";
          on-scroll-down = "brightnessctl set 5%-";
        };

        network = {
          format-wifi = "{essid} ({signalStrength}%) 󰖩";
          format-ethernet = "{ipaddr}/{cidr} 󰈀";
          format-linked = "{ifname} (No IP) 󰈀";
          format-disconnected = "disconnected 󰖪";
          tooltip-format = "{ifname} via {gwaddr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%) {ipaddr}";
          tooltip-format-ethernet = "{ifname} {ipaddr}";
          on-click = "${fol} nm-connection-editor ${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
          on-click-right = "${fol} nmtui ${glKitty} --class nmtui -e nmtui";
        };

        # Bluetooth. Reads bluez over D-Bus directly — no applet/agent needed
        # for status — and opens blueman-manager (pairing/connect GUI) on click.
        # Hidden when the controller is off so it doesn't clutter the bar.
        bluetooth = {
          format = "󰂯";
          format-disabled = "";
          format-off = "";
          format-connected = "󰂱 {num_connections}";
          tooltip-format = "{controller_alias}\t{controller_address}\n\n{num_connections} connected";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          on-click = "${fol} blueman-manager ${pkgs.blueman}/bin/blueman-manager";
        };

        "power-profiles-daemon" = {
          format = "{icon}";
          tooltip = true;
          tooltip-format = "Power profile: {profile}\nDriver: {driver}";
          format-icons = {
            default = "󰐥";
            performance = "󰓅";
            balanced = "󰿥";
            power-saver = "󰌪";
          };
        };

        cpu = {
          format = "{usage}% 󰻠";
          tooltip = true;
          on-click = "${fol} btop ${glKitty} --class btop -e btop";
        };

        memory = {
          format = "{}% 󰍛";
          on-click = "${fol} btop ${glKitty} --class btop -e btop";
        };

        temperature = {
          critical-threshold = 85;
          format = "{temperatureC}°C {icon}";
          format-icons = ["󰔐" "󰔏" "󰔏"];
        };

        battery = {
          format = "{capacity}% {icon}";
          format-charging = "{capacity}% 󰂄";
          format-icons = ["󰁺" "󰁼" "󰁾" "󰂀" "󰂂"];
          states = {
            warning = 30;
            critical = 15;
          };
        };

        pulseaudio = {
          format = "{volume}% {icon}";
          format-muted = "muted 󰝟";
          format-icons.default = ["󰕿" "󰖀" "󰕾"];
          on-click = "${fol} pavucontrol pavucontrol";
          on-click-right = vol.mute;
        };

        tray = {
          spacing = 10;
        };

        # Live G502 profile + DPI (see g502Status above). 2s interval.
        "custom/mouse" = {
          exec = "${g502Status}/bin/waybar-g502";
          return-type = "json";
          interval = 2;
          format = "{} 󰍽";
          on-click = "${fol} piper ${pkgs.piper}/bin/piper";
        };

        "custom/theme" = {
          exec = "${themeIcon}/bin/waybar-theme-icon";
          on-click = "${pkgs.darkman}/bin/darkman toggle";
          format = "{}";
          tooltip = false;
          interval = "once";
          signal = 1; # darkman scripts pkill -RTMIN+1 waybar to refresh this
        };

        "custom/power" = {
          format = "⏻";
          tooltip = true;
          tooltip-format = "Click: power menu\nRight-click: lock";
          # Left-click opens the wlogout power menu; right-click locks.
          on-click = "wlogout";
          on-click-right = "loginctl lock-session";
        };
      };

      # Palette names (@base, @text, @mauve, …) come from the @import
      # "mocha.css" that catppuccin/nix prepends. Per-module color + matching
      # underline, since waybar labels don't reliably inherit color from
      # window#waybar (the GTK theme wins).
      style = ''
        * {
          font-family: "Inter", "Symbols Nerd Font", sans-serif;
          font-size: 14px;
          min-height: 0;
        }
        window#waybar {
          background-color: alpha(@crust, 0.92);
          color: @overlay0;
          border-bottom: 1px solid @overlay1;
        }
        #window {
          padding: 0 12px;
          color: @subtext1;
        }

        #workspaces button {
          padding: 0 3px;
          color: @text;
          background: transparent;
          border-top: 2px solid transparent;
        }
        #workspaces button:hover {
          color: @mauve;
          background: rgba(0, 0, 0, 0.3);
          border-top: 2px solid @mauve;
        }
        #workspaces button.active {
          color: @mauve;
          background: rgba(0, 0, 0, 0.3);
          border-top: 2px solid @mauve;
        }

        #clock,
        #pulseaudio,
        #network,
        #bluetooth,
        #power-profiles-daemon,
        #cpu,
        #memory,
        #temperature,
        #backlight,
        #battery,
        #idle_inhibitor,
        #tray,
        #custom-mouse,
        #custom-theme,
        #custom-power {
          padding: 0 8px;
          margin: 2px 4px;
        }

        #clock           { color: @maroon;    border-bottom: 2px solid @maroon; }
        #pulseaudio      { color: @blue;      border-bottom: 2px solid @blue; }
        #network         { color: @yellow;    border-bottom: 2px solid @yellow; }
        #bluetooth       { color: @sky;       border-bottom: 2px solid @sky; }
        #power-profiles-daemon { color: @sapphire; border-bottom: 2px solid @sapphire; }
        #cpu             { color: @peach;     border-bottom: 2px solid @peach; }
        #memory          { color: @lavender;  border-bottom: 2px solid @lavender; }
        #temperature     { color: @teal;      border-bottom: 2px solid @teal; }
        #backlight       { color: @yellow;    border-bottom: 2px solid @yellow; }
        #battery         { color: @green;     border-bottom: 2px solid @green; }
        #custom-mouse    { color: @pink;      border-bottom: 2px solid @pink; }
        #custom-mouse.hidden { padding: 0; margin: 0; border-bottom: none; }
        #idle_inhibitor  { color: @green; }
        #idle_inhibitor.activated { color: @red; }
        #tray            { color: @subtext1; }
        #custom-theme    { color: @mauve; }
        #custom-power    { color: @red; margin-right: 8px; }

        #battery.warning      { color: @peach;  border-bottom-color: @peach; }
        #battery.critical     { color: @red;    border-bottom-color: @red; }
        #temperature.critical { color: @red;    border-bottom-color: @red; }
      '';
    };

    # Power menu (waybar power button). The nixpkgs wlogout package ships icons
    # but NO default layout, so a bare `wlogout` opens with zero buttons —
    # provide an explicit layout + a Catppuccin-Mocha style pointing at the
    # package's bundled icons.
    programs.wlogout = lib.mkIf cfg.wlogout.enable {
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
          action = "${hyprctl} dispatch exit";
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

    # walker (the app launcher bound to $mod+Space), via the home-manager
    # module; the systemd service makes $mod+Space instant (resident
    # GApplication). walker 2.x's data providers (apps, runner, calc, …) live in
    # the separate `elephant` daemon (services.elephant) — without it the
    # launcher opens but lists nothing.
    services.walker = {
      enable = true;
      systemd.enable = true;
      theme = {
        name = "mocha";
        layout = walkerLayout;
        style = walkerMochaStyle;
      };
    };
    # Scope walker + elephant to the Hyprland session (the module defaults to
    # graphical-session.target, which the GNOME/Plasma sessions also reach).
    systemd.user.services.walker.Install.WantedBy = lib.mkForce ["hyprland-session.target"];
    services.elephant.enable = true;
    systemd.user.services.elephant.Install.WantedBy = lib.mkForce ["hyprland-session.target"];

    # wpaperd paints + rotates the desktop background. Same pool on every
    # output, random order, new image every 30 minutes.
    services.wpaperd = lib.mkIf (cfg.wallpaperPath != null) {
      enable = true;
      settings.default = {
        path = "${cfg.wallpaperPath}";
        duration = "30m";
        sorting = "random";
      };
    };
    systemd.user.services.wpaperd = lib.mkIf (cfg.wallpaperPath != null) {
      Install.WantedBy = lib.mkForce ["hyprland-session.target"];
      # wpaperd renders via EGL, so on nixGL hosts the systemd-clean env can't
      # find a GL context (bare wpaperd dies "Failed to get EGL display"). wrap
      # injects the GL context; on NixOS glWrap is empty so this is the default.
      Service.ExecStart = lib.mkForce (wrap "${pkgs.wpaperd}/bin/wpaperd");
    };

    # swayosd OSD server — paints the workspace-switch popups (workspaceOsd) and,
    # where mediaKeyOsd is on, the volume/brightness popups. cairo/layer-shell,
    # no GL. Hand-rolled unit (no home-manager services.swayosd), target-scoped
    # like the others.
    systemd.user.services.swayosd = {
      Unit = {
        Description = "swayosd OSD server";
        PartOf = ["hyprland-session.target"];
        After = ["hyprland-session.target"];
      };
      Service = {
        ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
        Restart = "on-failure";
      };
      Install.WantedBy = ["hyprland-session.target"];
    };

    wayland.windowManager.hyprland = {
      enable = true;
      systemd.enable = lib.mkDefault true;
      plugins = [hyprspace];

      # 1Password Quick Access: keep the picker up until dismissed (Esc/Enter),
      # not until the cursor leaves it. Written as raw extraConfig (not
      # settings.windowrule) because Hyprland 0.55's windowrule is a v3 "special
      # category" block whose `name` MUST be the first field — the HM settings
      # serializer sorts keys alphabetically and would break that. Host
      # extraConfig is appended after.
      extraConfig =
        ''
          windowrule {
            name = 1p-quick-access
            match:class = ^(1password)$
            match:title = ^(Quick Access.*)$
            stay_focused = true
          }
        ''
        + cfg.extraConfig;

      settings = {
        "$mod" = "SUPER";
        "$terminal" = "kitty";
        "$menu" = "walker";
        # Catppuccin Mocha $crust for the hyprspace overview panel.
        "$crust" = "rgb(11111b)";

        # Animations off: every animated frame is a large full-surface repaint
        # on these iGPUs (Intel UHD), which strains the GPU / atomic-commit path.
        animations.enabled = false;

        # Keep Hyprland's session log on disk for diagnosing hot-plug/exit issues.
        debug.disable_logs = false;

        exec-once =
          ["${workspaceOsd}"]
          ++ lib.optionals cfg.cliphist.enable [
            # cliphist stores every text + image selection so $mod+V can recall
            # it. Routed through cliphistStore, which drops sensitive (1Password
            # password) copies cliphist itself would otherwise save.
            "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${cliphistStore}"
            "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${cliphistStore}"
          ]
          ++ lib.optional cfg.udiskie.enable
          "${pkgs.udiskie}/bin/udiskie --automount --notify --tray"
          ++ cfg.extraExecOnce;

        bind =
          [
            "$mod, Return, exec, $terminal"
            "$mod, Space, exec, $menu"
            "$mod SHIFT, Space, exec, ${cfg.onePasswordQuickAccessCmd}"
            "$mod, grave, overview:toggle" # hyprspace overview
            "$mod, Q, killactive"
            "$mod, F, fullscreen"
            "$mod, L, exec, loginctl lock-session"
            "$mod SHIFT, E, exit"
            # Screenshots -> ~/Pictures/Screenshots + clipboard. Print = full
            # focused monitor; Shift+Print or $mod+Shift+S = region select
            # ($mod+Shift+S also works on keyboards with no Print key).
            ", Print, exec, ${screenshot}/bin/screenshot full"
            "SHIFT, Print, exec, ${screenshot}/bin/screenshot region"
            "$mod SHIFT, S, exec, ${screenshot}/bin/screenshot region"
            "$mod, left, movefocus, l"
            "$mod, right, movefocus, r"
            "$mod, up, movefocus, u"
            "$mod, down, movefocus, d"
            # G502 thumb buttons + $mod: previous/next workspace.
            "$mod, mouse:275, workspace, e-1"
            "$mod, mouse:276, workspace, e+1"
            # Next empty workspace (W = workspace): $mod+W jumps to the first
            # empty workspace, $mod+Shift+W flings the focused window onto it.
            "$mod, W, workspace, empty"
            "$mod SHIFT, W, movetoworkspace, empty"
          ]
          ++ lib.optional cfg.cliphist.enable
          # Clipboard-history picker: cliphist entries through walker's dmenu
          # mode, decode the pick, copy it back.
          "$mod, V, exec, ${pkgs.cliphist}/bin/cliphist list | walker --dmenu | ${pkgs.cliphist}/bin/cliphist decode | ${pkgs.wl-clipboard}/bin/wl-copy"
          ++ cfg.extraBind
          ++ map (n: "$mod, ${toString n}, workspace, ${toString n}") keyboundWorkspaces
          ++ map (n: "$mod SHIFT, ${toString n}, movetoworkspace, ${toString n}") keyboundWorkspaces;

        bindm = [
          "$mod, mouse:272, movewindow"
          "$mod, mouse:273, resizewindow"
        ];

        # Repeatable (hold) + works while locked: brightness + volume.
        # brightnessctl auto-detects the backlight device.
        bindel =
          [
            ",XF86MonBrightnessUp, exec, brightnessctl set 5%+${osd "--brightness +0"}"
            ",XF86MonBrightnessDown, exec, brightnessctl set 5%-${osd "--brightness +0"}"
            ",XF86AudioRaiseVolume, exec, ${vol.up}${osd "--output-volume +0"}"
            ",XF86AudioLowerVolume, exec, ${vol.down}${osd "--output-volume +0"}"
          ]
          ++ cfg.extraBindel;

        # Locked (no repeat): mute toggles, optional media-transport keys.
        bindl =
          [
            ",XF86AudioMute, exec, ${vol.mute}${osd "--output-volume +0"}"
            ",XF86AudioMicMute, exec, ${vol.micMute}${osd "--input-volume +0"}"
          ]
          ++ lib.optionals cfg.playerctlMediaKeys [
            ",XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
            ",XF86AudioPause, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
            ",XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next"
            ",XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous"
          ]
          ++ cfg.extraBindl;

        input = {
          kb_layout = "us";
          natural_scroll = true;
          touchpad = {
            natural_scroll = true;
            tap-to-click = false;
            clickfinger_behavior = true;
          };
        };

        # macOS-style trackpad gestures (Hyprland 0.51+ per-gesture syntax).
        gestures = {
          gesture = [
            "3, horizontal, workspace"
            "3, horizontal, mod: $mod, move"
            "4, up, dispatcher, overview:toggle" # hyprspace overview
            "4, pinchin, dispatcher, exec, $menu"
            "4, pinchout, dispatcher, togglespecialworkspace"
          ];
        };

        # hyprspace overview tuning. Driven from our own 4-finger gesture + the
        # $mod+grave keybind, so disable the plugin's built-in gestures.
        plugin = {
          overview = {
            disableGestures = true;
            panelColor = "$crust";
            overrideGaps = true;
            gapsIn = 5;
            gapsOut = 5;
          };
        };
      };
    };
  };
}
