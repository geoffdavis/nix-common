{
  description = "Shared nix modules and pinned inputs for personal multi-host configs";

  inputs = {
    # darwin channel — for nix-darwin (macOS) hosts
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    # nixos channel — for NixOS systems and standalone home-manager on Linux
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-26.05";

    # unstable channel — for individual packages that must track upstream
    # faster than the stable release allows (e.g. netbird, historically
    # frozen several minor versions behind on the stable channel). Consumers
    # follow this pin and cherry-pick packages from it; whole systems stay on
    # the stable channels.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager-darwin.url = "github:nix-community/home-manager/release-26.05";
    home-manager-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    home-manager-nixos.url = "github:nix-community/home-manager/release-26.05";
    home-manager-nixos.inputs.nixpkgs.follows = "nixpkgs-nixos";

    darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    lazyvim.url = "github:pfassina/lazyvim-nix";

    # OpenDeck (Stream Deck software) built from source. Deliberately NO
    # nixpkgs follows — upstream README warns of FOD hash mismatches when
    # the pin changes.
    opendeck-nix.url = "github:Kitt3120/opendeck-nix";

    # Stream Deck mute-button plugin for teams-for-linux (HM module + package).
    opendeck-teams-for-linux.url = "github:geoffdavis/opendeck-teams-for-linux";
    opendeck-teams-for-linux.inputs.nixpkgs.follows = "nixpkgs-nixos";

    # Prebuilt nix-index database — powers the shell command-not-found handler
    # (name the nixpkgs package providing a missing command) and comma (`,`,
    # run a program from nixpkgs without installing). Fetched prebuilt and
    # refreshed upstream weekly so hosts never run `nix-index` by hand. Wired
    # via homeModules.nix-index.
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs-nixos";
  };

  outputs = inputs: let
    inherit (inputs.nixpkgs-nixos) lib;
    systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    pkgsFor = system:
      if lib.hasSuffix "-darwin" system
      then inputs.nixpkgs-darwin.legacyPackages.${system}
      else inputs.nixpkgs-nixos.legacyPackages.${system};
    forAllSystems = f: lib.genAttrs systems (system: f (pkgsFor system));
  in {
    # Dev helper, single source of truth for the ci.yml pin rewrite. Consumers
    # call `nix run github:geoffdavis/nix-common#sync-pin` from their Taskfile
    # (after `nix flake update nix-common`) instead of carrying the shell
    # inline. It reads the *consumer's* flake.lock in CWD, so the locked rev —
    # not this flake's version — is what lands in ci.yml.
    apps = forAllSystems (pkgs: {
      sync-pin = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "sync-pin" ''
          set -eu
          ci="''${1:-.github/workflows/ci.yml}"
          if [ ! -f "$ci" ]; then
            echo "sync-pin: workflow file not found: $ci" >&2
            exit 1
          fi
          if [ ! -f flake.lock ]; then
            echo "sync-pin: flake.lock not found in $PWD" >&2
            exit 1
          fi
          sha=$(${pkgs.jq}/bin/jq -r '.nodes."nix-common".locked.rev' flake.lock)
          if [ -z "$sha" ] || [ "$sha" = "null" ]; then
            echo "sync-pin: could not read nix-common rev from flake.lock" >&2
            exit 1
          fi
          tmp=$(${pkgs.coreutils}/bin/mktemp "''${TMPDIR:-/tmp}/sync-pin.XXXXXXXX")
          ${pkgs.gnused}/bin/sed "s|geoffdavis/nix-common/\.github/workflows/lint\.yml@[a-f0-9]\{7,\}|geoffdavis/nix-common/.github/workflows/lint.yml@$sha|" "$ci" > "$tmp"
          if ! ${pkgs.gnugrep}/bin/grep -qF "geoffdavis/nix-common/.github/workflows/lint.yml@$sha" "$tmp"; then
            echo "sync-pin: sed did not produce the expected pin in $ci" >&2
            ${pkgs.coreutils}/bin/rm -f "$tmp"
            exit 1
          fi
          ${pkgs.coreutils}/bin/mv "$tmp" "$ci"
          echo "sync-pin: nix-common workflow pin -> $sha"
        ''}/bin/sync-pin";
      };
    });

    # Dev shell for building/iterating the teams-for-linux checkout that
    # homeModules.teams-for-linux's devOverlay consumes. The module FHS-wraps
    # the *output* of `npm run pack`; this shell provides the build-time
    # toolchain to produce it (the missing piece — without a C compiler the
    # native-module rebuild dies with "gcc: command not found").
    #
    #   nix develop github:geoffdavis/nix-common#teams-for-linux
    #   # or, from the checkout's parent dir, an .envrc with:
    #   #   use flake "$HOME/src/nix/nix-common#teams-for-linux"
    #
    # Linux-only: the dev workflow targets the NixOS host (birdrock).
    devShells = forAllSystems (
      pkgs:
        lib.optionalAttrs pkgs.stdenv.isLinux {
          teams-for-linux = pkgs.mkShell {
            # node-gyp / @electron/rebuild compile native modules (cbor-extract)
            # from source during `npm run pack`.
            nativeBuildInputs = with pkgs; [
              nodejs_22
              python3
              gcc
              gnumake
              pkg-config
              electron_42
            ];

            # Make the checkout's own node_modules/.bin/electron launch the
            # nixpkgs-wrapped Electron (matching package.json's pinned major 42)
            # for `npm run start:dev`. The npm shim joins this dir with
            # "electron", so point at the wrapper in $out/bin — NOT the raw
            # libexec binary, which SIGILLs without the wrapper's GTK/GIO/pixbuf/
            # sandbox environment.
            ELECTRON_OVERRIDE_DIST_PATH = "${pkgs.electron_42}/bin";

            shellHook = ''
              echo "teams-for-linux dev: node $(node --version), gcc $(gcc -dumpversion), electron ${pkgs.electron_42.version}"
              echo "  build:   npm run pack        (home-manager switch then picks up dist/linux-unpacked)"
              echo "  iterate: npm run start:dev   (--no-sandbox; the Nix store sandbox binary isn't SUID)"
            '';
          };
        }
    );

    # Scaffolding for the two most common "new thing" operations. See
    # docs/module-contract.md and templates/*/README.md.
    #   nix flake new -t github:geoffdavis/nix-common#consumer ./my-config
    #   nix flake init -t github:geoffdavis/nix-common#home-module
    templates = {
      consumer = {
        path = ./templates/consumer;
        description = "Standalone home-manager repo that consumes nix-common (flake, Taskfile, CI, pre-commit, AGENTS/CLAUDE).";
      };
      home-module = {
        path = ./templates/home-module;
        description = "Skeleton for a new shared home-manager module following the nix-common module contract.";
      };
      default = {
        path = ./templates/consumer;
        description = "Alias for the consumer template.";
      };
    };

    darwinModules.common = ./modules/darwin/common.nix;
    # Opt-in scheduled GC + store optimisation for Determinate-managed Macs
    # (nix.enable = false), where darwinModules.common's nix.gc is inert.
    darwinModules.determinate-gc = ./modules/darwin/determinate-gc.nix;
    # NAS binary cache + x86_64-linux remote builder for system-level consumers
    # (nix-darwin + NixOS). Same file — both platforms share these option
    # namespaces (nix.settings, nix.buildMachines, programs.ssh.extraConfig).
    darwinModules.nas-cache = ./modules/nas-cache.nix;
    nixosModules.common = ./modules/nixos/common.nix;
    # NAS binary cache for NixOS hosts (same file as darwinModules.nas-cache).
    nixosModules.nas-cache = ./modules/nas-cache.nix;
    nixosModules.onepassword = ./modules/nixos/onepassword.nix;
    nixosModules.nas-backup = ./modules/nixos/nas-backup.nix;
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
    homeModules.hyprland = ./modules/home/hyprland.nix;
    homeModules.linux-headless-base = ./modules/home/linux-headless-base.nix;
    homeModules.gnome-desktop-base = ./modules/home/gnome-desktop-base.nix;
    homeModules.unfree-desktop = ./modules/home/unfree-desktop.nix;
    homeModules.op-json-secrets = ./modules/home/op-json-secrets.nix;
    homeModules.op-file-secrets = ./modules/home/op-file-secrets.nix;
    # Needs flake inputs (the plugin's HM module), hence the import-with-args.
    homeModules.teams-for-linux = import ./modules/home/teams-for-linux.nix inputs;
    # Needs flake inputs (the prebuilt-database HM module), hence import-with-args.
    homeModules.nix-index = import ./modules/home/nix-index.nix inputs;
    homeModules.ai-tools = ./modules/home/ai-tools.nix;
    # docx2pdf via pipx — macOS only, requires Microsoft Word. opt-in per host.
    homeModules.doc-tools = ./modules/home/doc-tools.nix;
    homeModules.onepassword = ./modules/home/onepassword.nix;
    homeModules.terraform = ./modules/home/terraform.nix;
    homeModules.yazi = ./modules/home/yazi.nix;
    # NAS binary cache (substituter only) for standalone home-manager on
    # Linux. buildMachines is not a home-manager option; system-level
    # consumers should use nixosModules.nas-cache / darwinModules.nas-cache.
    homeModules.nas-cache = ./modules/home/nas-cache.nix;

    # The shared interactive zsh aliases/functions as a builder, so
    # SYSTEM-level consumers (nix-personal's headless NAS shell, where the
    # humans are FreeIPA users with no home-manager) can reuse the exact same
    # source home/zsh.nix does — no copy-paste drift. Call as
    #   nix-common.lib.zshInteractiveInit { inherit pkgs; profile = "nas"; }
    lib.zshInteractiveInit = import ./modules/shell/interactive-aliases.nix;
  };
}
