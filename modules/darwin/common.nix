# Shared nix-darwin config for every personal Mac.
# Per-host modules only need to set hostname-specific bits
# (homebrew brews/casks, etc.) on top of this.
{
  pkgs,
  lazyvim,
  darwin,
  ...
}: {
  system.stateVersion = 6;
  system.primaryUser = "geoff";

  # zsh sourcing of nix-darwin's environment changes.
  programs.zsh.enable = true;

  homebrew.enable = true;
  homebrew.onActivation.autoUpdate = true; # can slow darwin-rebuild down

  users.users.geoff = {
    name = "geoff";
    home = "/Users/geoff";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.geoff = {pkgs, ...}: {
      imports = [
        lazyvim.homeManagerModules.default
        ../home/cli-tools.nix
      ];
      home.stateVersion = "25.11";

      # darwin-rebuild is part of nix-darwin's flake (not in nixpkgs).
      # Put it on the user PATH so it works without /run/current-system/sw/bin.
      home.packages = [
        darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild
      ];

      programs.lazyvim = {
        enable = true;

        extras = {
          lang.nix.enable = true;
          lang.python = {
            enable = true;
            installDependencies = true;
            installRuntimeDependencies = true;
          };
          lang.go = {
            enable = true;
            installDependencies = true;
            installRuntimeDependencies = true;
          };
        };

        extraPackages = with pkgs; [
          nixd # Nix LSP
          alejandra # Nix formatter
        ];

        treesitterParsers = with pkgs.vimPlugins.nvim-treesitter-parsers; [
          wgsl # WebGPU Shading Language
          templ # Go templ files
        ];
      };
    };
  };
}
