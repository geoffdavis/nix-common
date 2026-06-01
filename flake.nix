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
  };

  outputs = _: {
    darwinModules.common = ./modules/darwin/common.nix;
    nixosModules.common = ./modules/nixos/common.nix;
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
  };
}
