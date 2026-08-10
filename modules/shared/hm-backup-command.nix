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
  # activation over a file that is already gone. It also makes the concurrent
  # case benign — if another activation moved the file first, there is nothing
  # left to back up and nothing to lose.
  [ -e "$target" ] || exit 0

  # $$ is in the candidate name, not just the loop, so two activations racing
  # each other cannot even SELECT the same destination. A bare timestamp has
  # second resolution: both would compute the same name, both would find it
  # free, and the loser's `mv` would overwrite the winner's backup — losing
  # the original content this whole file exists to preserve.
  stamp=$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)
  base="$target.pre-hm.$stamp.$$"

  backup="$base"
  n=0
  while true; do
    # RESERVE THE NAME ATOMICALLY, don't test-then-move. `ln` fails with EEXIST
    # in a single syscall, so the winner is decided by the kernel rather than
    # by who reaches `mv` first. The link puts the same inode at both paths;
    # unlinking the original completes the move. Same directory, so the
    # cross-device limitation of hard links never applies.
    if ${pkgs.coreutils}/bin/ln -- "$target" "$backup" 2>/dev/null; then
      ${pkgs.coreutils}/bin/rm -f -- "$target"
      break
    fi

    # `ln` also refuses directories, which home-manager can hand us when a real
    # directory sits where it wants to write a symlink. There is no atomic
    # rename-if-absent in POSIX shell, so fall back to a plain move — safe here
    # because $$ already makes this process's candidate name unique.
    if [ -d "$target" ] && [ ! -L "$target" ] && [ ! -e "$backup" ]; then
      ${pkgs.coreutils}/bin/mv -- "$target" "$backup"
      break
    fi

    # Someone else holds this name (or the target vanished under us). Try the
    # next one; re-check existence so a concurrent winner ends us cleanly.
    [ -e "$target" ] || exit 0
    n=$((n + 1))
    backup="$base-$n"
  done

  echo "hm-backup-file: moved '$target' to '$backup'" >&2
''
