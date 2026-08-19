# modules/nixos/distrobox.nix — opt-in distrobox + its container backend for
# NixOS hosts.
#
# Off by default; flip `my.distrobox.enable` per consumer. distrobox runs a
# mutable distro (Ubuntu, Fedora, Arch, …) in a container that shares the
# host's $HOME, so FHS-expecting binaries, vendor .debs and quick apt/dnf
# experiments work on a NixOS box without polluting the system closure.
#
# Podman is the backend rather than Docker: it is distrobox's own default, it
# runs rootless (no `docker` group, which is root-equivalent, on a laptop),
# and it needs no daemon. `virtualisation.podman.enable` already pulls in
# `virtualisation.containers.enable` for us — that is where /etc/containers
# and the netavark network backend come from — so this module does not set it
# again.
#
# Nothing else is required for the rootless path, which is worth recording
# because it looks like an omission:
#   - subuid/subgid ranges: NixOS sets `autoSubUidGidRange = true` by default
#     for every `isNormalUser`, so the user already has a mapping range.
#   - the newuidmap/newgidmap setuid wrappers: installed unconditionally by
#     the shadow module (programs/shadow.nix), not by anything container-side.
# A host whose user is NOT a normal user (a system account, or one with
# autoSubUidGidRange explicitly disabled) has to provide its own ranges.
#
# Deliberately NOT bundled: `virtualisation.podman.dockerCompat` (aliasing
# podman to `docker` is a host-wide decision that collides with an actual
# Docker install) and podman-compose (unrelated to distrobox). A host that
# wants either sets it itself.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.distrobox;
in {
  options.my.distrobox = {
    enable = lib.mkEnableOption "distrobox and its rootless podman backend";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.distrobox];

    # mkDefault so a host that would rather drive distrobox with Docker can
    # turn podman off (and set DBX_CONTAINER_MANAGER) without a definition
    # conflict.
    virtualisation.podman.enable = lib.mkDefault true;
  };
}
