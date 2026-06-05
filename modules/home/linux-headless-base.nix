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
    # cli-tools pulls in unfree packages (the pinned 1Password CLI via
    # onepassword.nix, terraform, ...) — headless hosts need the same
    # allowlist as desktops.
    ./unfree-desktop.nix
  ];

  # Standalone home-manager on non-NixOS Linux: source the nix daemon profile
  # so ~/.nix-profile/bin is on PATH and NIX_PROFILES is set correctly.
  # NixOS hosts that import this module should override this to false.
  targets.genericLinux.enable = lib.mkDefault pkgs.stdenv.isLinux;
}
