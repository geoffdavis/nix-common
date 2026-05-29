{
  description = "Shared nix modules and pinned inputs for personal multi-host configs";

  inputs = {
    # darwin channel — for nix-darwin hosts (windansea, viasat-laptop)
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    # nixos channel — for NixOS hosts (birdrock) and Linux home configs (oceaneering)
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
    homeModules.cli-tools = ./modules/home/cli-tools.nix;
    homeModules.desktop-base = ./modules/home/desktop-base.nix;
    homeModules.git = ./modules/home/git.nix;
    homeModules.ssh = ./modules/home/ssh.nix;
    homeModules.gnome-desktop = ./modules/home/gnome-desktop.nix;
    homeModules.graphics = ./modules/home/graphics.nix;
    homeModules.linux-headless-base = ./modules/home/linux-headless-base.nix;
    homeModules.linux-desktop-base = ./modules/home/linux-desktop-base.nix;
    homeModules.unfree-desktop = ./modules/home/unfree-desktop.nix;
  };
}
