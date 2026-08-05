# wayland.windowManager.hyprland — compositor settings: effects, exec-once,
# binds/gestures/input, and the hyprspace overview plugin. Split out of
# hyprland.nix; shared helpers come from ./lib.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hyprland-desktop;
  h = import ./lib.nix {inherit config lib pkgs;};
  inherit
    (h)
    cliphistStore
    hyprspace
    keyboundWorkspaces
    onepasswordTrayScript
    osd
    screenshot
    uwsmLogout
    vol
    workspaceOsd
    ;
in {
  config = lib.mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = lib.mkDefault true;
      # Under uwsm, uwsm owns the session (graphical-session.target) and imports
      # the environment via its finalize step, so home-manager's own session
      # integration (the hyprland-session.target + dbus-activation exec-once)
      # must be off — otherwise the two fight over graphical-session.target and
      # uwsm refuses to start. Without uwsm, HM manages the session as usual.
      systemd.enable = lib.mkDefault (!cfg.uwsm.enable);
      plugins = [hyprspace];

      # Stay on the hyprlang config generator (26.05 flipped the default to
      # "lua"). The lua dialect can't set plugin config values, and hyprspace
      # registers plugin:overview:* through the hyprlang-only addConfigValue —
      # so under lua the overview panel can't be themed or have its gestures
      # disabled. mkDefault so a host can opt into lua if it ever drops hyprspace.
      configType = lib.mkDefault "hyprlang";

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
          # Float GTK/Qt/Electron open and save dialogs (title-based, app-agnostic).
          windowrule {
            name = file-dialog-float
            match:title = ^(Open|Open File|Open Folder|Save|Save As|Save File)$
            float = true
          }
          # Float the xdg-desktop-portal file picker (used by Firefox, Electron, etc.).
          windowrule {
            name = xdg-file-picker-float
            match:class = ^(xdg-desktop-portal.*)$
            float = true
          }
        ''
        + cfg.extraConfig;

      settings = {
        "$mod" = "SUPER";
        "$terminal" = "kitty";
        "$menu" = "walker";
        # Catppuccin Mocha $crust for the hyprspace overview panel.
        "$crust" = "rgb(11111b)";

        # Window effects, gated on effects.enable (default on). Animations are
        # the GPU-heaviest part (every animated frame is a large full-surface
        # repaint on these Intel iGPUs), so a host on a weak GPU can opt out
        # with effects.enable = false — which also turns blur off (the other
        # expensive bit) and drops rounding/shadows for a flat, cheap session.
        animations.enabled = lib.mkDefault cfg.effects.enable;
        decoration = {
          rounding = lib.mkDefault (
            if cfg.effects.enable
            then 10
            else 0
          );
          blur = {
            enabled = lib.mkDefault cfg.effects.enable;
            size = lib.mkDefault 5;
            passes = lib.mkDefault 2;
          };
          shadow.enabled = lib.mkDefault cfg.effects.enable;
        };

        # Keep Hyprland's session log on disk for diagnosing hot-plug/exit issues.
        debug.disable_logs = false;

        exec-once =
          # GUI polkit agent (privilege-escalation prompts under Hyprland).
          lib.optional cfg.polkitAgent.enable "${pkgs.hyprpolkitagent}/bin/hyprpolkitagent"
          # 1Password tray, waiting for waybar's StatusNotifier watcher first.
          ++ lib.optional cfg.onePasswordTray.enable "${onepasswordTrayScript}"
          ++ ["${workspaceOsd}"]
          ++ lib.optionals cfg.cliphist.enable [
            # cliphist stores every text + image selection so $mod+V can recall
            # it. Routed through cliphistStore, which drops sensitive (1Password
            # password) copies cliphist itself would otherwise save.
            "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${cliphistStore}"
            "${pkgs.wl-clipboard}/bin/wl-paste --type image --watch ${cliphistStore}"
          ]
          ++ lib.optional cfg.udiskie.enable
          "${pkgs.udiskie}/bin/udiskie --automount --notify --tray"
          # blueman applet: provides the org.blueman.Applet D-Bus service the
          # waybar bluetooth module's blueman-manager on-click needs.
          ++ lib.optional cfg.bluetooth.enable "${pkgs.blueman}/bin/blueman-applet"
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
            # Logout: graceful uwsm teardown (uwsmLogout) on uwsm hosts, else exit.
            (
              if cfg.uwsm.enable
              then "$mod SHIFT, E, exec, ${uwsmLogout}"
              else "$mod SHIFT, E, exit"
            )
            # Screenshots open in satty to crop/annotate; Ctrl+S saves to
            # ~/Pictures/Screenshots, Ctrl+C copies. Print = drag a region first
            # (GNOME-style); Shift+Print = whole focused monitor (no crop box);
            # $mod+Shift+S = region select for keyboards with no Print key.
            ", Print, exec, ${screenshot}/bin/screenshot region"
            "SHIFT, Print, exec, ${screenshot}/bin/screenshot full"
            "$mod SHIFT, S, exec, ${screenshot}/bin/screenshot region"
            "$mod, left, movefocus, l"
            "$mod, right, movefocus, r"
            "$mod, up, movefocus, u"
            "$mod, down, movefocus, d"
          ]
          # G502 thumb buttons + $mod: previous/next workspace.
          ++ lib.optionals cfg.g502.enable [
            "$mod, mouse:275, workspace, e-1"
            "$mod, mouse:276, workspace, e+1"
          ]
          ++ [
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
          kb_layout = lib.mkDefault "us";
          natural_scroll = lib.mkDefault true;
          touchpad = {
            natural_scroll = lib.mkDefault true;
            tap-to-click = lib.mkDefault false;
            clickfinger_behavior = lib.mkDefault true;
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
