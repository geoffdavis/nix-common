{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./cli-tools.nix
    ./git.nix
    ./graphics.nix
    ./ssh.nix
  ];

  # Provide Nerd Font glyph coverage for terminal editors (Neovim, etc.)
  # on interactive Linux desktops.
  fonts.fontconfig.enable = pkgs.stdenv.isLinux;
  home.packages = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    _1password-gui
    nerd-fonts.hack
    nerd-fonts.symbols-only
  ]);
}
