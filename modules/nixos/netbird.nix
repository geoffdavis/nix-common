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
        };
        script = ''
          key_file="${cfg.setupKeyFile}"
          if netbird status 2>/dev/null | grep -q "Management: Connected"; then
            echo "already enrolled; nothing to do"
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
          netbird up --setup-key-file "$key_file"
        '';
      };
    })
  ]);
}
