# Home-manager module: Microsoft Teams (teams-for-linux) with MQTT
# mute-button integration and optional OpenDeck plugin wiring.
#
# Generalized from the work-host setup so any host can consume it:
#   - app:    nixpkgs package, or a local dev build via devOverlay
#   - broker: localhost-only mosquitto user service with password auth
#   - config.json: module-owned mqtt keys + host extraConfig, jq deep-merged
#     so unmanaged keys survive; the password is patched via op-json-secrets
#   - plugin: wires programs.opendeck-teams-for-linux (published flake)
#
# Secrets: ONE op:// reference (mqtt.passwordRef) feeds three artifacts at
# activation — config.json's .mqtt.password, the hashed mosquitto
# passwordfile, and the plugin's password file. Every op step skips with a
# warning (never fails the switch) when `op` or the vault is unavailable.
#
# Exported from the flake as `import ./teams-for-linux.nix inputs` because
# the plugin's HM module comes from a flake input.
inputs: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.teams-for-linux;

  configDir = "${config.home.homeDirectory}/.config/teams-for-linux";
  configJson = "${configDir}/config.json";
  mosquittoPasswordFile = "${config.home.homeDirectory}/.config/mosquitto/passwordfile";
  pluginPasswordFile = "${config.home.homeDirectory}/.config/opendeck-teams-for-linux/password";

  # Dev build: electron-builder's renamed binary in the checkout. The process
  # name then matches StartupWMClass (and any 1Password custom_allowed_browsers
  # entry). Build first: cd <checkoutPath> && npm run pack
  devBin = "${cfg.devOverlay.checkoutPath}/dist/linux-unpacked/teams-for-linux";

  # Flags mirroring the nixpkgs package wrapper. WaylandWindowDecorations is
  # the load-bearing one: GNOME's Wayland compositor draws no server-side
  # decorations, so without it the window has no minimize/maximize controls
  # (only a close button) and an unthemed frame. All four are safe no-ops
  # under X11, so we pass them unconditionally rather than gating on a
  # session env var (NIXOS_OZONE_WL is unset on non-NixOS Wayland sessions).
  devFlags = "--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations,WebRTCPipeWireCapturer --enable-wayland-ime=true";

  # The checkout binary is a prebuilt (FHS) Electron. On NixOS there is no
  # /lib64/ld-linux for it to run against (stub-ld refuses), so it must run
  # inside an FHS sandbox. But that sandbox binds its own /usr over the host's
  # — hiding system fonts and the GTK/icon/cursor themes the window frame needs
  # — which on a normal FHS distro (Ubuntu, etc.) just breaks desktop
  # integration for no benefit. So: FHS-wrap only where required (useFHS),
  # otherwise run the binary directly against the host. The FHS path also
  # bundles fonts/themes the appimage default set omits.
  devWrapper =
    if cfg.devOverlay.useFHS
    then
      pkgs.buildFHSEnv (pkgs.appimageTools.defaultFhsEnvArgs
        // {
          name = "teams-for-linux";
          targetPkgs = p:
            (pkgs.appimageTools.defaultFhsEnvArgs.targetPkgs p)
            ++ (with p; [
              dejavu_fonts
              liberation_ttf
              noto-fonts
              gnome-themes-extra
              adwaita-icon-theme
            ]);
          runScript = pkgs.writeShellScript "teams-for-linux-dev" ''
            exec "${devBin}" \
              --user-data-dir="${configDir}" \
              ${devFlags} \
              "$@"
          '';
        })
    else
      # Plain wrapper script — not makeWrapper, which build-time-asserts the
      # target is executable, and devBin lives under $HOME (invisible to the
      # build sandbox). writeShellScriptBin just emits bin/teams-for-linux.
      #
      # Strip the nix library/GL env before exec. devBin is a *system* FHS
      # Electron built against the host glibc/Mesa. A nixGL-wrapped Wayland
      # session (e.g. non-NixOS Hyprland) leaks nix LD_LIBRARY_PATH (nix
      # alsa-lib pulling nix glibc) and the Mesa-loader vars into children; the
      # system binary then can't resolve the newer GLIBC symbols and fails to
      # start at all. Clearing them makes it use the host libraries it was built
      # for. Harmless no-op on hosts without the leak. NOT applied to the FHS
      # branch above, whose sandbox supplies its own LD_LIBRARY_PATH.
      pkgs.writeShellScriptBin "teams-for-linux" ''
        exec ${pkgs.coreutils}/bin/env \
          -u LD_LIBRARY_PATH -u __EGL_VENDOR_LIBRARY_FILENAMES \
          -u LIBGL_DRIVERS_PATH -u LIBVA_DRIVERS_PATH -u GBM_BACKENDS_PATH \
          "${devBin}" \
          --user-data-dir="${configDir}" \
          ${devFlags} \
          "$@"
      '';

  devDesktopEntry = pkgs.writeText "teams-for-linux.desktop" ''
    [Desktop Entry]
    Categories=Chat;Network;Office
    Comment=Unofficial client for Microsoft Teams for Linux (dev build)
    Exec=${devWrapper}/bin/teams-for-linux %U
    Icon=${cfg.devOverlay.checkoutPath}/build/icons/256x256.png
    MimeType=x-scheme-handler/msteams
    Name=Teams for Linux
    StartupWMClass=teams-for-linux
    Terminal=false
    Type=Application
  '';

  # Module-owned, non-secret config.json keys. extraConfig wins on conflict.
  # The password is deliberately absent — op-json-secrets patches it.
  managedConfig =
    lib.recursiveUpdate {
      mqtt = {
        enabled = true;
        brokerUrl = "mqtt://127.0.0.1:1883";
        clientId = "teams-for-linux";
        inherit (cfg.mqtt) username topicPrefix statusTopic commandTopic mediaTopics;
      };
    }
    cfg.extraConfig;
  managedConfigFile =
    pkgs.writeText "teams-for-linux-managed.json" (builtins.toJSON managedConfig);
in {
  imports = [
    ./op-json-secrets.nix
    ./op-file-secrets.nix
    inputs.opendeck-teams-for-linux.homeManagerModules.default
  ];

  options.teams-for-linux = {
    enable = lib.mkEnableOption "teams-for-linux with MQTT mute-button integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.teams-for-linux;
      defaultText = lib.literalExpression "pkgs.teams-for-linux";
      description = "Base teams-for-linux package (not installed when devOverlay.enable).";
    };

    devOverlay = {
      enable = lib.mkEnableOption "local dev build instead of the package";
      checkoutPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/src/teams-for-linux";
        description = ''
          Absolute path to the teams-for-linux git checkout.
          Build it first: cd <checkoutPath> && npm run pack
        '';
      };
      useFHS = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run the prebuilt dev binary inside an FHS (bubblewrap) sandbox.
          Required on NixOS, where the binary has no host /lib64/ld-linux to
          run against. Set false on a normal FHS distro (Ubuntu, etc.):
          running the binary directly avoids shadowing the host's /usr, so the
          app inherits system fonts, GTK/icon/cursor themes, and window-manager
          decorations instead of the sandbox's minimal set.
        '';
      };
    };

    mqtt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run the localhost mosquitto broker and manage config.json's mqtt
          block (password via 1Password at activation).
        '';
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "teams-for-linux";
        description = "MQTT broker username.";
      };
      passwordRef = lib.mkOption {
        type = lib.types.str;
        example = "op://Private/Teams for Linux MQTT/password";
        description = "1Password reference for the broker password.";
      };
      topicPrefix = lib.mkOption {
        type = lib.types.str;
        default = "teams";
        description = "MQTT topic prefix.";
      };
      statusTopic = lib.mkOption {
        type = lib.types.str;
        default = "status";
        description = "Presence status topic (under the prefix).";
      };
      commandTopic = lib.mkOption {
        type = lib.types.str;
        default = "command";
        description = "Inbound command topic (under the prefix).";
      };
      mediaTopics = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          inCall = "in-call";
          incomingCall = "incoming-call";
          camera = "camera";
          microphone = "microphone";
          microphoneControl = "microphone/control";
          screenSharing = "screen-sharing";
        };
        description = "teams-for-linux mqtt.mediaTopics (topic suffixes).";
      };
    };

    opendeckPlugin.enable =
      lib.mkEnableOption "OpenDeck mute-button plugin (opendeck-teams-for-linux)";

    extraConfig = lib.mkOption {
      inherit ((pkgs.formats.json {})) type;
      default = {};
      example = {disableGpu = false;};
      description = ''
        Host-specific config.json keys, deep-merged OVER the module-owned
        ones. Keys outside the managed set are preserved either way.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages =
        lib.optional (!cfg.devOverlay.enable) cfg.package
        ++ lib.optional cfg.devOverlay.enable devWrapper;

      # ~/.local/share/applications/ shadows the system desktop entry.
      home.file.".local/share/applications/teams-for-linux.desktop" =
        lib.mkIf cfg.devOverlay.enable {source = devDesktopEntry;};
    }

    (lib.mkIf cfg.mqtt.enable {
      home = {
        packages = [pkgs.mosquitto];

        # Deep-merge the managed (non-secret) keys into config.json, preserving
        # everything else. Order vs. the op-json-secrets password patch is
        # irrelevant: jq's `*` merge never drops the other writer's keys.
        activation.teamsForLinuxConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
            ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg configDir}
          [ -f ${lib.escapeShellArg configJson} ] || echo '{}' > ${lib.escapeShellArg configJson}
          _tmp=$(${pkgs.coreutils}/bin/mktemp)
            ${pkgs.jq}/bin/jq -s '.[0] * .[1]' ${lib.escapeShellArg configJson} ${managedConfigFile} > "$_tmp" \
            && ${pkgs.coreutils}/bin/mv "$_tmp" ${lib.escapeShellArg configJson}
            ${pkgs.coreutils}/bin/chmod 600 ${lib.escapeShellArg configJson}
        '';

        # The broker passwordfile is HASHED (mosquitto_passwd), so
        # op-file-secrets can't produce it — dedicated op step, same
        # degradation contract.
        activation.teamsForLinuxBrokerPassword = lib.hm.dag.entryAfter ["writeBoundary"] ''
          _op=$(command -v op 2>/dev/null) || true
          # Activations run with a minimal PATH that often lacks op — a HM-as-NixOS
          # module, or standalone HM on a non-NixOS host. Fall back to well-known
          # setgid-shim locations across OSes: the NixOS wrappers, plus /usr/bin/op
          # (the Ubuntu/Debian 1Password desktop-CLI integration shim) and a
          # /usr/local manual-install path.
          if [ -z "$_op" ]; then
            for _c in /run/wrappers/bin/op /run/current-system/sw/bin/op /etc/profiles/per-user/"$USER"/bin/op /usr/bin/op /usr/local/bin/op; do
              if [ -x "$_c" ]; then
                _op="$_c"
                break
              fi
            done
          fi
          if [ -z "$_op" ]; then
            echo "[teams-for-linux] op not in PATH — skipping mosquitto passwordfile" >&2
          else
            _pw=$($_op read ${lib.escapeShellArg cfg.mqtt.passwordRef} 2>/dev/null) || _pw=""
            if [ -n "$_pw" ]; then
            ${pkgs.coreutils}/bin/mkdir -p \
                "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg mosquittoPasswordFile})"
              # mosquitto 2.x (nixos 26.05) makes `mosquitto_passwd -c` refuse to
              # overwrite an existing file ("Unable to open file ... for writing.
              # File exists."), which fails activation on every switch after the
              # first. Remove it first so -c always writes a fresh single-user
              # hash file (the password is re-read from 1Password each run).
            ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg mosquittoPasswordFile}
            ${pkgs.mosquitto}/bin/mosquitto_passwd -b -c \
            ${lib.escapeShellArg mosquittoPasswordFile} \
            ${lib.escapeShellArg cfg.mqtt.username} "$_pw"
            ${pkgs.coreutils}/bin/chmod 600 ${lib.escapeShellArg mosquittoPasswordFile}
            else
              echo "[teams-for-linux] cannot read mqtt.passwordRef — skipping mosquitto passwordfile" >&2
            fi
          fi
        '';
      };

      systemd.user.services.mosquitto = {
        Unit = {
          Description = "Mosquitto MQTT broker (user, localhost-only)";
          After = ["network.target"];
        };
        Install.WantedBy = ["default.target"];
        Service = {
          ExecStart = "${pkgs.mosquitto}/bin/mosquitto -c %h/.config/mosquitto/mosquitto.conf";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };

      xdg.configFile."mosquitto/mosquitto.conf".text = ''
        listener 1883 127.0.0.1
        allow_anonymous false
        password_file ${mosquittoPasswordFile}
        persistence false
        log_dest stderr
      '';

      op-json-secrets = [
        {
          dest = configJson;
          patches = [
            {
              path = ".mqtt.password";
              ref = cfg.mqtt.passwordRef;
            }
          ];
        }
      ];
    })

    (lib.mkIf cfg.opendeckPlugin.enable {
      programs.opendeck-teams-for-linux = {
        enable = true;
        settings = {
          inherit (cfg.mqtt) username;
          password_file = pluginPasswordFile;
          topic_prefix = cfg.mqtt.topicPrefix;
          microphone_topic = cfg.mqtt.mediaTopics.microphone;
          microphone_control_topic = cfg.mqtt.mediaTopics.microphoneControl;
          in_call_topic = cfg.mqtt.mediaTopics.inCall;
          command_topic = cfg.mqtt.commandTopic;
        };
      };

      op-file-secrets = [
        {
          dest = pluginPasswordFile;
          ref = cfg.mqtt.passwordRef;
        }
      ];
    })
  ]);
}
