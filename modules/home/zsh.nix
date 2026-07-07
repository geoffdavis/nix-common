{
  lib,
  pkgs,
  ...
}: {
  programs = {
    # zoxide: frecency-ranked directory jumping; the zsh hook is required for
    # it to learn paths. The shared aliases put `cd` onto its zd wrapper.
    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    # fzf keybindings (Ctrl-R history, Ctrl-T files, Alt-C dirs). The fzf
    # binary itself also sits in cli-tools for consumers without this module.
    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    zsh = {
      enable = true;
      oh-my-zsh = {
        enable = true;
        theme = lib.mkDefault "agnoster";
        plugins = ["git" "python" "terraform"];
      };

      # Shared interactive aliases + functions. Single source of truth in
      # ../shell/interactive-aliases.nix, exposed on the flake as
      # lib.zshInteractiveInit and also consumed at the SYSTEM level by
      # nix-personal's headless-NAS shell (where the humans are FreeIPA users
      # with no home-manager generation). profile defaults to "workstation" =
      # the full set. Per-host initContent that sources a fuller alias file can
      # still override these (later source wins).
      initContent = import ../shell/interactive-aliases.nix {inherit pkgs lib;};
    };
  };
}
