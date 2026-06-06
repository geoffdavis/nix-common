# teams-for-linux + OpenDeck on birdrock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the dev build of teams-for-linux plus OpenDeck and the published mute-button plugin on birdrock, implemented as shared nix-common modules consumed by nix-personal.

**Architecture:** nix-common (branch `gdavis/teams-opendeck`) gains two flake inputs (`opendeck-nix` source-build flake, `opendeck-teams-for-linux` plugin flake) and three exports: a re-exported OpenDeck NixOS module, a generic `op-file-secrets` home module (sibling of the existing `op-json-secrets`), and a `teams-for-linux` home module (app + devOverlay + mosquitto user broker + jq-merged `config.json` + plugin glue, all secrets from one `op://` reference). nix-personal pins its `nix-common` input to the dev branch and enables everything in a new `hosts/birdrock/teams.nix`. Spec: `docs/superpowers/specs/2026-06-05-teams-for-linux-opendeck-module-design.md` (same repo).

**Tech Stack:** Nix flakes, home-manager 25.11, mosquitto, 1Password CLI (`op`), jq, opendeck-nix (Tauri source build), teams-for-linux dev checkout (`npm run pack`).

**Verified facts (do not re-derive):**

- nix-common `flake.nix` currently has `outputs = _: {...}` — it must become `outputs = inputs: {...}` because two new exports need input access.
- `opendeck-nix.nixosModules.default` = module + overlay; the overlay injects `pkgs.opendeck` built from opendeck-nix's OWN nixpkgs pin (do NOT add `inputs.nixpkgs.follows` — upstream README forbids it, hash mismatches). x86_64-linux only — fine, birdrock is x86_64.
- The plugin flake exports `homeManagerModules.default` with options `programs.opendeck-teams-for-linux.{enable,package,settings}`; `settings` is TOML-typed, keys: `broker_host`, `broker_port`, `username`, `password_file`, `topic_prefix`, `microphone_topic`, `microphone_control_topic`, `in_call_topic`, `command_topic` (suffixes, not full topics).
- nixpkgs-25.11 has `teams-for-linux` 2.8.0 — fine as the default `package`; birdrock uses `devOverlay` anyway.
- nix-personal's birdrock is wired in `flake.nix` `nixosConfigurations.birdrock.modules` with `specialArgs = {inherit nix-common lazyvim catppuccin;}`; host files live at `hosts/birdrock/*.nix`; the username is `config.my.username` (set by nixosModules.common).
- HM activation runs with `op` on PATH on birdrock (system-level onepassword module); `op read` output's trailing newline is stripped by `$(...)`.
- The existing `op-json-secrets` module (`modules/home/op-json-secrets.nix`) is the pattern to mirror: list-typed top-level option, `lib.hm.dag.entryAfter ["writeBoundary"]` activation, skip-with-warning when `op` is absent.
- jq deep-merge (`.[0] * .[1]`) makes the config.json managed-keys merge and the op-json-secrets password patch order-independent (neither clobbers the other's keys).
- Lint/verify commands in both repos: `task fmt` (alejandra), `task lint` (pre-commit: alejandra+deadnix+statix), `task check` (nix flake check). nix-personal also has `task bump:common` (flake update nix-common + ci.yml lint pin sync — REQUIRED after changing the nix-common URL, the CI `verify-pin` check fails otherwise).

**Repos and branches:**

- nix-common: `~/src/nix/nix-common`, branch `gdavis/teams-opendeck` (exists, has the spec; work on it directly).
- nix-personal: `~/src/nix/nix-personal`, branch `gdavis/teams-opendeck` (create from main).

---

### Task 1: nix-common flake — new inputs and export wiring

**Files:**
- Modify: `~/src/nix/nix-common/flake.nix`

- [ ] **Step 1: Replace the full file content with:**

```nix
{
  description = "Shared nix modules and pinned inputs for personal multi-host configs";

  inputs = {
    # darwin channel — for nix-darwin (macOS) hosts
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    # nixos channel — for NixOS systems and standalone home-manager on Linux
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-25.11";

    home-manager-darwin.url = "github:nix-community/home-manager/release-25.11";
    home-manager-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    home-manager-nixos.url = "github:nix-community/home-manager/release-25.11";
    home-manager-nixos.inputs.nixpkgs.follows = "nixpkgs-nixos";

    darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    lazyvim.url = "github:pfassina/lazyvim-nix";

    # OpenDeck (Stream Deck software) built from source. Deliberately NO
    # nixpkgs follows — upstream README warns of FOD hash mismatches when
    # the pin changes.
    opendeck-nix.url = "github:Kitt3120/opendeck-nix";

    # Stream Deck mute-button plugin for teams-for-linux (HM module + package).
    opendeck-teams-for-linux.url = "github:geoffdavis/opendeck-teams-for-linux";
    opendeck-teams-for-linux.inputs.nixpkgs.follows = "nixpkgs-nixos";
  };

  outputs = inputs: {
    darwinModules.common = ./modules/darwin/common.nix;
    nixosModules.common = ./modules/nixos/common.nix;
    nixosModules.onepassword = ./modules/nixos/onepassword.nix;
    # OpenDeck app + udev rules + pkgs.opendeck overlay (programs.opendeck.enable).
    nixosModules.opendeck = inputs.opendeck-nix.nixosModules.default;
    homeModules.cli-tools = ./modules/home/cli-tools.nix;
    homeModules.neovim = ./modules/home/neovim.nix;
    homeModules.profile = ./modules/home/profile.nix;
    homeModules.desktop-base = ./modules/home/desktop-base.nix;
    homeModules.git = ./modules/home/git.nix;
    homeModules.zsh = ./modules/home/zsh.nix;
    homeModules.ssh = ./modules/home/ssh.nix;
    homeModules.gnome-dconf = ./modules/home/gnome-dconf.nix;
    homeModules.graphics = ./modules/home/graphics.nix;
    homeModules.linux-headless-base = ./modules/home/linux-headless-base.nix;
    homeModules.gnome-desktop-base = ./modules/home/gnome-desktop-base.nix;
    homeModules.unfree-desktop = ./modules/home/unfree-desktop.nix;
    homeModules.op-json-secrets = ./modules/home/op-json-secrets.nix;
    homeModules.op-file-secrets = ./modules/home/op-file-secrets.nix;
    # Needs flake inputs (the plugin's HM module), hence the import-with-args.
    homeModules.teams-for-linux = import ./modules/home/teams-for-linux.nix inputs;
    homeModules.ai-tools = ./modules/home/ai-tools.nix;
    homeModules.onepassword = ./modules/home/onepassword.nix;
    homeModules.terraform = ./modules/home/terraform.nix;
  };
}
```

- [ ] **Step 2: Lock the new inputs**

Run: `cd ~/src/nix/nix-common && nix flake lock`
Expected: lockfile gains `opendeck-nix` and `opendeck-teams-for-linux` nodes; no errors.

- [ ] **Step 3: Note — flake check will fail until Tasks 2–3 create the two module files.** Verify only evaluation of the lock here:

Run: `nix flake metadata --json | nix run nixpkgs#jq -- -r '.locks.nodes | keys[]' | grep opendeck`
Expected: both `opendeck-nix` and `opendeck-teams-for-linux` listed.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(flake): add opendeck-nix and opendeck-teams-for-linux inputs, expose opendeck module"
```

---

### Task 2: nix-common — `op-file-secrets` home module

**Files:**
- Create: `~/src/nix/nix-common/modules/home/op-file-secrets.nix`

- [ ] **Step 1: Write the module** (mirrors op-json-secrets' contract):

```nix
# Home-manager module: write 1Password secrets to standalone files at
# activation time.
#
# Sibling of op-json-secrets for non-JSON consumers — password files, token
# files — anywhere an application expects a secret as the entire file
# content.
#
# ## Usage
#
#   op-file-secrets = [
#     {
#       dest = "${config.home.homeDirectory}/.config/myapp/password";
#       ref = "op://MyVault/MyItem/password";
#       mode = "0600"; # default
#     }
#   ];
#
# ## Degradation contract (same as op-json-secrets)
#
# If `op` is not in PATH, or a read fails (locked vault, missing item), the
# affected file is skipped with a warning on stderr; `home-manager switch`
# never fails because of it. Existing file contents are left untouched on
# skip — stale secrets, not broken activations.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.op-file-secrets;

  fileScript = entry: ''
    _val=$($_op read ${lib.escapeShellArg entry.ref} 2>/dev/null) || _val=""
    if [ -n "$_val" ]; then
      _f=${lib.escapeShellArg entry.dest}
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$_f")"
      (umask 077; printf '%s' "$_val" > "$_f")
      ${pkgs.coreutils}/bin/chmod ${lib.escapeShellArg entry.mode} "$_f"
    else
      echo "[op-file-secrets] skipping ${entry.ref} (unavailable or empty)" >&2
    fi
  '';
in {
  options.op-file-secrets = lib.mkOption {
    default = [];
    description = ''
      Files whose entire content is a secret fetched from 1Password during
      `home-manager switch`.
    '';
    type = lib.types.listOf (lib.types.submodule {
      options = {
        dest = lib.mkOption {
          description = "Absolute path of the file to write.";
          type = lib.types.str;
        };
        ref = lib.mkOption {
          description = "1Password secret reference: `op://<vault>/<item>/<field>`.";
          type = lib.types.str;
        };
        mode = lib.mkOption {
          default = "0600";
          description = "File mode (chmod argument).";
          type = lib.types.str;
        };
      };
    });
  };

  config = lib.mkIf (cfg != []) {
    home.activation.opFileSecrets = lib.hm.dag.entryAfter ["writeBoundary"] ''
      _op=$(command -v op 2>/dev/null) || true
      if [ -z "$_op" ]; then
        echo "[op-file-secrets] 1Password CLI not in PATH — skipping secret files" >&2
      else
        ${lib.concatMapStrings fileScript cfg}
      fi
    '';
  };
}
```

- [ ] **Step 2: Lint and check**

Run: `cd ~/src/nix/nix-common && task fmt && task lint && task check`
Expected: alejandra may reformat (re-run `git diff` to sanity-check, no logic changes); lint clean; `nix flake check` passes (teams-for-linux module file still missing is OK only if Task 3 hasn't run — if check fails on the missing `./modules/home/teams-for-linux.nix`, defer `task check` to Task 3 Step 3 and run only `task fmt && task lint` here).

- [ ] **Step 3: Commit**

```bash
git add modules/home/op-file-secrets.nix
git commit -m "feat(home): add op-file-secrets module (1Password secrets to standalone files)"
```

---

### Task 3: nix-common — `teams-for-linux` home module

**Files:**
- Create: `~/src/nix/nix-common/modules/home/teams-for-linux.nix`

- [ ] **Step 1: Write the module:**

```nix
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
  devWrapper = pkgs.writeShellScriptBin "teams-for-linux" ''
    exec "${cfg.devOverlay.checkoutPath}/dist/linux-unpacked/teams-for-linux" \
      --user-data-dir="${configDir}" \
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
        username = cfg.mqtt.username;
        clientId = "teams-for-linux";
        topicPrefix = cfg.mqtt.topicPrefix;
        statusTopic = cfg.mqtt.statusTopic;
        commandTopic = cfg.mqtt.commandTopic;
        mediaTopics = cfg.mqtt.mediaTopics;
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
      type = (pkgs.formats.json {}).type;
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
      home.packages = [pkgs.mosquitto];

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

      # Deep-merge the managed (non-secret) keys into config.json, preserving
      # everything else. Order vs. the op-json-secrets password patch is
      # irrelevant: jq's `*` merge never drops the other writer's keys.
      home.activation.teamsForLinuxConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg configDir}
        [ -f ${lib.escapeShellArg configJson} ] || echo '{}' > ${lib.escapeShellArg configJson}
        _tmp=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' ${lib.escapeShellArg configJson} ${managedConfigFile} > "$_tmp" \
          && ${pkgs.coreutils}/bin/mv "$_tmp" ${lib.escapeShellArg configJson}
        ${pkgs.coreutils}/bin/chmod 600 ${lib.escapeShellArg configJson}
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

      # The broker passwordfile is HASHED (mosquitto_passwd), so
      # op-file-secrets can't produce it — dedicated op step, same
      # degradation contract.
      home.activation.teamsForLinuxBrokerPassword = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _op=$(command -v op 2>/dev/null) || true
        if [ -z "$_op" ]; then
          echo "[teams-for-linux] op not in PATH — skipping mosquitto passwordfile" >&2
        else
          _pw=$($_op read ${lib.escapeShellArg cfg.mqtt.passwordRef} 2>/dev/null) || _pw=""
          if [ -n "$_pw" ]; then
            ${pkgs.coreutils}/bin/mkdir -p \
              "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg mosquittoPasswordFile})"
            ${pkgs.mosquitto}/bin/mosquitto_passwd -b -c \
              ${lib.escapeShellArg mosquittoPasswordFile} \
              ${lib.escapeShellArg cfg.mqtt.username} "$_pw"
            ${pkgs.coreutils}/bin/chmod 600 ${lib.escapeShellArg mosquittoPasswordFile}
          else
            echo "[teams-for-linux] cannot read mqtt.passwordRef — skipping mosquitto passwordfile" >&2
          fi
        fi
      '';
    })

    (lib.mkIf cfg.opendeckPlugin.enable {
      programs.opendeck-teams-for-linux = {
        enable = true;
        settings = {
          username = cfg.mqtt.username;
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
```

- [ ] **Step 2: Lint and check**

Run: `cd ~/src/nix/nix-common && task fmt && task lint && task check`
Expected: all clean (flake check now finds every exported module file).

- [ ] **Step 3: Commit and push the branch**

```bash
git add modules/home/teams-for-linux.nix
git commit -m "feat(home): add teams-for-linux module (app, devOverlay, mqtt broker, opendeck plugin)"
git push -u origin gdavis/teams-opendeck
```

---

### Task 4: nix-personal — dev-branch pin

**Files:**
- Modify: `~/src/nix/nix-personal/flake.nix` (line 13)

- [ ] **Step 1: Branch**

```bash
cd ~/src/nix/nix-personal
git checkout main && git pull
git checkout -b gdavis/teams-opendeck
```

- [ ] **Step 2: Pin nix-common to the dev branch** — change line 13:

```nix
    nix-common.url = "github:geoffdavis/nix-common/gdavis/teams-opendeck";
```

- [ ] **Step 3: Update the lock AND the CI lint pin** (verify-pin fails without the sync):

Run: `task bump:common`
Expected: `flake.lock`'s nix-common rev = the pushed dev-branch HEAD; `.github/workflows/ci.yml` lint pin updated to match.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock .github/workflows/ci.yml
git commit -m "chore: pin nix-common to gdavis/teams-opendeck for teams/opendeck rollout"
```

---

### Task 5: nix-personal — birdrock teams.nix

**Files:**
- Create: `~/src/nix/nix-personal/hosts/birdrock/teams.nix`
- Modify: `~/src/nix/nix-personal/flake.nix` (birdrock modules list, after `./hosts/birdrock/default.nix`)

- [ ] **Step 1: Write `hosts/birdrock/teams.nix`:**

```nix
# hosts/birdrock/teams.nix — Microsoft Teams (dev build) + MQTT mute-button
# stack + OpenDeck, via nix-common's shared modules. Design spec lives in
# nix-common: docs/superpowers/specs/2026-06-05-teams-for-linux-opendeck-module-design.md
#
# Secrets: create the 1Password item once —
#   op item create --vault Private --category login \
#     --title "Teams for Linux MQTT" --generate-password=24,letters,digits
# Dev build: cd ~/src/teams-for-linux && npm run pack (after each pull).
{
  config,
  nix-common,
  ...
}: let
  inherit (config.my) username;
in {
  # OpenDeck (Stream Deck software) from source via opendeck-nix (pinned in
  # nix-common) + its udev rules; works whenever a deck is plugged in.
  imports = [nix-common.nixosModules.opendeck];
  programs.opendeck.enable = true;

  home-manager.users.${username} = {
    imports = [nix-common.homeModules.teams-for-linux];

    teams-for-linux = {
      enable = true;
      # Run the local checkout's dev build (MQTT-features branch).
      devOverlay.enable = true;
      mqtt.passwordRef = "op://Private/Teams for Linux MQTT/password";
      opendeckPlugin.enable = true;
      # GPU on native Wayland (no blur at fractional scale factors).
      extraConfig.disableGpu = false;
    };
  };
}
```

- [ ] **Step 2: Add the module to birdrock in `flake.nix`** — in `nixosConfigurations.birdrock.modules`, insert after `./hosts/birdrock/default.nix`:

```nix
        ./hosts/birdrock/teams.nix
```

- [ ] **Step 3: Lint**

Run: `cd ~/src/nix/nix-personal && task fmt && task lint`
Expected: clean.

- [ ] **Step 4: Full evaluation + build gate (no activation yet).** This compiles OpenDeck from source the first time — expect 10–30 minutes; run in the background and monitor:

Run:
```bash
nix build .#nixosConfigurations.birdrock.config.system.build.toplevel \
  --override-input nix-common ~/src/nix/nix-common --accept-flake-config
```
Expected: builds to completion (`./result` symlink). Evaluation errors here mean module bugs — fix in nix-common (`~/src/nix/nix-common`, commit there) and re-run; `--override-input` picks up local changes without push/lock cycles.

- [ ] **Step 5: Commit**

```bash
git add hosts/birdrock/teams.nix flake.nix
git commit -m "feat(birdrock): teams-for-linux dev build + mqtt stack + opendeck"
```

---

### Task 6: Secrets + dev build prerequisites (interactive)

**CONFIRM WITH GEOFF before creating the 1Password item.**

- [ ] **Step 1: Create the 1Password item** (needs an unlocked vault):

```bash
op item create --vault Private --category login \
  --title "Teams for Linux MQTT" \
  --generate-password=24,letters,digits \
  username=teams-for-linux
op read "op://Private/Teams for Linux MQTT/password" >/dev/null && echo SECRET-OK
```
Expected: `SECRET-OK`.

- [ ] **Step 2: Build the teams-for-linux dev binary**

Run:
```bash
cd ~/src/teams-for-linux && npm install && npm run pack
ls dist/linux-unpacked/teams-for-linux
```
Expected: the binary exists. (The checkout is on the MQTT-features branch `gdavis/configurable-mqtt-topics`.)

---

### Task 7: Activate and verify on birdrock

- [ ] **Step 1: Switch**

Run:
```bash
cd ~/src/nix/nix-personal
sudo nixos-rebuild switch --flake .#birdrock \
  --override-input nix-common ~/src/nix/nix-common --accept-flake-config
```
Expected: activation completes; no `[op-…] skipping` warnings (vault unlocked from Task 6).

- [ ] **Step 2: Verify the secret artifacts**

Run:
```bash
ls -l ~/.config/mosquitto/passwordfile ~/.config/opendeck-teams-for-linux/password
nix run nixpkgs#jq -- -r '.mqtt | {enabled, brokerUrl, username, password: (if .password != null and .password != "" then "(set)" else "MISSING" end)}' ~/.config/teams-for-linux/config.json
```
Expected: both files 0600; jq shows `enabled: true`, localhost URL, username, password `(set)`.

- [ ] **Step 3: Broker up + authenticated subscribe**

Run:
```bash
systemctl --user status mosquitto --no-pager | head -5
timeout 5 mosquitto_sub -u teams-for-linux \
  -P "$(cat ~/.config/opendeck-teams-for-linux/password)" -t 'teams/#' -v; echo "sub exit: $?"
```
Expected: service `active (running)`; subscribe holds until the 5s timeout (exit 124) with no auth error.

- [ ] **Step 4: teams-for-linux dev build connects**

Launch "Teams for Linux" from the app launcher (or `teams-for-linux` in a terminal). Expected: dev binary starts (it's the wrapper on PATH), log shows `[MQTT] Successfully connected to broker`; with a `mosquitto_sub` running, a retained JSON status message appears on `teams/status` after login.

- [ ] **Step 5: OpenDeck + plugin**

Run `opendeck` (or launch from the app menu). Expected: OpenDeck starts; the "Teams for Linux" plugin appears in its plugins view (installed at `~/.config/opendeck/plugins/com.geoffdavis.teamsforlinux.sdPlugin` as an HM symlink); OpenDeck's plugin log shows the plugin's `mqtt connected` line. With a Stream Deck attached: add "Toggle Mute (Teams)" to a key → shows `OFF`; drive it with a real Teams call (MIC/MUTED, press toggles). Without a deck: the running-plugin log lines are the success criterion; the key test happens whenever a deck is next attached.

- [ ] **Step 6: Record results** — note any deviations/fixes in the commit messages that resolve them; this task produces no commit when everything passes.

---

### Task 8: Merge rollout

**CONFIRM WITH GEOFF before merging (squash merges, protected branches).**

- [ ] **Step 1: nix-common PR**

```bash
cd ~/src/nix/nix-common
git push
gh pr create --title "feat: shared teams-for-linux + OpenDeck modules" \
  --body "Adds opendeck-nix + opendeck-teams-for-linux inputs, nixosModules.opendeck re-export, homeModules.op-file-secrets, and homeModules.teams-for-linux (app + devOverlay + mosquitto + config.json secrets + plugin glue). Spec + plan in docs/superpowers/. Verified on birdrock via nix-personal dev branch."
gh pr checks --watch
```
Expected: lint workflow green. Squash-merge once green (GitGuardian may false-positive on "onepassword" identifiers — it is not a required check).

- [ ] **Step 2: nix-personal — restore canonical pin onto merged main**

```bash
cd ~/src/nix/nix-personal
# restore the canonical URL (drop the branch suffix) in flake.nix line 13:
#   nix-common.url = "github:geoffdavis/nix-common";
task bump:common
git add flake.nix flake.lock .github/workflows/ci.yml
git commit -m "chore: point nix-common back at main (teams/opendeck merged)"
git push -u origin gdavis/teams-opendeck
gh pr create --title "feat(birdrock): teams-for-linux dev build + mqtt stack + opendeck" \
  --body "Consumes nix-common's new teams-for-linux/opendeck modules on birdrock. Verified locally (broker, dev app, plugin)."
gh pr checks --watch
```
Expected: CI green incl. verify-pin. Squash-merge.

- [ ] **Step 3: Final switch from main** (confirms the merged state matches what was verified):

```bash
cd ~/src/nix/nix-personal && git checkout main && git pull
sudo nixos-rebuild switch --flake .#birdrock --accept-flake-config
```
Expected: no-op or trivial activation; stack still healthy (repeat Task 7 Step 3 spot-check).

---

### Follow-up (separate, in the plugin repo's docs)

With the shared module proven on birdrock, the work repo's migration (its
"Follow-up B") becomes: consume these same nix-common modules, set
`devOverlay.checkoutPath`/`extraConfig`/`passwordRef` to the work values, and
delete its local Python plugin + module. Plan that in the work repo when
ready.
