# Shared CLI tooling, cross-platform (macOS + Linux).
# Imported from each host's home-manager user config.
{pkgs, ...}: {
  imports = [
    ./onepassword.nix
    ./terraform.nix
  ];

  home.sessionPath = ["$HOME/.local/bin"];

  home.packages = with pkgs; [
    # cloud / infra
    ansible
    azure-cli
    google-cloud-sdk
    azure-storage-azcopy
    awscli2
    cilium-cli
    cloudflared
    cosign
    crane
    fluxcd
    fluxcd-operator-mcp # MCP server for the Flux Operator (was the controlplaneio-fluxcd brew tap)
    kubernetes-helm
    jfrog-cli
    k9s
    opentofu
    pulumi
    # terraform itself is pinned via modules/home/terraform.nix (imported
    # above) so it tracks HashiCorp's stable channel rather than lagging
    # nixpkgs.
    talhelper
    talosctl
    terragrunt

    # git / source control
    gh
    git-filter-repo
    git-secrets
    gitleaks
    lazygit # git TUI

    # shells & terminal
    bashInteractive
    tmux
    pay-respects # `thefuck` replacement; nixpkgs dropped thefuck

    # languages / runtimes
    go
    go-task
    nodejs
    hugo

    # python tooling
    python312
    pipenv
    pipx
    pre-commit
    python3Packages.pytest
    uv

    # perl tooling
    perlPackages.Appcpanminus

    # general utilities
    bat # cat/pager with syntax highlighting; also colored MANPAGER (zsh.nix)
    btop
    dtc
    expect
    eza # iconified ls/tree, aliased over ls (zsh.nix)
    fastfetch # neofetch-like system info
    file # mime detection for the ff fzf preview (zsh.nix)
    fzf
    gnugrep
    gnumake
    gnupatch
    gum # confirm prompts in shell functions (gwd in zsh.nix)
    ipcalc
    jq
    lazydocker # docker/compose TUI
    markdownlint-cli
    mise
    ripgrep
    shellcheck # shell linter; used by pre-commit language:system hooks
    tree
    yamllint
    yq # kislyuk/yq (python): bare `yq .` emits JSON, which the CCoE
    # terraform aliases (tfcd/tfstackshow/y2j*) pipe into jq. mikefarah
    # yq-go's `yq .` prints YAML instead, breaking those `yq . | jq`
    # pipelines with "jq: parse error: Invalid numeric literal".

    # nix tooling
    alejandra
    deadnix
    statix

    # python linting (the runtime is python312 above)
    ruff

    # editor support
    # (neovim itself is provided by lazyvim-nix)
  ];
}
