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
  # (laptop off-VPN) the connection fails fast instead of blocking the build.
  # (An earlier `bash /dev/tcp` pre-probe was removed: it is SIGKILL'd on
  # darwin — bash's /dev/tcp to a non-local host is killed there — so it made
  # the hook skip every push on macOS. Letting `nix copy` connect is portable.)
  #
  # THE WALL-CLOCK TIMEOUT IS A BACKSTOP, NOT THE STALL DETECTOR. It used to
  # be 30s, which is a THROUGHPUT GATE in disguise: whether a path lands
  # depends on its size against the current link speed, so the cut-off moves
  # with load. Measured 2026-08-09 at 17 MiB/s over the overlay, 30s buys
  # roughly 500 MiB nominal — less once closure paths and protocol overhead
  # are included, and less again while the link is busy.
  #
  # That makes it MARGINAL rather than cleanly wrong, which is worse. A
  # 354 MiB path sits at ~21s: it squeaks through often enough that nobody
  # investigates, and fails often enough never to persist. Observed exactly
  # that — onlyoffice (354 MiB) re-pushed on every build and absent from all
  # 27,359 cache entries, while 1password (199 MiB), obsidian (112 MiB) and
  # plasma-workspace-wallpapers (216 MiB) all landed fine at 6-13s.
  # `|| true` then swallowed every failure, and the hook runs per realised
  # derivation with `nix copy` pushing each path plus its closure, so the
  # same doomed transfer was retried repeatedly within a single build.
  #
  # (nas-sdg pushes to this cache through its own local hook, disk-to-disk,
  # so its builds are unaffected by any of this. Entries above ~500 MiB in
  # the cache came from there, not from a remote pusher — do not read them
  # as evidence that large remote pushes succeed.)
  #
  # Three layers already bound a push, in increasing order of severity, and
  # the wall-clock one must sit ABOVE the others or it preempts them:
  #   - ConnectTimeout 4 (nas-cache)          — unreachable host, ~4s
  #   - ServerAliveInterval 15 x CountMax 3   — stalled connection, ~45s
  #   - this timeout                          — pathological hang only
  #
  # --kill-after=60 is not decoration: plain `timeout N` sends SIGTERM and
  # then waits FOREVER, so against a child that ignores it the "hard bound"
  # bounds nothing. nas-sdg's sibling hook (nix-personal
  # modules/nas/nix-cache.nix) lacked it, and on 2026-08-16 four of its
  # pushes wedged in futex_do_wait, shrugged off SIGTERM, and were still
  # alive 4.4 hours later — each holding a shared /nix/var/nix/gc.lock, which
  # starved the GC until the host hit 100% disk and every deploy to it hung.
  # This hook has the same shape and the same blast radius (it BLOCKS the
  # build), so it gets the same escalation.
  # At 30s it fired BEFORE the 45s keepalive teardown built for exactly this
  # job, so it could only ever kill transfers that were working. 600s is
  # chosen to clear that by an order of magnitude while still bounding a
  # hook that BLOCKS the build: even a slow overlay link moves a multi-GB
  # path well inside it. A fixed wall-clock value is a poor instrument for
  # "too slow" — it cannot tell stalled from merely large — which is why the
  # keepalives, not this, are what detect a dead peer.
  #
  # WHY NOT `--substitute-on-destination` (-s), which would have the
  # destination fetch from its own substituters instead of receiving bytes
  # over the wire: the destination is a `file://` binary cache, pinned in the
  # forced command with no substituters configured, so it has nothing to
  # substitute FROM. Assessed 2026-08-09 and rejected on that basis — not
  # empirically confirmed, since the daemon key is root-only.
  #
  # Failures are non-fatal (a broken cache must never fail a build) but are
  # no longer silent: this exact bug survived months because `|| true`
  # produced no output. Grep build logs for `cache-push:`. Path size is
  # deliberately NOT computed — it would mean walking the closure on every
  # hook invocation, and the path list already names what to look up.
  pushHook = pkgs.writeShellScript "cache-push-hook" ''
    set -eu
    [ -n "''${OUT_PATHS:-}" ] || exit 0
    rc=0
    ${pkgs.coreutils}/bin/timeout --kill-after=60 600 ${config.nix.package}/bin/nix copy \
      --no-check-sigs \
      --to 'ssh-ng://nix-cache-push-nas-sdg' \
      $OUT_PATHS || rc=$?
    if [ "$rc" -ne 0 ]; then
      if [ "$rc" -eq 124 ]; then
        echo "cache-push: TIMEOUT after 600s; NOT cached: $OUT_PATHS" >&2
      elif [ "$rc" -eq 137 ]; then
        # SIGKILL from --kill-after: the copy ignored SIGTERM at the deadline.
        # This is the shape that wedged nas-sdg's GC — worth naming separately
        # so it is greppable rather than filed under a generic exit code.
        echo "cache-push: HUNG, SIGKILLed after 660s (ignored SIGTERM); NOT cached: $OUT_PATHS" >&2
      else
        echo "cache-push: FAILED (exit $rc); NOT cached: $OUT_PATHS" >&2
      fi
    fi
  '';
in {
  options.my.cachePush.enable =
    lib.mkEnableOption "pushing local build outputs to nas-sdg's file-based cache via a post-build-hook";

  config = lib.mkIf cfg.enable {
    nix.settings.post-build-hook = "${pushHook}";
  };
}
