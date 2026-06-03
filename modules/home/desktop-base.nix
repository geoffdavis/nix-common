{
  config,
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
  home.packages = lib.optionals pkgs.stdenv.isLinux (with pkgs; [
    _1password-gui
    ghostty
    nerd-fonts.hack
    nerd-fonts.symbols-only
  ]);

  # On standalone Home Manager (generic Linux), ensure GUI login sessions load
  # hm-session-vars so launchers from ~/.nix-profile/share/applications are
  # visible in desktop app menus.
  sharedProfile.snippets = lib.optionals (pkgs.stdenv.isLinux && config.targets.genericLinux.enable) [
    ''
      if [ -e "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
      fi
    ''
  ];
}
