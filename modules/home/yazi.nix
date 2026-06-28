# Shared yazi (terminal file manager) config + shell integration.
# Cross-platform (macOS + Linux). Like git.nix / neovim.nix this is a
# program-wrapping base module: importing it *is* the opt-in, so there is no
# separate enable gate — a host that doesn't want yazi simply doesn't import
# it. Everything a host might reasonably tweak is `lib.mkDefault`.
#
# Catppuccin theming is intentionally NOT wired here. catppuccin/nix is a
# downstream input (not a nix-common one), and the hosts that use it run with
# `autoEnable` on, so their catppuccin module themes yazi automatically once
# `programs.yazi.enable` is set — exactly how kitty/waybar/hyprlock get themed.
# Setting `catppuccin.yazi.enable` from here would either reference an
# undeclared option on headless hosts (error) or, if guarded on the option's
# presence, make this module's shape depend on the option set (infinite
# recursion in the module fixpoint). Leave it to autoEnable.
{lib, ...}: {
  programs.yazi = {
    enable = true;

    # `y` opens yazi and cd's the shell to the directory you quit in (the
    # wrapper writes the chosen cwd back out). Renamed off the default
    # "yazi" so the bare binary still works non-interactively.
    shellWrapperName = lib.mkDefault "y";

    # zsh is the primary shell (modules/home/zsh.nix); bashInteractive is
    # also installed via cli-tools.nix, so wire both wrappers up.
    enableZshIntegration = lib.mkDefault true;
    enableBashIntegration = lib.mkDefault true;

    # yazi.toml. yazi 25.x renamed the `[manager]` table to `[mgr]`; this is
    # a freeform attrset (home-manager does no validation), so keep it in
    # sync with the pinned yazi if it lags. All mkDefault so a host can
    # override any single key without a conflict.
    settings = {
      mgr = {
        show_hidden = lib.mkDefault false;
        sort_by = lib.mkDefault "natural";
        sort_dir_first = lib.mkDefault true;
        sort_sensitive = lib.mkDefault false;
        linemode = lib.mkDefault "size";
      };

      preview = {
        tab_size = lib.mkDefault 2;
        max_width = lib.mkDefault 600;
        max_height = lib.mkDefault 900;
      };
    };
  };
}
