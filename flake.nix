{
  description = "Shared nix modules and pinned inputs for personal multi-host configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

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
    homeModules.linux-desktop-base = ./modules/home/linux-desktop-base.nix;
    homeModules.unfree-desktop = ./modules/home/unfree-desktop.nix;
  };
}
