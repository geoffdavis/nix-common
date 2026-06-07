{
  description = "Shared nix modules and pinned inputs for personal multi-host configs";

  inputs = {
    # darwin channel — for nix-darwin (macOS) hosts
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    # nixos channel — for NixOS systems and standalone home-manager on Linux
    nixpkgs-nixos.url = "github:NixOS/nixpkgs/nixos-25.11";

    # unstable channel — for individual packages that must track upstream
    # faster than the stable release allows (e.g. netbird, frozen at 0.60.x
    # on 25.11 while upstream ships 0.7x). Consumers follow this pin and
    # cherry-pick packages from it; whole systems stay on the stable channels.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

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
    # NAS binary cache + x86_64-linux remote builder for system-level consumers
    # (nix-darwin + NixOS). Same file — both platforms share these option
    # namespaces (nix.settings, nix.buildMachines, programs.ssh.extraConfig).
    darwinModules.nas-cache = ./modules/nas-cache.nix;
    nixosModules.common = ./modules/nixos/common.nix;
    # NAS binary cache for NixOS hosts (same file as darwinModules.nas-cache).
    nixosModules.nas-cache = ./modules/nas-cache.nix;
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
    # NAS binary cache (substituter only) for standalone home-manager on
    # Linux. buildMachines is not a home-manager option; system-level
    # consumers should use nixosModules.nas-cache / darwinModules.nas-cache.
    homeModules.nas-cache = ./modules/home/nas-cache.nix;
  };
}
