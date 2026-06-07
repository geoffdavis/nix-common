# Shared home-manager module skeleton. Follows the nix-common module contract:
#
#   * one `enable` option gates all config via `lib.mkIf cfg.enable`
#   * `lib.mkDefault` on anything a consuming host might reasonably override
#   * no platform-specific absolute paths (`/Applications/...`, `/opt/...`)
#     without a darwin/nixos fork or a `lib.mkDefault` so consumers can override
#   * no lambda args the body does not use (deadnix is enforced in CI)
#
# After copying to `modules/home/<name>.nix`, export it from flake.nix:
#
#   homeModules.<name> = ./modules/home/<name>.nix;
#
# `task contract` (and CI) fail until that export exists. Use `task new:module
# -- <name>` to scaffold this skeleton with the name pre-substituted.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.myModule;
in {
  options.myModule = {
    enable = lib.mkEnableOption "CHANGEME: what this module provides";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgs.hello];

    # Use lib.mkDefault for anything a consuming host might want to override:
    #   programs.foo.settings.theme = lib.mkDefault "dark";
  };
}
