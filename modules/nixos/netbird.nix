# modules/nixos/netbird.nix — netbird overlay spoke: the daemon, plus
# optional identity restore and optional one-shot enrollment.
#
# PROMOTED from nix-personal (#124): four hosts there consume it, it is
# deliberately sops-agnostic and names no fleet endpoints, and nix-common's
# own nas-cache module assumes an overlay exists — the mechanism belongs at
# the shared layer. nix-personal's nixosTest for it stays in that repo
# (this repo has no checks output; the test exercises the module through
# the flake input on every nix-personal `nix flake check`).
#
# Extracted from three copy-pasted host configs (nas-cin, nas-sct, nas-sdg)
# when tourmaline would have made a fourth. Deliberately sops-AGNOSTIC: it
# takes PATHS and hosts declare their own sops.secrets + restartUnits, which
# is already how nas-sdg did it. That keeps the module usable by a host with
# no sops at all, and keeps secret NAMES a host concern.
#
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.netbird;
in {
  options.my.netbird = {
    enable = lib.mkEnableOption "netbird overlay agent (spoke class)";

    stateFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File holding base64 of a preserved netbird config.json (its WireGuard
        private key + ManagementURL). When set, netbird-restore drops it into
        the state dir before the daemon starts, so a REINSTALL reconnects as
        the EXISTING peer instead of minting a new one and orphaning the old
        — an orphan keeps the canonical DNS name, which breaks deploys.

        Null for a genuinely new peer. Contents beginning with PLACEHOLDER are
        treated as not-yet-provisioned and skipped.
      '';
    };

    setupKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        File holding an admin-minted setup key. When set, netbird-join enrolls
        with it — the FALLBACK for when no identity was restored, or the
        restore did not connect. PLACEHOLDER contents are skipped so a deploy
        never fails or rolls back on enrollment state.
      '';
    };

    useRoutingFeatures = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum ["client" "server" "both"]);
      default = null;
      description = ''
        Passed through to services.netbird.useRoutingFeatures. "both" is the
        routing-peer posture (ip_forward for the server half, loose rp_filter
        for the client half). Null leaves the nixpkgs default, which is what a
        plain spoke wants.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      # Compat alias == clients.default = { port = 51820; interface = "wt0";
      # hardened = false; } — the fleet convention. The daemon runs from first
      # boot; unenrolled it just sits in NeedsLogin, which is harmless.
      services.netbird.enable = true;

      # DNS: resolved, not plain resolvconf — and this is a correctness
      # requirement, not a preference.
      #
      # netbird needs per-domain resolution to do split DNS. resolvconf has
      # none, so netbird falls back to rewriting /etc/resolv.conf to point ALL
      # system DNS at its own in-process resolver on wt0. That makes the
      # overlay a hard dependency of every lookup on the host, including the
      # one netbird itself needs to come back:
      #
      #   netbird loses management
      #     -> its resolver stops answering
      #     -> resolv.conf still points at it, so ALL DNS fails
      #     -> netbird cannot resolve api.netbird.io to reconnect
      #
      # which is a closed loop with no self-recovery. Observed on tourmaline
      # 2026-08-19: DNS dead, resolv.conf holding `nameserver <its own overlay
      # IP>`, recovered only by hand-writing a LAN nameserver. birdrock hit
      # the same thing in June and fixed it exactly this way (see
      # nix-personal hosts/birdrock/network.nix) — "any daemon DNS stall
      # presented as total network problems".
      #
      # With resolved, netbird registers only its MATCH DOMAINS
      # (netbird.cloud, the realm, …) on wt0 and every other lookup rides the
      # host's normal DNS, so a disconnected overlay costs overlay names and
      # nothing else.
      #
      # mkDefault: a host with a deliberate DNS design of its own can still
      # override it, but it should have to say so.
      services.resolved.enable = lib.mkDefault true;
    }

    (lib.mkIf (cfg.useRoutingFeatures != null) {
      services.netbird.useRoutingFeatures = cfg.useRoutingFeatures;
    })

    (lib.mkIf (cfg.stateFile != null) {
      systemd.services.netbird-restore = {
        description = "Restore preserved netbird peer identity (reconnect as the existing peer)";
        before = ["netbird.service"];
        wantedBy = ["netbird.service"];
        # Never clobber an already-present config: a live peer is undisturbed
        # on redeploy.
        unitConfig.ConditionPathExists = "!/var/lib/netbird/config.json";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          state="${cfg.stateFile}"
          if ${pkgs.gnugrep}/bin/grep -q '^PLACEHOLDER' "$state"; then
            echo "netbird-state is the repo placeholder; leaving enrollment to netbird-join"
            exit 0
          fi
          install -d -m0700 -o root -g root /var/lib/netbird
          ${pkgs.coreutils}/bin/base64 -d "$state" > /var/lib/netbird/config.json
          chmod 0600 /var/lib/netbird/config.json
          echo "restored preserved netbird config -> ${config.networking.hostName} should reconnect as its existing peer"
        '';
      };
    })

    (lib.mkIf (cfg.setupKeyFile != null) {
      systemd.services.netbird-join = {
        description = "Enroll netbird with the provided setup key (fallback if reuse fails; idempotent)";
        # Order is deliberate: netbird.service, then the restore unit when
        # there is one, then network-online.target. That is the ordering all
        # three hosts had inline before this module existed, reproduced here
        # so the extraction changed no unit semantics.
        after =
          ["netbird.service"]
          ++ lib.optional (cfg.stateFile != null) "netbird-restore.service"
          ++ ["network-online.target"];
        wants = ["network-online.target"];
        requires = ["netbird.service"];
        wantedBy = ["multi-user.target"];
        path = [config.services.netbird.package];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # `netbird up` BLOCKS until it reaches the management service, and
          # systemd's default here is infinity. On tourmaline 2026-08-19 that
          # turned a transient DNS outage into a permanent wedge: this unit
          # sat in `activating` for 20 minutes, multi-user.target waited on
          # it, and switch-to-configuration blocked behind that — so the
          # deploy never failed either, it HUNG, which meant deploy-rs's
          # magicRollback could not fire (it reverts a failed activation, not
          # a stuck one). A bounded failure is recoverable; an unbounded wait
          # is not.
          TimeoutStartSec = "120s";
        };
        script = ''
          key_file="${cfg.setupKeyFile}"
          state_file="/var/lib/netbird/config.json"

          # Gate on ENROLLMENT, not connectivity.
          #
          # This used to test `netbird status | grep "Management: Connected"`,
          # which is a CONNECTIVITY check wearing an enrollment check's
          # clothes. Any network disruption — a resolver restart, a VLAN
          # change, the overlay flapping — reads as "not enrolled", so the
          # unit tries to re-enroll a host that is already enrolled and holds
          # a valid identity. On tourmaline that fired during a networking
          # migration while /var/lib/netbird/config.json was intact and 2001
          # bytes on disk, untouched since March.
          #
          # The identity is the right signal: config.json carries the peer's
          # WireGuard private key, and its presence is exactly what makes
          # enrollment unnecessary. Whether the daemon can currently REACH
          # management is netbird's problem to retry, not this unit's problem
          # to solve by minting a new peer.
          # Whitespace-tolerant on purpose: netbird writes config.json
          # PRETTY-PRINTED, so the naive '"PrivateKey":"' (no space) never
          # matches. Verified against a real identity on tourmaline — the file
          # contains `"PrivateKey": "` — and a gate that never matches is
          # WORSE than the connectivity check it replaces, because it would
          # re-enroll on every single activation rather than only during a
          # network blip.
          if [ -s "$state_file" ] && grep -qE '"PrivateKey"[[:space:]]*:[[:space:]]*"[^"]' "$state_file"; then
            echo "already enrolled (identity present in $state_file); nothing to do"
            exit 0
          fi
          if grep -q '^PLACEHOLDER' "$key_file"; then
            # Host-agnostic on purpose: a shared module can't name a
            # specific host's secrets/ path, but this hint is read exactly
            # when someone is debugging a stuck placeholder-key deploy, so
            # it earns its place.
            echo "setup key is the repo placeholder; skipping enrollment (mint a one-off key and redeploy)"
            exit 0
          fi
          # --setup-key-file keeps the key off argv (no /proc leak).
          #
          # Bounded independently of TimeoutStartSec so the failure is
          # ATTRIBUTABLE: a timeout here says "enrollment could not reach
          # management", where a unit-level kill says only "something took too
          # long". --kill-after because `netbird up` does not always honour
          # SIGTERM promptly, and a plain `timeout` that cannot kill its child
          # bounds nothing (see nix-common cache-push, same lesson).
          if ! timeout --kill-after=15s 90s netbird up --setup-key-file "$key_file"; then
            echo "netbird-join: enrollment did not complete within 90s — the host keeps its existing identity, if any" >&2
            exit 1
          fi
        '';
      };
    })
  ]);
}
