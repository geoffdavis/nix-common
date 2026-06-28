{
  description = "CHANGEME: one-line description of this nix config";

  inputs = {
    nix-common.url = "github:geoffdavis/nix-common";

    # Follow nix-common's pins so every host shares the same channel versions.
    # This template is a standalone home-manager (Linux) consumer. For a
    # nix-darwin host, follow nixpkgs-darwin / home-manager-darwin and add
    # `darwin.follows = "nix-common/darwin";` instead.
    nixpkgs.follows = "nix-common/nixpkgs-nixos";
    home-manager.follows = "nix-common/home-manager-nixos";
    lazyvim.follows = "nix-common/lazyvim";
  };

  outputs = {
    nix-common,
    nixpkgs,
    home-manager,
    lazyvim,
    ...
  }: {
    # CHANGEME: rename "user@hostname" and the ./hosts/hostname path.
    homeConfigurations."user@hostname" = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      extraSpecialArgs = {inherit lazyvim;};
      modules = [
        nix-common.homeModules.linux-headless-base
        nix-common.homeModules.neovim
        nix-common.homeModules.nas-cache
        ./hosts/hostname/home.nix
      ];
    };
  };
}
