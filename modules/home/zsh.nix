{lib, ...}: {
  programs.zsh = {
    enable = true;
    oh-my-zsh = {
      enable = true;
      theme = lib.mkDefault "agnoster";
      plugins = ["git" "python" "terraform"];
    };

    # Shared interactive aliases + functions. Curated subset originally
    # subsetted from oceaneering's CCOE .bash_aliases for viasat-laptop;
    # promoted to shared so every host gets the same baseline. On hosts
    # whose own initContent sources a fuller alias file (e.g. oceaneering's
    # CCOE bundle) the later source wins, so per-host supersets still
    # override these definitions.
    initContent = ''
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
    '';
  };
}
