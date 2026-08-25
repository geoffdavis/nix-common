# modules/darwin/nas-backup.nix — scheduled restic backups to the NAS
# append-only rest-server, darwin equivalent of nixosModules.nas-backup.
# Same option shape (repositoryFile/passwordFile/paths/extraExcludes/timer)
# so a consuming host's backup.nix reads the same on either platform; no
# btrfs snapshot support here (macOS has no equivalent staging concept in
# scope for this module — back up live paths).
#
# There is no `services.restic.backups` on nix-darwin, so this schedules
# restic directly via a launchd daemon. Uses `launchd.daemons` (not a
# home-manager `launchd.agents` LaunchAgent) so the backup runs on schedule
# even when nobody is logged into the GUI session — UserName makes it run
# as the target user while staying a LaunchDaemon.
#
# Creds are read from files (repositoryFile/passwordFile) that the host
# materializes at switch via homeModules.op-file-secrets — this module
# never touches 1Password, matching the NixOS module's contract.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nasBackup;
  baselineExcludes = [
    "/Users/*/Library/Caches"
    "/Users/*/Library/Containers/*/Data/Library/Caches"
    "/Users/*/.Trash"
    "/Users/*/.cache"
    "/Users/*/node_modules"
    "/Users/*/.local/share/Steam"
    "/Users/*/.cargo/registry"
    "/Users/*/.npm/_cacache"
    "*.iso"
  ];
  excludeArgs = lib.concatMapStrings (e: " --exclude " + lib.escapeShellArg e) (baselineExcludes ++ cfg.extraExcludes);
  pathArgs = lib.concatMapStrings (p: " " + lib.escapeShellArg p) cfg.paths;
  label = "nas-backup-${cfg.name}";
in {
  options.services.nasBackup = {
    enable = lib.mkEnableOption "restic backups to the NAS rest-server (darwin)";

    name = lib.mkOption {
      type = lib.types.str;
      default = "nas";
      description = "launchd daemon label suffix and log-file discriminator.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      description = "macOS user the backup runs as, and whose home holds repositoryFile/passwordFile.";
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
      default = ["/Users/${cfg.username}"];
      description = "Paths to back up.";
    };

    extraExcludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra restic exclude patterns, appended to the baseline.";
    };

    timer = {
      hour = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Hour (0-23, local time) the backup starts.";
      };
      minute = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Minute the backup starts.";
      };
      randomizedDelaySec = lib.mkOption {
        type = lib.types.int;
        default = 1800;
        description = "Random jitter (seconds) added before the backup runs, so a sleeping laptop that wakes on schedule doesn't hammer the server at the same instant every host.";
      };
    };

    notify = {
      enable = lib.mkEnableOption "a GUI notification in the logged-in session when a backup run fails" // {default = true;};
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.restic];

    launchd.daemons.${label} = {
      serviceConfig = {
        UserName = cfg.username;
        StartCalendarInterval = [
          {
            Hour = cfg.timer.hour;
            Minute = cfg.timer.minute;
          }
        ];
        RunAtLoad = false;
        StandardOutPath = "/var/log/${label}.log";
        StandardErrorPath = "/var/log/${label}.log";
        ProgramArguments = [
          "/bin/sh"
          "-c"
          ''
            sleep "$(( RANDOM % ${toString (cfg.timer.randomizedDelaySec + 1)} ))"
            export RESTIC_REPOSITORY_FILE="${cfg.repositoryFile}"
            export RESTIC_PASSWORD_FILE="${cfg.passwordFile}"
            if ! ${pkgs.restic}/bin/restic backup${pathArgs}${excludeArgs}; then
              ${lib.optionalString cfg.notify.enable ''
              uid="$(/usr/bin/id -u ${cfg.username})"
              /bin/launchctl asuser "$uid" /usr/bin/osascript -e 'display notification "check /var/log/${label}.log" with title "NAS backup failed" subtitle "${label}"' || true
            ''}
              exit 1
            fi
          ''
        ];
      };
    };
  };
}
