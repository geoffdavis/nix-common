# modules/shell/interactive-aliases.nix — the shared interactive zsh
# aliases/functions, as a single source of truth for BOTH consumers:
#   - home/zsh.nix (workstation, via home-manager `initContent`)
#   - nix-personal's modules/nas/shell.nix (headless NAS, via the NixOS
#     `programs.zsh` at the SYSTEM level, since FreeIPA users have no HM)
# exposed on the flake as `lib.zshInteractiveInit`.
#
# `profile`:
#   "workstation" (default) — the full set, unchanged from the original
#     home/zsh.nix block.
#   "nas" — the core subset; drops the workstation-only bits (terraform,
#     azure, and the tmux dev-layout functions) that reference tooling a
#     NAS doesn't carry.
#
# Escaping note: this is a zsh script in a Nix '' string — `''${...}` is a
# literal ''${...} to zsh, and `${...}` interpolates in Nix.
{
  pkgs,
  lib ? pkgs.lib,
  profile ? "workstation",
}: let
  # Core — every host. (git/omz provide the git aliases; this is the custom
  # layer on top.)
  core = ''
    alias reporoot='echo "$(git rev-parse --show-toplevel)"'
    alias cdreporoot='cd "$(git rev-parse --show-toplevel)"'

    gw() {
      local dir
      dir=$(git worktree list | fzf | awk '{print $1}')
      [ -n "$dir" ] && cd "$dir"
    }

    alias year='date +"%Y"'
    alias month='date +"%m"'
    alias day='date +"%d"'

    alias getipi='curl ipv4.icanhazip.com'
    alias getip6='curl icanhazip.com'

    alias pc='pre-commit'
    alias pci='pre-commit install'
    alias pcu='pre-commit autoupdate'
    alias pcr='pre-commit run --all-files'

    alias ghh='githelp'
    alias ghi='gh issue'
    alias ghil='gh issue list'
    alias ghiv='gh issue view'
    alias ghivw='gh issue view --web'
    alias ghivnt="gh issue view --json number,title --template '#{{.number}} {{.title}}'"
    alias ghilw='gh issue list --web'
    alias ghic='gh issue create'
    alias ghiassign='gh issue edit --add-assignee'
    alias ghia='gh issue edit --add-assignee'
    alias ghiassignme='gh issue edit --add-assignee @me'
    alias ghiame='gh issue edit --add-assignee @me'
    alias ghiunassign='gh issue edit --remove-assignee'
    alias ghiunassignme='gh issue edit --remove-assignee @me'
    alias ghidev='gh issue develop'
    alias ghidevco='gh issue develop --checkout'
    alias ghilabel='gh issue edit --add-label'
    alias ghiremovelabel='gh issue edit --remove-label'
    alias ghilabel_app-owner-request='gh issue edit --add-label app-owner-request'
    alias ghilabel_enhancement='gh issue edit --add-label enhancement'
    alias ghilabel_bug='gh issue edit --add-label bug'
    alias ghilabel_documentation='gh issue edit --add-label documentation'
    alias ghilabel_security='gh issue edit --add-label security'
    alias ghilabel_initial-implementation='gh issue edit --add-label initial-implementation'
    alias ghilabel_question='gh issue edit --add-label question'
    alias ghilabel_chore='gh issue edit --add-label chore'
    alias ghilabel_help-wanted='gh issue edit --add-label help-wanted'
    alias ghpr='gh pr'
    alias ghprl='gh pr list'
    alias ghprlw='gh pr list --web'
    alias ghprc='gh pr checks'
    alias ghprcl='gh pr close'
    alias ghprcr='gh pr create'
    alias ghprcm='gh pr comment'
    alias ghprco='gh pr checkout'
    alias ghprub='gh pr update-branch'
    alias ghprm='gh pr merge'
    alias ghprms='gh pr merge --squash'
    alias ghprmsd='gh pr merge --squash --delete-branch'
    alias ghprv='gh pr view'
    alias ghprvw='gh pr view --web'
    alias ghw='gh workflow'
    alias ghwl='gh workflow list'
    alias ghwr='gh workflow run'
    alias ghr='gh run'
    alias ghrw='gh run watch'

    # GitHub Copilot assignment
    alias ghiassigncopilot='gh issue edit --add-assignee @copilot'
    alias ghiacopilot='gh issue edit --add-assignee @copilot'
    alias ghiunassigncopilot='gh issue edit --remove-assignee @copilot'

    # git extras not in oh-my-zsh git plugin
    alias grbom='git rebase origin/main'

    # ---- Omarchy-inspired layer (adapted from basecamp/omarchy
    # default/bash; ported bash->zsh, collisions with the oh-my-zsh git
    # plugin renamed, tool deps swapped for what cli-tools ships). ----

    # eza over ls: long listings, dirs first, icons; lt = git-aware tree.
    alias ls='eza -lh --group-directories-first --icons=auto'
    alias lsa='ls -a'
    alias lt='eza --tree --level=2 --long --icons --git'
    alias lta='lt -a'

    # fzf pickers with bat previews; kitty additionally gets inline image
    # previews via icat. eff opens the pick in $EDITOR; sff scps it.
    if [[ "$TERM" == "xterm-kitty" ]]; then
      alias ff="fzf --preview 'case \$(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=\''${FZF_PREVIEW_COLUMNS}x\''${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'"
    else
      alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
    fi
    alias eff='$EDITOR "$(ff)"'
    # (upstream sorts candidates by mtime via GNU find -printf; dropped
    # for BSD-find/macOS portability)
    sff() {
      if [ $# -eq 0 ]; then
        echo "Usage: sff <destination> (e.g. sff host:/tmp/)"
        return 1
      fi
      local file
      file=$(find . -type f 2>/dev/null | ff) && [ -n "$file" ] && scp "$file" "$1"
    }

    # Colored man pages via bat.
    export BAT_THEME=ansi
    export MANROFFOPT="-c"
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"

    # zoxide owns cd: real paths behave exactly like cd; misses fall
    # through to a frecency jump (with the landing dir echoed back).
    zd() {
      if (( $# == 0 )); then
        builtin cd ~ || return
      elif [[ -d $1 ]]; then
        builtin cd "$1" || return
      else
        if ! z "$@"; then
          echo "zd: no match: $*" >&2
          return 1
        fi
        printf "\U000F17A9 "
        pwd
      fi
    }
    alias cd='zd'
    ${lib.optionalString pkgs.stdenv.isLinux ''
      # macOS ships a native `open`; give Linux the same verb.
      open() (
        xdg-open "$@" >/dev/null 2>&1 &
      )
    ''}
    # Worktree trio: gw (above) fzf-jumps between worktrees; gwa creates
    # a sibling ../repo--branch worktree+branch and enters it; gwd removes
    # the current one (and its branch) after a gum confirm. Named gw* —
    # upstream's ga/gd collide with oh-my-zsh git add/diff aliases.
    gwa() {
      if [[ -z "$1" ]]; then
        echo "Usage: gwa <branch>"
        return 1
      fi
      local branch="$1"
      local base="$(basename "$PWD")"
      local wt_path="../''${base}--''${branch}"
      git worktree add -b "$branch" "$wt_path" && cd "$wt_path"
    }
    gwd() {
      gum confirm "Remove worktree and branch?" || return
      local cwd worktree root branch
      cwd="$(pwd)"
      worktree="$(basename "$cwd")"
      root="''${worktree%%--*}"
      branch="''${worktree#*--}"
      # only act when the dir matches the repo--branch worktree pattern
      if [[ "$root" != "$worktree" ]]; then
        cd "../$root" || return
        git worktree remove "$cwd" --force || return 1
        git branch -D "$branch"
      fi
    }

    # tmux: t attaches to (or starts) the Work session.
    alias t='tmux attach || tmux new -s Work'

    # pay-respects (the thefuck replacement in cli-tools) is inert without
    # this hook — the binary just sits on PATH. Evaluating its init defines
    # the `f` alias (correct the previous command) and an inline-correction
    # keybinding (^X^X). --nocnf suppresses its command_not_found_handler so
    # it doesn't fight homeModules.nix-index for that hook: pay-respects fixes
    # typos, nix-index names the nixpkgs package providing a missing command.
    # Guarded so the module stays usable on hosts that don't ship the binary.
    command -v pay-respects >/dev/null && eval "$(pay-respects zsh --nocnf)"
  '';

  # Workstation-only — terraform/azure helpers and the tmux dev-layout
  # functions. Reference tooling a NAS doesn't carry, so profile="nas" omits
  # them. (Appended after core; alias/function definition order is immaterial,
  # so the workstation shell is semantically unchanged.)
  workstationExtras = ''
    # terraform utilities (basic aliases provided by oh-my-zsh terraform plugin)
    alias tm=terramate
    alias tf_get_lock_id='terraform plan 2>&1 | grep ID | rev | cut -d" " -f1 | rev'
    tf_force_unlock() {
      local lock_id
      lock_id=$(tf_get_lock_id)
      terraform force-unlock "$lock_id"
    }
    alias tf_fu='tf_force_unlock'

    set_arm_subscription_id() {
      export ARM_SUBSCRIPTION_ID="$(az account show --query 'id' -o tsv)"
    }

    tfctx() {
      echo "Cloud:               $(az cloud show --query name -o tsv 2>/dev/null || echo unknown)"
      echo "Subscription:        $(az account show --query name -o tsv 2>/dev/null || echo unknown)"
      echo "Subscription ID:     $(az account show --query id -o tsv 2>/dev/null || echo unknown)"
      echo "Workspace:           $(terraform workspace show 2>/dev/null || echo unknown)"
      echo "ARM_SUBSCRIPTION_ID: $ARM_SUBSCRIPTION_ID"
    }

    # Tmux Dev Layout: editor (top-left) + AI column (right) + terminal
    # strip (bottom). Usage: tdl <ai-cmd> [<second-ai-cmd>]
    tdl() {
      [[ -z $1 ]] && { echo "Usage: tdl <ai-cmd> [<second-ai-cmd>]"; return 1; }
      [[ -z $TMUX ]] && { echo "tdl requires a tmux session."; return 1; }
      local current_dir="$PWD" editor_pane ai_pane ai2_pane
      local ai="$1" ai2="$2"
      editor_pane="$TMUX_PANE"
      tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"
      tmux split-window -v -l '15%' -t "$editor_pane" -c "$current_dir"
      ai_pane=$(tmux split-window -h -l '30%' -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
      if [[ -n $ai2 ]]; then
        ai2_pane=$(tmux split-window -v -t "$ai_pane" -c "$current_dir" -P -F '#{pane_id}')
        tmux send-keys -t "$ai2_pane" "$ai2" C-m
      fi
      tmux send-keys -t "$ai_pane" "$ai" C-m
      tmux send-keys -t "$editor_pane" "$EDITOR ." C-m
      # focus the editor (upstream selects an unset variable here)
      tmux select-pane -t "$editor_pane"
    }

    # Tmux Dev Square: editor / live-diff / terminal / AI quadrants.
    # Usage: tds [<ai-cmd>] (default claude). The diff pane is a plain
    # color git-diff loop (upstream uses their `hunk` watcher).
    tds() {
      [[ -z $TMUX ]] && { echo "tds requires a tmux session."; return 1; }
      local current_dir="$PWD" editor_pane diff_pane terminal_pane ai_pane
      local ai="''${1:-claude}"
      editor_pane="$TMUX_PANE"
      tmux rename-window -t "$editor_pane" "$(basename "$current_dir")"
      terminal_pane=$(tmux split-window -v -l '50%' -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
      diff_pane=$(tmux split-window -h -l '50%' -t "$editor_pane" -c "$current_dir" -P -F '#{pane_id}')
      ai_pane=$(tmux split-window -h -l '50%' -t "$terminal_pane" -c "$current_dir" -P -F '#{pane_id}')
      tmux send-keys -t "$editor_pane" "$EDITOR ." C-m
      tmux send-keys -t "$diff_pane" 'while :; do clear; git -c color.ui=always diff | head -n "$LINES"; sleep 2; done' C-m
      tmux send-keys -t "$ai_pane" "$ai" C-m
      tmux select-pane -t "$editor_pane"
    }

    # One tdl window per subdirectory of the cwd. Usage: tdlm <ai-cmd> [<ai2>]
    tdlm() {
      [[ -z $1 ]] && { echo "Usage: tdlm <ai-cmd> [<second-ai-cmd>]"; return 1; }
      [[ -z $TMUX ]] && { echo "tdlm requires a tmux session."; return 1; }
      local ai="$1" ai2="$2" base_dir="$PWD" first=true
      # tmux session names disallow dots/colons
      tmux rename-session "$(basename "$base_dir" | tr '.:' '--')"
      local dir dirpath pane_id
      for dir in "$base_dir"/*/; do
        [[ -d $dir ]] || continue
        dirpath="''${dir%/}"
        if $first; then
          tmux send-keys -t "$TMUX_PANE" "cd '$dirpath' && tdl $ai $ai2" C-m
          first=false
        else
          pane_id=$(tmux new-window -c "$dirpath" -P -F '#{pane_id}')
          tmux send-keys -t "$pane_id" "tdl $ai $ai2" C-m
        fi
      done
    }

    # Swarm layout: N tiled panes all running the same command.
    # Usage: tsl <pane-count> <command>
    tsl() {
      [[ -z $1 || -z $2 ]] && { echo "Usage: tsl <pane-count> <command>"; return 1; }
      [[ -z $TMUX ]] && { echo "tsl requires a tmux session."; return 1; }
      local count="$1" cmd="$2" current_dir="$PWD" new_pane pane
      local -a panes
      tmux rename-window -t "$TMUX_PANE" "$(basename "$current_dir")"
      panes+=("$TMUX_PANE")
      # NB zsh arrays are 1-indexed (upstream bash uses panes[0])
      while (( ''${#panes[@]} < count )); do
        new_pane=$(tmux split-window -h -t "''${panes[-1]}" -c "$current_dir" -P -F '#{pane_id}')
        panes+=("$new_pane")
        tmux select-layout -t "''${panes[1]}" tiled
      done
      for pane in "''${panes[@]}"; do
        tmux send-keys -t "$pane" "$cmd" C-m
      done
      tmux select-pane -t "''${panes[1]}"
    }
  '';
in
  core + lib.optionalString (profile == "workstation") workstationExtras
