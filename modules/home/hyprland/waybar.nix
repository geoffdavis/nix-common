# waybar — the declarative status bar: module set, per-module on-click
# handlers, and the Catppuccin-palette CSS. Split out of hyprland.nix;
# shared helpers come from ./lib.nix.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hyprland-desktop;
  h = import ./lib.nix {inherit config lib pkgs;};
  inherit (h) fol g502Status glKitty sessionGuard sessionTarget themeIcon vol;
in {
  config = lib.mkIf cfg.enable {
    programs = {
      waybar = {
        enable = lib.mkDefault true;
        # Scope to the session target so the bar doesn't also start under the
        # other desktop sessions in the greeter's session list. 26.05 renamed
        # the singular `target` to a `targets` list. Under uwsm that target is
        # the shared graphical-session.target, which those sessions DO reach —
        # hence the sessionGuard ExecCondition below.
        systemd = {
          enable = lib.mkDefault true;
          targets = [sessionTarget];
        };
        settings.mainBar =
          {
            layer = "top";
            position = "top";
            height = 34;

            modules-left = ["hyprland/workspaces" "hyprland/window"];
            modules-center = ["clock"];
            # custom/power is gated on wlogout.enable: its on-click runs `wlogout`,
            # so without the package/menu it would be a dead button — drop it
            # entirely rather than render a broken one.
            modules-right =
              [
                "idle_inhibitor"
                "pulseaudio"
              ]
              ++ lib.optional cfg.laptop.enable "backlight"
              ++ ["network"]
              ++ lib.optional cfg.bluetooth.enable "bluetooth"
              ++ [
                "power-profiles-daemon"
                "cpu"
                "memory"
                "temperature"
              ]
              ++ lib.optional cfg.laptop.enable "battery"
              ++ lib.optional cfg.g502.enable "custom/mouse"
              ++ [
                "tray"
                "custom/theme"
              ]
              ++ lib.optional cfg.wlogout.enable "custom/power";

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

            network = {
              format-wifi = "{essid} ({signalStrength}%) 󰖩";
              format-ethernet = "{ipaddr}/{cidr} 󰈀";
              format-linked = "{ifname} (No IP) 󰈀";
              format-disconnected = "disconnected 󰖪";
              tooltip-format = "{ifname} via {gwaddr}";
              tooltip-format-wifi = "{essid} ({signalStrength}%) {ipaddr}";
              tooltip-format-ethernet = "{ifname} {ipaddr}";
              # Left: walker wifi scan/join picker (good at joining new networks,
              # which nm-connection-editor is not). The class arg is a sentinel that
              # matches no window — the picker shows a transient walker surface and
              # exits on select, so there's nothing to focus; fol just routes the
              # launch through the compositor (out of waybar's cgroup). Middle:
              # nm-connection-editor for editing saved profiles. Right: nmtui.
              on-click = "${fol} nm-dmenu-picker ${pkgs.networkmanager_dmenu}/bin/networkmanager_dmenu";
              on-click-middle = "${fol} nm-connection-editor ${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
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
          }
          # Laptop-only modules, behind the laptop gate (default on). Attr names
          # render sorted in the generated JSON, so merging them in here is
          # byte-identical to defining them inline.
          // lib.optionalAttrs cfg.laptop.enable {
            backlight = {
              format = "{percent}% {icon}";
              format-icons = ["󰃞" "󰃟" "󰃠"];
              on-scroll-up = "brightnessctl set 5%+";
              on-scroll-down = "brightnessctl set 5%-";
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
          }
          // lib.optionalAttrs cfg.g502.enable {
            # Live G502 profile + DPI (see g502Status in lib.nix). 2s interval.
            "custom/mouse" = {
              exec = "${g502Status}/bin/waybar-g502";
              return-type = "json";
              interval = 2;
              format = "{} 󰍽";
              on-click = "${fol} piper ${pkgs.piper}/bin/piper";
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
          ${lib.optionalString cfg.g502.enable "#custom-mouse,\n"}#custom-theme,
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
          ${lib.optionalString cfg.g502.enable "#custom-mouse    { color: @pink;      border-bottom: 2px solid @pink; }\n#custom-mouse.hidden { padding: 0; margin: 0; border-bottom: none; }\n"}#idle_inhibitor  { color: @green; }
          #idle_inhibitor.activated { color: @red; }
          #tray            { color: @subtext1; }
          #custom-theme    { color: @mauve; }
          #custom-power    { color: @red; margin-right: 8px; }

          #battery.warning      { color: @peach;  border-bottom-color: @peach; }
          #battery.critical     { color: @red;    border-bottom-color: @red; }
          #temperature.critical { color: @red;    border-bottom-color: @red; }
        '';
      };
    };

    # Keep the bar out of the other desktop sessions once uwsm moves it onto
    # the shared graphical-session.target (no-op without uwsm — see
    # lib.nix sessionGuard).
    systemd.user.services.waybar.Service = sessionGuard;
  };
}
