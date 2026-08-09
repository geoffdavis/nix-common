# modules/cache-push.nix — publish this host's local build outputs to
# nas-sdg's file-based Nix cache (plain NAR + narinfo files on /tank, outside
# the Nix store), so interactive/dev builds and locally-built closures don't
# get recompiled elsewhere in the fleet.
#
# WHY a file cache and not nas-sdg's Harmonia cache, which this module used
# to push to directly: Harmonia serves nas-sdg's LIVE /nix/store, so every
# path pushed there was an unrooted store path — nothing GC-rooted it, so
# nix-collect-garbage on nas-sdg could reclaim a fleet-shared build the
# moment it ran (nix-personal#353). The file cache sits outside the store,
# so entries survive GC.
#
# Platform-agnostic: imported as nixosModules.cache-push or
# darwinModules.cache-push. Requires the host to ALSO import nas-cache, which
# provides the `nix-cache-push-nas-sdg` ssh alias and the daemon key
# /etc/nix/builder_ed25519. Requires the nix-personal side deployed on
# nas-sdg FIRST: the `nix-cache-push` user and its forced-command
# authorized_keys entry (nix-personal#353) — without it, pushes fail closed.
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
  # over the ssh-ng nix-cache-push endpoint (nas-cache.nix). --no-check-sigs
  # is kept because this host still has no signing key to check against —
  # signing, if any, happens server-side on ingest into the file cache, not
  # here.
  #
  # Note what's NOT in the --to url: no `remote-store=file:///tank/...`
  # query param naming the destination. The destination is pinned instead in
  # the forced command on nix-cache-push's authorized_keys entry on nas-sdg
  # (nix-personal#353). This is deliberate, not an oversight: the
  # nix-cache-push credential is handed to every builder in the fleet, and a
  # credential shared that widely should not also get to choose where on
  # nas-sdg its writes land — pinning the destination server-side means a
  # compromised or merely misconfigured client can push into the file cache
  # and nowhere else. Both forms were verified on real hardware; this one was
  # chosen for that reason.
  #
  # The copy IS its own reachability test: the ssh alias sets a short
  # ConnectTimeout (see nas-cache), so when the netbird overlay is down
  # (laptop off-VPN) the connection fails fast instead of blocking the build;
  # a hard timeout + `|| true` keep a slow/failed push non-fatal either way.
  # (An earlier `bash /dev/tcp` pre-probe was removed: it is SIGKILL'd on
  # darwin — bash's /dev/tcp to a non-local host is killed there — so it made
  # the hook skip every push on macOS. Letting `nix copy` connect is portable.)
  pushHook = pkgs.writeShellScript "cache-push-hook" ''
    set -eu
    [ -n "''${OUT_PATHS:-}" ] || exit 0
    ${pkgs.coreutils}/bin/timeout 30 ${config.nix.package}/bin/nix copy \
      --no-check-sigs \
      --to 'ssh-ng://nix-cache-push-nas-sdg' \
      $OUT_PATHS || true
  '';
in {
  options.my.cachePush.enable =
    lib.mkEnableOption "pushing local build outputs to nas-sdg's file-based cache via a post-build-hook";

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = "${pushHook}";
  };
}
