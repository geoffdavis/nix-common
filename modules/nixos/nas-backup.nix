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
        default = "02:00";
        description = "systemd OnCalendar for the backup timer.";
      };
      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "30m";
        description = "systemd RandomizedDelaySec for the backup timer.";
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

    (lib.mkIf snapshotting {
      services.restic.backups.${cfg.name} = {
        backupPrepareCommand = ''
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
          ExecStart = "${pkgs.libnotify}/bin/notify-send --urgency=critical 'NAS backup failed' 'restic-backups-${cfg.name} failed — journalctl -u restic-backups-${cfg.name}'";
        };
      };
    })
  ]);
}
