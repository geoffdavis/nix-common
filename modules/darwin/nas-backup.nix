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
#
# ── HOURLY CADENCE ──────────────────────────────────────────────────────
# The default schedule is hourly (timer.hour = null), for parity with the
# Time Machine setup this replaced. Four things make an hourly restic job
# safe that a once-nightly one could get away with ignoring:
#
#   1. Overlap. At 24 starts a day, a run that outlasts its slot is no
#      longer hypothetical. `flock -n` around restic is the hard guarantee
#      that only one restic touches this repo at a time, and minIntervalSec
#      is the soft one that stops launchd re-firing a just-finished job
#      back-to-back (see that option's description).
#   2. Transient unreachability. The NAS lives on a NetBird overlay, so a
#      laptop that half-wakes for launchd before the overlay is up cannot
#      resolve it. Nightly, that was one lost backup; hourly it would be 24
#      failure notifications a day. preflight turns "can't reach the repo"
#      into a clean skip instead of a failure.
#   3. What counts as a failure. restic exit 3 means "snapshot created, but
#      some source files were unreadable" — the permanent steady state on
#      macOS, where a LaunchDaemon has no Full Disk Access and every run
#      trips over the TCC-protected corners of ~/Library. It is logged, not
#      notified, and not a non-zero exit.
#   4. Notification volume. notify.enable is OFF by default here (it is on
#      for the NixOS sibling): the only delivery path a LaunchDaemon has is
#      osascript, which needs an Automation grant whose prompt names this
#      module's own store-path wrapper and therefore cannot survive a
#      rebuild. A consumer's status widget carries the signal instead. When
#      it IS enabled, a genuine persistent failure fires once and then at
#      most every notify.minIntervalSec, and the window is stamped on the
#      ATTEMPT — so a delivery path that is itself broken cannot defeat its
#      own rate limit.
#
# Snapshot volume is the server's problem, not this module's: the repo is
# append-only and Backrest owns the forget/prune policy. Going from ~1 to
# ~24 snapshots a day per host wants a forget policy with an `hourly`
# bucket — restic's own `--keep-hourly 24 --keep-daily 7 ...` shape — or
# the repo grows a snapshot list nothing ever trims.
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
  cacertArg = lib.optionalString (cfg.cacertFile != null) (" --cacert " + lib.escapeShellArg "${cfg.cacertFile}");
  label = "nas-backup-${cfg.name}";
  logDir = "/Users/${cfg.username}/Library/Logs";
  # Convention, not an option: a consumer's own status-widget script (e.g.
  # an xbar plugin) derives this same path from username + name rather than
  # this module exposing it — it's just where the live --json progress
  # stream lands, sibling to the human-readable StandardOutPath log.
  progressFile = "${logDir}/${label}.progress.json";
  # Run-state, all in the same user-writable dir as the logs so nothing
  # needs a privileged path or a tmpfiles rule:
  #   .lock        flock(2) target; held for the duration of restic itself.
  #   .stamp       mtime = end of the last run that actually reached restic.
  #   .notified    mtime = when we last posted a failure notification.
  #
  # Like progressFile these are a convention rather than options, and .stamp
  # is the one a consumer legitimately touches: deleting it is how a "back up
  # NOW" affordance (a menu-bar widget, a shell alias) tells this job that the
  # run it is about to request is not a duplicate, so timer.minIntervalSec
  # does not silently swallow it.
  lockFile = "${logDir}/${label}.lock";
  stampFile = "${logDir}/${label}.stamp";
  notifyStamp = "${logDir}/${label}.notified";

  # Seconds since $1 was last modified, or a very large number if it does
  # not exist yet (i.e. "infinitely stale", so every caller runs).
  ageOf = ''
    age_of() {
      if [ -e "$1" ]; then
        echo $(( $(${pkgs.coreutils}/bin/date +%s) - $(${pkgs.coreutils}/bin/stat -c %Y "$1") ))
      else
        echo 999999999
      fi
    }
  '';

  backupScript = pkgs.writeShellScript label ''
    set -u
    export RESTIC_REPOSITORY_FILE=${lib.escapeShellArg cfg.repositoryFile}
    export RESTIC_PASSWORD_FILE=${lib.escapeShellArg cfg.passwordFile}
    restic=${pkgs.restic}/bin/restic
    ${ageOf}

    # ── rate limit ───────────────────────────────────────────────────────
    # Checked before the jitter sleep so a suppressed run costs nothing.
    # launchd will not run two copies of a daemon at once, but it does
    # remember an interval that fired while the job was busy and start it
    # the instant the job exits — so without this a backup that overruns
    # its slot is followed immediately by another one, forever. This also
    # absorbs `launchctl kickstart` (the widget's "Run Backup Now", a
    # darwin-rebuild switch reloading the daemon) landing near a scheduled
    # run.
    if [ "$(age_of ${lib.escapeShellArg stampFile})" -lt ${toString cfg.timer.minIntervalSec} ]; then
      echo "$(${pkgs.coreutils}/bin/date -Is) skip: last run was under ${toString cfg.timer.minIntervalSec}s ago"
      exit 0
    fi

    ${lib.optionalString (cfg.timer.randomizedDelaySec > 0) ''
      # Spread concurrent hosts off the same instant; small relative to the
      # interval on purpose, so the effective cadence stays roughly hourly.
      ${pkgs.coreutils}/bin/sleep "$(( RANDOM % ${toString (cfg.timer.randomizedDelaySec + 1)} ))"
    ''}

    ${lib.optionalString cfg.preflight.enable ''
      # ── preflight ────────────────────────────────────────────────────────
      # Can we open the repo at all? One cheap metadata call, not a trial
      # backup. Exit code is the signal, not the output: a fresh repo with
      # zero snapshots is reachable and must pass. Polls rather than failing
      # on the first miss, because the common cause is a laptop that woke
      # for launchd seconds before its NetBird overlay finished reconnecting
      # — a short wait converts that from a lost run into a normal one.
      #
      # A repo that is still unreachable at the end of the budget is NOT a
      # failure: no notification, no stamp (so the next slot retries rather
      # than being rate-limited away), exit 0.
      deadline=$(( $(${pkgs.coreutils}/bin/date +%s) + ${toString cfg.preflight.waitSec} ))
      until "$restic" snapshots --latest 1 --no-lock${cacertArg} >/dev/null 2>&1; do
        if [ "$(${pkgs.coreutils}/bin/date +%s)" -ge "$deadline" ]; then
          echo "$(${pkgs.coreutils}/bin/date -Is) skip: repo unreachable after ${toString cfg.preflight.waitSec}s; will retry next slot"
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 15
      done
    ''}

    # ── the backup ───────────────────────────────────────────────────────
    # -n: if another copy already holds the lock, leave rather than queueing
    # behind it — at this cadence the next slot is close, and a pile of
    # blocked runs is worse than a skipped one. -E 4 makes "could not take
    # the lock" exit 4, which restic never returns, so the wrapper below can
    # tell "someone else is backing up" (fine) from restic's own exit 1
    # (not fine) without racing to re-probe the lock.
    ${pkgs.flock}/bin/flock -n -E 4 ${lib.escapeShellArg lockFile} ${pkgs.writeShellScript "${label}-locked" ''
      set -u
      # --json's stdout stream goes only to progressFile (a status-widget
      # feed, e.g. an xbar plugin) — stderr still reaches StandardErrorPath
      # (this same log file) unredirected, so failures stay human-readable
      # there instead of buried in NDJSON.
      ${pkgs.restic}/bin/restic backup${pathArgs}${excludeArgs}${cacertArg} --json > ${lib.escapeShellArg progressFile}
      rc=$?
      # Stamp on the way out whether restic won or lost: a failing repo
      # should be retried next slot, not every time launchd twitches.
      ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg stampFile}
      exit $rc
    ''} || rc=$?
    rc=''${rc:-0}

    if [ "$rc" -eq 0 ]; then
      exit 0
    fi

    if [ "$rc" -eq 4 ]; then
      echo "$(${pkgs.coreutils}/bin/date -Is) skip: another ${label} run holds the lock"
      exit 0
    fi

    # restic exit 3 = "the snapshot was created, but some source files could
    # not be read". On macOS that is the PERMANENT steady state, not a fault:
    # a LaunchDaemon has no Full Disk Access, so every run trips over the
    # TCC-protected corners of ~/Library (Mail, Messages, Safari, HomeKit,
    # Group Containers/*, ...) and exits 3 with the backup itself complete.
    # Treating it as failure meant every single hourly run took the failure
    # path; verified live on a personal Mac 2026-09-18, 29 of 30 runs exited
    # 3 while the snapshots landed hourly exactly as intended.
    #
    # It is still worth one line in the log — a jump in the unreadable count
    # is how you would notice a NEW protected path — but it is not a
    # notification, and it is not a non-zero exit.
    if [ "$rc" -eq 3 ]; then
      echo "$(${pkgs.coreutils}/bin/date -Is) ok: snapshot created; some source files were unreadable (restic exit 3, expected under macOS TCC)"
      exit 0
    fi

    echo "$(${pkgs.coreutils}/bin/date -Is) restic exited $rc"
    ${lib.optionalString cfg.notify.enable ''
      # ── notification rate limit ────────────────────────────────────────
      # First failure notifies immediately; a persistent one repeats no more
      # than every notify.minIntervalSec. Without this an hourly job with a
      # broken credential posts a banner every hour until someone notices,
      # which trains you to dismiss it.
      if [ "$(age_of ${lib.escapeShellArg notifyStamp})" -ge ${toString cfg.notify.minIntervalSec} ]; then
        # Stamp the ATTEMPT, before delivering, and never mind whether the
        # banner lands. An earlier version stamped only on success, reasoning
        # that a failure nobody saw should not burn the suppression window.
        # That reasoning inverts the moment delivery is what is broken:
        # osascript from a LaunchDaemon needs an Automation (Apple Events)
        # grant, the prompt for it names this wrapper's bash, and an
        # unanswered prompt is a failed delivery — so the window never
        # engaged and the next slot prompted again, every hour, forever.
        # A rate limit whose own precondition is that the thing it limits
        # works is not a rate limit. The suppression window now holds
        # regardless, and the log still records every failure.
        ${pkgs.coreutils}/bin/touch ${lib.escapeShellArg notifyStamp}
        uid="$(/usr/bin/id -u ${cfg.username})"
        /bin/launchctl asuser "$uid" /usr/bin/osascript -e 'display notification "check ~/Library/Logs/${label}.log" with title "NAS backup failed" subtitle "${label}"' || true
      fi
    ''}
    exit 1
  '';
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

    cacertFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "./certs/home-ca-root.pem";
      description = ''
        PEM CA bundle passed as restic's `--cacert`, for a rest-server
        behind a private CA (macOS has no NixOS-style
        `security.pki.certificateFiles` to trust it system-wide, and
        --cacert is the narrowest fix — just this one restic invocation,
        not the whole OS). Pass a real path literal (e.g. `./certs/foo.pem`)
        so it's copied into the store as part of the closure, not a string.
      '';
    };

    timer = {
      hour = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 2;
        description = ''
          Hour (0-23, local time) the backup starts. `null` (the default)
          leaves launchd's Hour field unset, which it treats as a wildcard —
          i.e. the job fires every hour at `minute`. Set an integer to pin
          it to a single daily slot instead.
        '';
      };
      minute = lib.mkOption {
        type = lib.types.int;
        default = 0;
        description = "Minute the backup starts.";
      };
      randomizedDelaySec = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = ''
          Random jitter (seconds) added before the backup runs, so a
          sleeping laptop that wakes on schedule doesn't hammer the server
          at the same instant as every other host. Kept well under the
          interval on an hourly schedule — the point is to decorrelate
          hosts, not to smear one host's cadence.
        '';
      };
      minIntervalSec = lib.mkOption {
        type = lib.types.int;
        default = 2700;
        description = ''
          Floor on the gap between runs, measured from the end of the last
          run that reached restic. A start inside this window logs a skip
          and exits 0.

          This is what makes an hourly schedule self-limiting: launchd holds
          a calendar interval that fired while the job was busy and releases
          it the moment the job exits, so a run that overruns its slot would
          otherwise be followed instantly by another. Also absorbs manual
          `launchctl kickstart`s and daemon reloads landing near a scheduled
          run. Default 45min — under the hourly cadence (which jitter can
          pull in to ~55min) and far above any accidental double-fire.
        '';
      };
    };

    preflight = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Before backing up, poll the repo with one cheap metadata call for
          up to `waitSec`; if it never opens, log and exit 0 instead of
          failing. The NAS is reached over a NetBird overlay, and a laptop
          that wakes for launchd before the overlay reconnects cannot
          resolve it — an unreachable NAS is a "not now", not a fault, and
          at an hourly cadence the retry is a few minutes away.
        '';
      };
      waitSec = lib.mkOption {
        type = lib.types.int;
        default = 180;
        description = "How long preflight waits for the repo to become reachable before skipping the run.";
      };
    };

    notify = {
      enable =
        lib.mkEnableOption "a GUI notification in the logged-in session when a backup run fails"
        // {
          description = ''
            Post a GUI notification when a backup run genuinely fails.

            OFF by default on darwin, unlike the NixOS sibling, because the
            only delivery path available to a LaunchDaemon is `osascript`,
            and `display notification` from a daemon needs an Automation
            (Apple Events) grant. The permission prompt names this module's
            own wrapper — a content-addressed store path — so the grant does
            not survive a rebuild that changes the script, and the prompt
            comes back. A notifier that periodically demands to be
            re-authorised is worse than no notifier.

            Leave it off and let a status widget carry the signal: it derives
            staleness from the newest snapshot's age, needs no TCC grant at
            all, and is visible without interrupting anything. Turn this on
            only if you have a delivery path you are willing to keep
            authorised.
          '';
        };
      minIntervalSec = lib.mkOption {
        type = lib.types.int;
        default = 21600;
        description = ''
          Minimum gap between failure notifications. The first failure
          notifies immediately; a persistent one repeats at most this often
          rather than once per hourly run. Default 6h.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.restic];

    launchd.daemons.${label} = {
      serviceConfig = {
        UserName = cfg.username;
        StartCalendarInterval = [
          # Omitting Hour entirely is what makes this hourly — launchd treats
          # an absent field as "any". Setting it to a value would pin the job
          # to one slot a day, which is the timer.hour != null case.
          ({Minute = cfg.timer.minute;}
            // lib.optionalAttrs (cfg.timer.hour != null) {Hour = cfg.timer.hour;})
        ];
        RunAtLoad = false;
        # NOT /var/log: launchd opens these paths AS UserName (geoff), and
        # /var/log is root:wheel 0755 — a non-root LaunchDaemon can't create
        # a file there, so it fails closed with EX_CONFIG (78) before the
        # ProgramArguments even run, silently (no log file, no notification).
        # Confirmed live 2026-08-25. ~/Library/Logs is geoff-writable and
        # already exists as a standard per-user directory.
        StandardOutPath = "${logDir}/${label}.log";
        StandardErrorPath = "${logDir}/${label}.log";
        ProgramArguments = ["${backupScript}"];
      };
    };
  };
}
