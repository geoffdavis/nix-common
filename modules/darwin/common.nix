# Shared nix-darwin config for every personal Mac.
# Per-host modules set `my.username` (default "geoff") and any hostname-
# specific bits (homebrew brews/casks, etc.) on top of this.
{
  config,
  lib,
  lazyvim,
  darwin,
  ...
}: let
  inherit (config.my) username;
  unfreePackageNames = import ../shared/unfree-package-names.nix;
in {
  options.my.username = lib.mkOption {
    type = lib.types.str;
    default = "geoff";
    description = ''
      Primary macOS user on this host. Drives system.primaryUser,
      users.users.<name>, and home-manager.users.<name>. Override in
      host configs whose login account isn't "geoff".
    '';
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) unfreePackageNames;

    system.stateVersion = 6;
    system.primaryUser = username;

    # zsh sourcing of nix-darwin's environment changes.
    programs.zsh.enable = true;

    homebrew.enable = true;
    homebrew.onActivation.autoUpdate = true; # can slow darwin-rebuild down
    homebrew.onActivation.upgrade = true;
    homebrew.onActivation.cleanup = "uninstall"; # remove brews/casks not in config
    homebrew.onActivation.extraFlags = ["--force"]; # required since homebrew added safety check for --cleanup
    # Ensure terminal/editor glyph support on every interactive macOS host.
    homebrew.casks = [
      "1password"
      "1password-cli"
      "font-hack-nerd-font"
      "ghostty"
    ];

    users.users.${username} = {
      name = username;
      home = "/Users/${username}";
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "pre-hm";
      extraSpecialArgs = {inherit lazyvim;};
      users.${username} = {pkgs, ...}: {
        imports = [
          # Editor (LazyVim + EDITOR) is shared cross-platform; desktop-base
          # bundles cli-tools/git/graphics/ssh + the macOS/Linux GUI bits.
          ../home/neovim.nix
          ../home/desktop-base.nix
          ../home/ai-tools.nix
        ];
        home.stateVersion = "25.11";

        # darwin-rebuild is part of nix-darwin's flake (not in nixpkgs).
        # Put it on the user PATH so it works without /run/current-system/sw/bin.
        home.packages = [
          darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild
        ];
      };
    };
  };
}
