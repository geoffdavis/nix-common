# Home-manager module: nix-index-powered command-not-found + comma.
#
# Gives interactive shells two things, both backed by the prebuilt nix-index
# database (fetched via the nix-index-database flake input and refreshed on
# each `nix flake update` — hosts never run `nix-index` by hand):
#   - a command_not_found_handler that, on an unknown command, names the
#     nixpkgs package(s) providing it (e.g. `htop` -> `nix-shell -p htop`).
#   - comma (`,`): run a program straight from nixpkgs without installing it,
#     e.g. `, cowsay hi`.
#
# This module owns the command_not_found_handler. pay-respects (wired in
# zsh.nix) is initialised with --nocnf so it does not fight for the same hook:
# pay-respects keeps the `f` alias and ^X^X inline correction (fix what you
# mistyped); nix-index answers the orthogonal question "that program exists in
# nixpkgs, here's how to get it".
#
# Exported from the flake as `import ./nix-index.nix inputs` because the
# prebuilt-database HM module comes from a flake input.
inputs: {
  config,
  lib,
  ...
}: let
  cfg = config.nixIndex;
in {
  imports = [inputs.nix-index-database.homeModules.nix-index];

  options.nixIndex.enable =
    lib.mkEnableOption "nix-index command-not-found handler and comma (`,`), backed by the prebuilt nix-index database";

  config = lib.mkMerge [
    # Unconditional: the imported module flips `programs.nix-index.enable` on
    # with `mkDefault` just by being imported, so drive it from this toggle at
    # normal priority — that wins over their default and makes
    # `nixIndex.enable = false` actually turn it off. Hosts that need a
    # different value can still `mkForce` it.
    {programs.nix-index.enable = cfg.enable;}
    (lib.mkIf cfg.enable {
      # `,` runs a program from nixpkgs without installing it, using the same
      # prebuilt database as the command-not-found handler. mkDefault so a host
      # can opt back out while keeping the handler.
      programs.nix-index-database.comma.enable = lib.mkDefault true;
    })
  ];
}
