#!/usr/bin/env bash
# Dump a host's hand-managed zsh state so the shared home-manager zsh module
# rollout can preserve anything worth keeping before HM moves *.pre-hm aside.
#
# Usage on the target host (one line):
#   curl -fsSL https://raw.githubusercontent.com/geoffdavis/nix-common/main/scripts/audit-zsh.sh | bash
#
# Output goes to /tmp/zsh-audit.log and (if `gh` is authenticated) is also
# uploaded to a secret gist whose URL is printed at the end. Paste that URL
# back to the operator running the rollout.
set -uo pipefail

LOG=/tmp/zsh-audit.log

{
  echo "=== host: $(hostname) ==="
  echo "=== uname: $(uname -a) ==="
  echo "=== date:  $(date) ==="
  echo "=== shell: ${SHELL:-unset}"
  echo

  echo "--- inventory ---"
  ls -la \
    ~/.zshrc ~/.zshenv ~/.zprofile ~/.zlogin ~/.zlogout \
    ~/.oh-my-zsh ~/.p10k.zsh ~/.zsh_history \
    ~/.aliases ~/.bashrc ~/.bash_profile \
    2>/dev/null
  echo

  for f in ~/.zshrc ~/.zshenv ~/.zprofile ~/.zlogin ~/.zlogout ~/.aliases; do
    if [ -f "$f" ]; then
      echo "--- $f ---"
      cat "$f"
      echo
    fi
  done

  if [ -d ~/.oh-my-zsh ]; then
    echo "--- ~/.oh-my-zsh/custom listing ---"
    ls -la ~/.oh-my-zsh/custom 2>/dev/null
    echo "--- ~/.oh-my-zsh/custom/plugins listing ---"
    ls -la ~/.oh-my-zsh/custom/plugins 2>/dev/null
    echo "--- ~/.oh-my-zsh/custom/themes listing ---"
    ls -la ~/.oh-my-zsh/custom/themes 2>/dev/null
    echo
    echo "--- ~/.oh-my-zsh/custom contents (non-default) ---"
    while IFS= read -r -d '' file; do
      case "$(basename "$file")" in
        example.zsh) continue ;;
      esac
      echo ">>> $file"
      cat "$file"
      echo
    done < <(find ~/.oh-my-zsh/custom -type f \( -name '*.zsh' -o -name '*.zsh-theme' \) -print0 2>/dev/null)
  fi
} > "$LOG" 2>&1

cat "$LOG"
echo
echo "=== audit log: $LOG ==="

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  echo "Uploading to a secret gist..."
  gh gist create --filename "$(hostname)-zsh-audit.log" "$LOG"
else
  echo "(gh unavailable / not authenticated — paste $LOG contents manually)"
fi
