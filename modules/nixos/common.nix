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
  inherit (config.my) username;
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
      # Disk-pressure safety net: when free space drops below min-free mid-build
      # the daemon collects garbage until max-free is available again. Bounds the
      # worst case (a big closure landing on an almost-full disk) that scheduled
      # GC alone can't catch. mkDefault so a host can retune.
      min-free = lib.mkDefault (1024 * 1024 * 1024); # 1 GiB
      max-free = lib.mkDefault (5 * 1024 * 1024 * 1024); # 5 GiB
    };

    # Scheduled housekeeping. Weekly GC of generations older than 30d (keeps ~a
    # month of rollback history) plus periodic store optimisation (hard-links
    # identical files). All mkDefault so a host can disable or retune.
    nix.gc = {
      automatic = lib.mkDefault true;
      dates = lib.mkDefault "weekly";
      options = lib.mkDefault "--delete-older-than 30d";
    };
    nix.optimise.automatic = lib.mkDefault true;

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
