# NOT a module: the shared helper attrset for the hyprland/ sub-modules.
# Imported per file as
#   h = import ./lib.nix {inherit config lib pkgs;};
# Pure evaluation — every helper is a pure function of config/lib/pkgs, so
# re-importing it from each sub-module yields identical derivations.
{
  config,
  lib,
  pkgs,
}: let
  cfg = config.hyprland-desktop;

  hyprctl = "${pkgs.hyprland}/bin/hyprctl";

  # The systemd user target this desktop's session services attach to.
  #
  # Under uwsm (uwsm.enable) the Hyprland session is launched by uwsm — which
  # owns the stock graphical-session.target — so services bind there (the uwsm
  # docs' recommended integration) and home-manager's own session integration
  # is turned off (wayland.windowManager.hyprland.systemd.enable = false). The
  # two cannot coexist: HM's integration starts hyprland-session.target
  # (BindsTo graphical-session.target) and, because this host runs
  # KillUserProcesses=false, that graphical-session.target leaks across logout
  # and uwsm then refuses to start ("a compositor or graphical-session* target
  # is already active"). Letting uwsm be the sole owner removes the conflict.
  #
  # Without uwsm, HM manages hyprland-session.target and services bind there.
  sessionTarget =
    if cfg.uwsm.enable
    then "graphical-session.target"
    else "hyprland-session.target";

  # Logout for a uwsm session. `uwsm stop` stops ONLY the compositor; it does
  # not stop graphical-session.target. On this host (logind KillUserProcesses=
  # false) the target then lingers — held active by darkman.service, which
  # BindsTo it and survives logout — and the NEXT uwsm login aborts with "a
  # compositor or graphical-session* target is already active" (black screen).
  # So stop the target first: an ordered SIGTERM to the scoped session services
  # (the actual graceful-logout win) that also clears the target, then stop the
  # compositor to return to the greeter. (`uwsm` / `systemctl` are bare PATH —
  # the system instances that own the running session.)
  uwsmLogout = pkgs.writeShellScript "uwsm-logout" ''
    systemctl --user stop graphical-session.target
    exec uwsm stop -r
  '';

  # GL wrapper prefix for apps launched from a systemd-user service (waybar
  # on-click), which start in a clean env without the compositor's
  # leaked nixGL discovery vars. Empty on NixOS (real hardware.graphics); a
  # nixGL command path on non-NixOS. `wrap` prepends it iff set.
  wrap = c:
    if cfg.glWrap == ""
    then c
    else "${cfg.glWrap} ${c}";
  glKitty = wrap "kitty";

  # Volume control commands per audio stack. pactl = PulseAudio,
  # wpctl = WirePlumber/PipeWire. Intentionally BARE (not store-qualified): the
  # tool is the host's *system* audio stack's client — Ubuntu's PulseAudio
  # `pactl`, NixOS's WirePlumber `wpctl` — which talks to the system audio
  # server. Pinning `${pkgs.pulseaudio}/bin/pactl` would put a nix client (the
  # launcher prepends ~/.nix-profile/bin) ahead of the system one and run it
  # against the system server — exactly the version-skew the hosts avoid. Both
  # consumers run a desktop audio stack, so the client is always on PATH.
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

  # networkmanager_dmenu's launcher (waybar network left-click): walker in dmenu
  # mode. The candidate SSID list arrives on stdin and the pick returns on stdout
  # — walker --dmenu is exactly a dmenu. Wrapped rather than set as
  # `dmenu_command = walker --dmenu` so any launcher-specific flags
  # networkmanager_dmenu appends for a tool it recognises are dropped: walker
  # isn't in its table today (so it appends nothing), but walker maps -i to
  # --index, which would make it return a row number instead of the SSID — the
  # wrapper keeps us safe if that table ever changes.
  nmDmenuLauncher = pkgs.writeShellScript "nmdm-walker" ''
    exec ${pkgs.walker}/bin/walker --dmenu
  '';

  # Screenshot helper: grim captures, then satty opens the shot for crop/
  # annotate. In satty, Ctrl+S saves a timestamped PNG to ~/Pictures/Screenshots
  # and Ctrl+C copies to the clipboard; --early-exit closes satty after either
  # action. `region` exits cleanly if slurp is cancelled; anything else captures
  # the focused monitor (the one with the active workspace), falling back to all
  # outputs if it can't be resolved.
  screenshot = pkgs.writeShellScriptBin "screenshot" ''
    set -eu
    dir="$HOME/Pictures/Screenshots"
    ${pkgs.coreutils}/bin/mkdir -p "$dir"
    out="$dir/Screenshot-$(${pkgs.coreutils}/bin/date +%Y-%m-%d_%H-%M-%S).png"
    edit() {
      ${pkgs.satty}/bin/satty --filename - \
        --output-filename "$out" \
        --early-exit \
        --copy-command "${pkgs.wl-clipboard}/bin/wl-copy"
    }
    case "''${1:-full}" in
      region)
        geom="$(${pkgs.slurp}/bin/slurp)" || exit 0
        ${pkgs.grim}/bin/grim -g "$geom" - | edit
        ;;
      *)
        mon="$(${hyprctl} -j activeworkspace 2>/dev/null | ${pkgs.jq}/bin/jq -r '.monitor // empty')"
        if [ -n "$mon" ]; then
          ${pkgs.grim}/bin/grim -o "$mon" - | edit
        else
          ${pkgs.grim}/bin/grim - | edit
        fi
        ;;
    esac
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

  # Re-lay-out waybar after a monitor change WITHOUT restarting it: SIGUSR1
  # hide+show recreates its layer-shell surfaces on the current outputs while
  # keeping the process, watcher, and tray intact. A `systemctl restart` would
  # tear down the StatusNotifier watcher waybar hosts and orphan once-only tray
  # icons (1Password). Exposed via the read-only `waybarRelayout` option for host
  # monitor-change handlers (lid binds, clamshell services). The mid sleep lets
  # the hide settle so the two signals don't coalesce into a no-op.
  #
  # DEBOUNCED. A single monitor change can invoke this several times — the
  # clamshell settle, a lid bind, and the extra configreloaded the undock
  # `hyprctl reload` kicks off — and a relayout that fires while the outputs are
  # still settling recreates waybar's surface onto a transient state, leaving it
  # mapped-but-BLANK (process + layer surface survive, so it reads as "waybar
  # vanished" with no crash). Firing per-call makes waybar visibly restart once
  # per invocation. Instead: each caller stamps a unique token and waits out a
  # debounce window; only the LAST caller in the burst survives the token check
  # and does the single hide+show. Net effect — exactly ONE relayout per monitor
  # change no matter how many callers fire, and because it lands only after the
  # burst goes quiet, it's past the output settle so the bar isn't left blank.
  waybarRelayoutScript = pkgs.writeShellScript "waybar-relayout" ''
    stamp="$XDG_RUNTIME_DIR/waybar-relayout.stamp"
    token="$$.$(${pkgs.coreutils}/bin/date +%s%N)"
    ${pkgs.coreutils}/bin/printf '%s' "$token" > "$stamp"
    ${pkgs.coreutils}/bin/sleep 1.5
    # A newer caller claimed the stamp during the window — let it do the work.
    [ "$(${pkgs.coreutils}/bin/cat "$stamp" 2>/dev/null)" = "$token" ] || exit 0
    ${pkgs.procps}/bin/pkill -SIGUSR1 waybar
    ${pkgs.coreutils}/bin/sleep 0.3
    ${pkgs.procps}/bin/pkill -SIGUSR1 waybar
  '';

  # 1Password registers its StatusNotifier tray icon exactly once at start and
  # never re-registers, so a cold start that beats waybar.service (which OWNS the
  # watcher) gets no icon. Wait up to ~15s for the watcher first. stripGlEnv
  # additionally drops the leaked nixGL GL-discovery env so a *system* Electron
  # 1Password under a nixGL-wrapped compositor doesn't load nix Mesa against the
  # system libc and SIGILL (the nixpkgs 1Password on NixOS needs no strip).
  onepasswordEnvStrip =
    lib.optionalString cfg.onePasswordTray.stripGlEnv ''
      ${pkgs.coreutils}/bin/env -u LD_LIBRARY_PATH -u __EGL_VENDOR_LIBRARY_FILENAMES -u LIBGL_DRIVERS_PATH -u LIBVA_DRIVERS_PATH -u GBM_BACKENDS_PATH '';
  onepasswordTrayScript = pkgs.writeShellScript "1password-tray" ''
    i=0
    while [ "$i" -lt 30 ]; do
      ${pkgs.systemd}/bin/busctl --user list 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -q org.kde.StatusNotifierWatcher && break
      ${pkgs.coreutils}/bin/sleep 0.5
      i=$((i + 1))
    done
    exec ${onepasswordEnvStrip}1password --silent
  '';
in {
  inherit
    cliphistStore
    focusOrLaunch
    fol
    g502Status
    glKitty
    hyprctl
    hyprspace
    keyboundWorkspaces
    nmDmenuLauncher
    onepasswordEnvStrip
    onepasswordTrayScript
    osd
    screenshot
    sessionTarget
    themeIcon
    uwsmLogout
    vol
    walkerLayout
    walkerMochaStyle
    waybarRelayoutScript
    workspaceOsd
    wrap
    ;
}
