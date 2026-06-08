# modules/home/nas-cache.nix — substituter-only NAS cache config for
# standalone home-manager on Linux (oceaneering-laptop, azure-dev-vm).
# nix.buildMachines is not a home-manager option; builder config for these
# hosts goes via the Ansible system layer (writes /etc/nix/machines and
# /etc/ssh/ssh_config.d/99-nix-builder.conf).
#
# For system-level consumers (NixOS, nix-darwin) use nixosModules.nas-cache
# or darwinModules.nas-cache instead — those include the full builder config.
{
  lib,
  pkgs,
  ...
}: let
  cacheUrl = "http://nas-sdg.netbird.cloud:30500";
  cachePublicKey = "nas-sdg-nix-cache-1:5FXUg5ik7av8CDnsngWpuM2Xe9RJ3WYoewH6t+rt9mo=";
in {
  # home-manager requires nix.package to be set before it will write nix.conf.
  # mkDefault so a host that already sets nix.package (e.g. to nix-unstable)
  # keeps its own choice.
  nix.package = lib.mkDefault pkgs.nix;

  # Flakes + the new CLI, written into the home-manager-managed
  # ~/.config/nix/nix.conf. The Determinate installer normally enables these
  # in /etc/nix/nix.conf, but on these standalone-HM Ubuntu hosts that file is
  # owned by the Ansible system layer and has gone missing in practice —
  # leaving `nix run`/`task hm:switch` dead with "experimental Nix feature
  # 'nix-command' is disabled". Declaring it in the user config makes it
  # self-healing: every switch rewrites nix.conf with these features. Set
  # unconditionally (not gated on the cache key) since every consumer needs it.
  nix.settings.experimental-features = ["nix-command" "flakes"];

  nix.settings = lib.mkIf (cachePublicKey != null) {
    extra-substituters = [cacheUrl];
    extra-trusted-public-keys = [cachePublicKey];
  };
}
