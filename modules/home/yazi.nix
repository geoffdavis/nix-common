# Shared yazi (terminal file manager) config + shell integration.
# Cross-platform (macOS + Linux). Like git.nix / neovim.nix this is a
# program-wrapping base module: importing it *is* the opt-in, so there is no
# separate enable gate — a host that doesn't want yazi simply doesn't import
# it. Everything a host might reasonably tweak is `lib.mkDefault`.
{
  config,
  lib,
  ...
}: {
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

  # Theme yazi with Catppuccin via catppuccin/nix's yazi port, inheriting the
  # host's global `catppuccin.flavor`/`accent` so yazi matches the rest of the
  # desktop (kitty/waybar/hyprlock) rather than hardcoding Mocha here.
  #
  # Guarded on the option being declared: catppuccin/nix is wired in each
  # consumer's own flake (it isn't a nix-common input), so a headless host
  # that imports this module without it must still evaluate — `mkIf` drops the
  # definition before the module system checks the option exists. With
  # catppuccin's `autoEnable` (default on) this port already turns on once
  # `programs.yazi.enable` is set; the explicit `mkDefault` makes the intent
  # legible and survives a host that disables autoEnable.
  catppuccin = lib.mkIf (config ? catppuccin) {
    yazi.enable = lib.mkDefault true;
  };
}
