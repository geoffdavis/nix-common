# The backup command home-manager runs when it finds an unmanaged file in the
# way of one it wants to write.
#
# WHY THIS EXISTS RATHER THAN `backupFileExtension`. A fixed extension names
# the backup deterministically, so the SECOND time the same path collides the
# destination is already occupied and activation ABORTS:
#
#   Existing file '<path>.pre-hm' would be clobbered by backing up '<path>'
#   Failed to start Home Manager environment for <user>
#
# The system generation still activates; only the home-manager unit fails, so
# it reads as a partial success and is easy to misdiagnose. It is also
# self-perpetuating: the stale backup is never consumed, so every later switch
# hits the same wall until someone moves the file by hand.
#
# `home-manager.overwriteBackup = true` would also unblock it, but by clobbering
# the older backup — which is the ORIGINAL pre-home-manager content, the copy
# most worth keeping. Losing user data silently to avoid an error is the same
# trade as `force = true`, just quieter.
#
# So: a runtime-unique name. Uniqueness has to be decided during activation,
# not evaluation — anything derived from the config (a revision, a hash) is
# fixed for the whole generation and collides on the second switch of it.
#
# INTERFACE (home-manager modules/files.nix): the command is invoked as
#   run $HOME_MANAGER_BACKUP_COMMAND "$targetPath"
# so the path arrives as the FINAL argument, and the variable is unquoted —
# a command with its own flags word-splits correctly. `run` is home-manager's
# dry-run wrapper, so this is echoed rather than executed under DRY_RUN.
pkgs:
pkgs.writeShellScript "hm-backup-file" ''
  set -eu

  target="''${1:?hm-backup-file: no target path given}"

  # home-manager only calls this for a path it has already seen exist, but a
  # missing file is a no-op rather than an error: failing here would abort an
  # activation over a file that is already gone.
  [ -e "$target" ] || exit 0

  stamp=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)
  backup="$target.pre-hm.$stamp"

  # Second-resolution stamps can repeat if two activations race, and a
  # clobbered backup is the bug this file exists to prevent — so find a free
  # name rather than trusting the timestamp to be unique.
  n=0
  while [ -e "$backup" ]; do
    n=$((n + 1))
    backup="$target.pre-hm.$stamp-$n"
  done

  ${pkgs.coreutils}/bin/mv -- "$target" "$backup"
  echo "hm-backup-file: moved '$target' to '$backup'" >&2
''
