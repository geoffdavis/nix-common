# modules/cache-push.nix — publish this host's local build outputs to the
# nas-sdg Harmonia cache, so interactive/dev builds and locally-built closures
# don't get recompiled elsewhere in the fleet.
#
# Platform-agnostic: imported as nixosModules.cache-push or
# darwinModules.cache-push. Requires the host to ALSO import nas-cache, which
# provides the `nix-builder-nas-sdg` ssh alias, the daemon key
# /etc/nix/builder_ed25519, and the pinned host key. The host's builder public
# key must be authorized on nas-sdg (my.nixCache.builderKeys in nix-personal
# hosts/nas-sdg/default.nix) — the same key used for remote building.
#
# Design: nix-personal docs/superpowers/specs/2026-07-28-fleet-build-cache-retention-design.md
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.cachePush;
  # Runs per realised build (as the nix-daemon). Copies $OUT_PATHS to nas-sdg
  # over the ssh-ng builder endpoint. nix-remote-builder is a trusted user on
  # nas-sdg, so unsigned paths are accepted (--no-check-sigs) and this host
  # needs no signing key. A bounded TCP probe skips the push cleanly when the
  # netbird overlay is down (laptop off-VPN), so local builds never block on a
  # dead cache; a hard timeout + `|| true` keep a slow/failed push non-fatal.
  pushHook = pkgs.writeShellScript "cache-push-hook" ''
    set -eu
    [ -n "''${OUT_PATHS:-}" ] || exit 0
    ${pkgs.coreutils}/bin/timeout 2 ${pkgs.bash}/bin/bash -c \
      'exec 3<>/dev/tcp/nas-sdg.netbird.cloud/22' 2>/dev/null || exit 0
    ${pkgs.coreutils}/bin/timeout 30 ${config.nix.package}/bin/nix copy \
      --no-check-sigs \
      --to 'ssh-ng://nix-remote-builder@nix-builder-nas-sdg' \
      $OUT_PATHS || true
  '';
in {
  options.my.cachePush.enable =
    lib.mkEnableOption "pushing local build outputs to the nas-sdg Harmonia cache via a post-build-hook";

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = "${pushHook}";
  };
}
