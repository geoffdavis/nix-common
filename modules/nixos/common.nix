# Shared NixOS system + home-manager wiring for personal NixOS hosts.
# Mirror of darwinModules.common. Host modules add hostname, boot, filesystem,
# desktop environment, and other host-specific config on top of this.
# Consumers pass `lazyvim` via specialArgs.
{
  config,
  lib,
  pkgs,
  lazyvim,
  ...
}: let
  username = config.my.username;
  unfreePackageNames = import ../shared/unfree-package-names.nix;
in {
  options.my.username = lib.mkOption {
    type = lib.types.str;
    default = "geoff";
    description = ''
      Primary user on this NixOS host. Drives users.users.<name> and
      home-manager.users.<name>. Override in host configs whose login account
      isn't "geoff".
    '';
  };

  config = {
    # home-manager useGlobalPkgs shares this nixpkgs config, so allowUnfree is
    # set at the system level (home-level nixpkgs.config is ignored there).
    nixpkgs.config.allowUnfreePredicate = pkg:
      builtins.elem (lib.getName pkg) unfreePackageNames;

    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" username];
    };

    programs.zsh.enable = true;

    users.users.${username} = {
      isNormalUser = true;
      description = "Geoff Davis";
      extraGroups = ["wheel" "networkmanager" "video"];
      shell = pkgs.zsh;
    };

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "pre-hm";
      extraSpecialArgs = {inherit lazyvim;};
      users.${username} = {
        imports = [../home/neovim.nix];
        home.username = username;
        home.homeDirectory = "/home/${username}";
        home.stateVersion = lib.mkDefault "25.11";
      };
    };
  };
}
