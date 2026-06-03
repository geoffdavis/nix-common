{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./profile.nix
    ./cli-tools.nix
    ./git.nix
    ./zsh.nix
  ];

  # Standalone home-manager on non-NixOS Linux: source the nix daemon profile
  # so ~/.nix-profile/bin is on PATH and NIX_PROFILES is set correctly.
  # NixOS hosts that import this module should override this to false.
  targets.genericLinux.enable = lib.mkDefault pkgs.stdenv.isLinux;
}
