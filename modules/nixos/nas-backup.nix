# modules/nixos/nas-backup.nix — scheduled restic backups to the NAS
# append-only rest-server. Generic: the NAS endpoint, repo name, op://
# refs, and btrfs source are all supplied by the consuming host. Creds are
# read from files (repositoryFile/passwordFile) that the host materializes
# at switch via homeModules.op-file-secrets — this module never touches
# 1Password.
#
# Restore note: with the btrfs snapshot hook on, restic records paths under
# btrfsSnapshotStage (e.g. /.snapshots/restic-stage/<user>/...) instead of
# /home/<user>/...; restores land the data under that subpath. Standard
# btrfs+restic behaviour; the stage path is stable so dedup is unaffected.
#
# ── HOURLY CADENCE ──────────────────────────────────────────────────────
# The default timer is hourly, for parity with the Time Machine setup the
# darwin sibling replaced. Concurrency needs no extra machinery here the
# way it does on darwin: systemd will not start a second
# restic-backups-<name>.service while one is active, it just logs that the
# unit is already running and drops the trigger — which is exactly the
# wanted behaviour, and it also keeps the btrfs prepare/cleanup hooks (which
# delete and recreate one fixed stage subvolume) from ever interleaving.
#
# What does change with cadence is the cost of a transient fault. The NAS
# is reached over a NetBird overlay, so "cannot resolve the host" is a
# routine, self-healing condition; nightly that was one lost backup, hourly
# it would be 24 failed units and 24 desktop notifications a day. Hence
# preflight (an ExecCondition, so an unreachable NAS is a clean systemd
# *skip*, not a failure) and a rate limit on the notification itself.
#
# Snapshot volume is the server's problem, not this module's: the repo is
# append-only and Backrest owns the forget/prune policy. ~24 snapshots a
# day per host wants a forget policy with an `hourly` bucket, or the repo
# grows a snapshot list nothing ever trims.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nasBackup;
  snapshotting = cfg.btrfsSnapshotSource != null;
  baselineExcludes = [
    "**/.cache"
    "**/.local/share/Trash"
    "**/node_modules"
    "**/.local/share/Steam"
    "**/*.iso"
    "**/.cargo/registry"
    "**/.npm/_cacache"
    "**/.var/app/*/cache"
  ];
  btrfs = "${pkgs.btrfs-progs}/bin/btrfs";

  # Exit 0 => run the backup; exit 1 => systemd marks the activation as
  # skipped (ExecCondition semantics) and nothing downstream, onFailure
  # included, treats it as an error. Deliberately probes with the repo's
  # exit code rather than its output: a fresh repo with no snapshots at all
  # is reachable and must pass.
  preflightScript = pkgs.writeShellScript "nas-backup-preflight-${cfg.name}" ''
    set -u
    export RESTIC_REPOSITORY_FILE=${lib.escapeShellArg cfg.repositoryFile}
    export RESTIC_PASSWORD_FILE=${lib.escapeShellArg cfg.passwordFile}
    deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + ${toString cfg.preflight.waitSec} ))
    until ${pkgs.restic}/bin/restic snapshots --latest 1 --no-lock >/dev/null 2>&1; do
      if [ "$(${pkgs.coreutils}/bin/date +%s)" -ge "$deadline" ]; then
        echo "preflight: repo unreachable after ${toString cfg.preflight.waitSec}s; skipping this run"
        exit 1
      fi
      ${pkgs.coreutils}/bin/sleep 15
    done
  '';

  # notify-send, but at most once per notify.minIntervalSec. The stamp lives
  # in the user's XDG_RUNTIME_DIR: the unit already requires that directory
  # to reach the session bus at all, and the user owns it, so this needs no
  # extra StateDirectory. Losing the stamp on logout/reboot is the right
  # default anyway — the first failure after you come back should speak up.
  notifyScript = pkgs.writeShellScript "nas-backup-notify-${cfg.name}" ''
    set -u
    stamp="''${XDG_RUNTIME_DIR}/nas-backup-${cfg.name}.notified"
    now=$(${pkgs.coreutils}/bin/date +%s)
    if [ -e "$stamp" ]; then
      last=$(${pkgs.coreutils}/bin/stat -c %Y "$stamp")
      if [ $(( now - last )) -lt ${toString cfg.notify.minIntervalSec} ]; then
        echo "failure notification suppressed (last one $(( (now - last) / 60 ))m ago)"
        exit 0
      fi
    fi
    # Stamp only once the banner is actually delivered. notify-send exits 1
    # when there is no session bus (nobody logged in) — stamping first would
    # let a failure nobody ever saw burn the whole suppression window, so the
    # next login would stay silent about a backup that is still broken.
    ${pkgs.libnotify}/bin/notify-send --urgency=critical \
      'NAS backup failed' \
      'restic-backups-${cfg.name} failed — journalctl -u restic-backups-${cfg.name}'
    rc=$?
    [ "$rc" -eq 0 ] && ${pkgs.coreutils}/bin/touch "$stamp"
    exit $rc
  '';
in {
  options.services.nasBackup = {
    enable = lib.mkEnableOption "restic backups to the NAS rest-server";

    name = lib.mkOption {
      type = lib.types.str;
      default = "nas";
      description = "services.restic.backups.<name> key and systemd unit suffix.";
    };

    repositoryFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the full restic `rest:` URL including credentials.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding the restic repository encryption password.";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["/home"];
      description = "Paths to back up. Ignored when btrfsSnapshotSource is set.";
    };

    extraExcludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra restic exclude patterns, appended to the baseline.";
    };

    btrfsSnapshotSource = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home";
      description = "When set, snapshot this path read-only into btrfsSnapshotStage and back that up (atomic). null backs up `paths` live.";
    };

    btrfsSnapshotStage = lib.mkOption {
      type = lib.types.str;
      default = "/.snapshots/restic-stage";
      description = "Destination subvolume path for the read-only staging snapshot.";
    };

    timer = {
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "hourly";
        example = "02:00";
        description = ''
          systemd OnCalendar for the backup timer. Hourly by default; set a
          single time to go back to one run a day.
        '';
      };
      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "5m";
        description = ''
          systemd RandomizedDelaySec for the backup timer — decorrelates
          hosts so they don't all hit the server on the hour. Kept well
          under the interval on an hourly schedule; the point is to spread
          hosts, not to smear one host's cadence.
        '';
      };
    };

    preflight = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Gate the backup on one cheap metadata call against the repo, run
          as the unit's ExecCondition. If the repo does not open within
          `waitSec`, systemd records the run as *skipped* rather than
          failed — no failed unit, no onFailure notification, and the next
          timer elapse retries.

          The NAS is reached over a NetBird overlay, so "unreachable" is a
          routine, self-healing state rather than a fault, and at an hourly
          cadence the retry is minutes away.
        '';
      };
      waitSec = lib.mkOption {
        type = lib.types.int;
        default = 180;
        description = "How long preflight waits for the repo to become reachable before skipping the run.";
      };
    };

    notify = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Fire a desktop notification when a backup run fails.";
      };
      uid = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "UID of the graphical session receiving the notification.";
      };
      minIntervalSec = lib.mkOption {
        type = lib.types.int;
        default = 21600;
        description = ''
          Minimum gap between failure notifications. The first failure
          notifies immediately; a persistent one repeats at most this often
          rather than once per hourly run — an hourly job with a broken
          credential that pops a banner every hour just trains you to
          dismiss it. Default 6h.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.restic.backups.${cfg.name} = {
        inherit (cfg) repositoryFile passwordFile;
        initialize = lib.mkDefault false;
        paths = lib.mkDefault (
          if snapshotting
          then [cfg.btrfsSnapshotStage]
          else cfg.paths
        );
        exclude = lib.mkDefault (baselineExcludes ++ cfg.extraExcludes);
        timerConfig = {
          OnCalendar = lib.mkDefault cfg.timer.onCalendar;
          Persistent = lib.mkDefault true;
          RandomizedDelaySec = lib.mkDefault cfg.timer.randomizedDelaySec;
        };
        # Deliberately no pruneOpts: the server is append-only; Backrest prunes.
      };
    }

    (lib.mkIf cfg.preflight.enable {
      systemd.services."restic-backups-${cfg.name}".serviceConfig.ExecCondition = lib.mkDefault "${preflightScript}";
    })

    (lib.mkIf snapshotting {
      services.restic.backups.${cfg.name} = {
        backupPrepareCommand = ''
          # Ensure the stage's parent dir exists — generic hosts may not have
          # one (birdrock mounts @snapshots at /.snapshots, but don't assume).
          # Absolute path: the restic unit's PATH is minimal.
          ${pkgs.coreutils}/bin/mkdir -p ${builtins.dirOf cfg.btrfsSnapshotStage}
          ${btrfs} subvolume delete ${cfg.btrfsSnapshotStage} 2>/dev/null || true
          ${btrfs} subvolume snapshot -r ${cfg.btrfsSnapshotSource} ${cfg.btrfsSnapshotStage}
        '';
        backupCleanupCommand = ''
          ${btrfs} subvolume delete ${cfg.btrfsSnapshotStage} 2>/dev/null || true
        '';
      };
    })

    (lib.mkIf cfg.notify.enable {
      systemd.services."restic-backups-${cfg.name}".onFailure = ["restic-nas-notify-${cfg.name}.service"];
      systemd.services."restic-nas-notify-${cfg.name}" = {
        description = "Desktop notification for a failed restic backup (${cfg.name})";
        serviceConfig = {
          Type = "oneshot";
          User = toString cfg.notify.uid;
          Environment = [
            "XDG_RUNTIME_DIR=/run/user/${toString cfg.notify.uid}"
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${toString cfg.notify.uid}/bus"
          ];
          # Best-effort: if the user is logged out there's no session bus, so
          # notify-send exits 1. SuccessExitStatus keeps that from parking the
          # unit in `systemctl --failed` (genuine failures — e.g. libnotify
          # missing — exit with other codes and stay visible).
          SuccessExitStatus = "0 1";
          ExecStart = "${notifyScript}";
        };
      };
    })
  ]);
}
