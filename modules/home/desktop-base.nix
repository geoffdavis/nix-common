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
    ./graphics.nix
    ./ssh.nix
  ];

  # Standalone home-manager on non-NixOS Linux: source the nix daemon profile
  # so ~/.nix-profile/bin is on PATH and NIX_PROFILES is set correctly.
  # NixOS hosts that import this module should override this to false.
  targets.genericLinux.enable = lib.mkDefault pkgs.stdenv.isLinux;

  # Provide Nerd Font glyph coverage for terminal editors (Neovim, etc.)
  # on interactive Linux desktops.
  fonts.fontconfig.enable = pkgs.stdenv.isLinux;
  # _1password-gui comes from modules/home/onepassword.nix (imported via
  # ./cli-tools.nix above) so it stays in lockstep with the CLI override.
  home.packages = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    ghostty
    nerd-fonts.hack
    nerd-fonts.symbols-only
  ]);
}
