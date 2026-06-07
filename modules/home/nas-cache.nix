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

  nix.settings = lib.mkIf (cachePublicKey != null) {
    extra-substituters = [cacheUrl];
    extra-trusted-public-keys = [cachePublicKey];
  };
}
